local fs = require("filesystem")
local serial = require("serialization")
local computer = require("computer")
local event = require("event")
local core = {
  languages = {
    ["eu_EN"] = "English",
    ["eu_RU"] = "Русский",
  },
  langPath = "/MaynerOS Donate/Lang/",
  guidePath = "/MaynerOS Donate/Guide/",
  associations = {
      txt = "EDIT",
      lua = "EXECUTE",
      bin = "EDIT",
      cfg = "EDIT",
  },
  settings = {},
  lowMemory = false,
  memoryCheckTimeout = 10,
}

local settingsProxy = { -- СЮДА МЕТАТАБЛИЦУ НЕ СТАВИТЬ!
  language = "eu_EN",
  userInit = false,
  timezone = 0,
}
setmetatable(core.settings,{
  __index = function(self, key)
    if not settingsProxy[key] then settingsProxy[key] = core[key] end
    return settingsProxy[key]
  end,
  __newindex = function(self,key,value)
    rawset(settingsProxy,key,value)
    core.saveSettings()
  end,
  __pairs = function(self)
    return pairs(settingsProxy)
  end,
  __ipairs = function(self)
    return ipairs(settingsProxy)
  end,
  __len = function(self)
    return #settingsProxy
  end,
  __name = "TabletOS Settings Proxy",
  __metatable = "Protected metatable of TabletOS Settings Proxy.",
})
setmetatable(core.languages,{
  __index = function(self,key)
    if rawget(self,key) then return rawget(self,key) end
    return key
  end
})

function core.loadLanguage(lang)
  core.settings.language = lang
  local package = {}
  for dir in fs.list(core.settings.langPath) do
    if dir:sub(-1,-1) == "/" then
      local path = core.settings.langPath .. dir .. lang .. ".lang"
      if fs.exists(path) then
        for line in io.lines(path) do
          local key, value = line:match("\"(.+)\"%s\"(.+)\"")
          if key then
            package[dir:sub(1,-2) .. "_" .. key] = value
          end
        end
      end
    end
  end
  setmetatable(package,{
    __index = function(self,key)
      if rawget(self,key) then return rawget(self,key) end
      return "lang." .. key
    end
  })
  core.package = package
  computer.pushSignal("REDRAW_ALL")
end

function core.getLanguagePackages() return core.package end

function core.saveData(name,data)
  checkArg(2,data,"table")
  checkArg(1,name,"string")
  data = serial.serialize(data)
  local path = fs.concat("/TabletOS/db/",name)
  fs.makeDirectory("/TabletOS/db/")
  local handle, reason = io.open(path,"w")
  if not handle then return nil, reason end
  handle:write(data)
  handle:close()
  return true
end
function core.readData(name)
  checkArg(1,name,"string")
  local path = fs.concat("/TabletOS/db/",name)
  local handle, reason = io.open(path,"r")
  if not handle then return nil, reason end
  local buffer = ""
  repeat
    local data,reason = handle:read()
    if data then buffer = buffer .. data end
    if not data and reason then handle:close() return nil, reason end
  until not data
  handle:close()
  return serial.unserialize(buffer)
end

function core.getEditTime(path)
  local t_correction = (tonumber(core.settings.timezone) or 0) * 3600
  local lastmod = fs.lastModified(path) + t_correction
  local data = os.date('%d.%m.%Y', lastmod)
  local time = os.date('%X', lastmod)
  return data, time, lastmod
end
function core.getTime()
  local f = io.open("/.UNIX","w")
  f:write(" ")
  f:close()
  local _1 = {core.getEditTime("/.UNIX")}
  fs.remove("/.UNIX")
  return table.unpack(_1)
end
local notifications = {}
function core.newNotification(priority,icon,name,description,qrcodewords)
  local notification = {priority=priority,icon=icon,name=name,description=description,created=computer.uptime(),qrcodewords = qrcodewords}
  table.insert(notifications,notification)
  table.sort(notifications,function(a,b) return a.priority > b.priority end)
end


function core.getNotifications() 
  return notifications 
end
function core.removeNotification(index)
  table.remove(notifications,index)
end

function core.showGuide(name)
  if not core.settings["guide"..name.."Displayed"] and core.settings.userInit then
    local tbl = dofile(fs.concat(core.guidePath,name)..".lua")
    local guide = tbl[core.settings.language]
    core.newNotification(0,guide.icon,guide.name,guide.description,guide.qrcodewords)
    core.settings["guide"..name.."Displayed"] = true
  end
end

local priors = {
  "Verbose",
  "Debug",
  "Info",
  "Warning",
  "Error",
  "Fatal",
  "Slient",
}
function core.log(priority,app,log)
  priority = priority > 1 and (priority < 7 and priority or 6) and priority or 2
  priority = priors[priority]
  local str = "[" .. ({core.getTime()})[2] .. "] [" .. tostring(priority) .. "] " .. app .. ": " .. log .. "\n"
  local f = io.open("/TabletOS/logs.log","a")
  f:write(str)
  f:close()
end
function core.pcall(...)
  local result = {pcall(...)}
  if not result[1] then
    local str = "ERROR IN "
    for i = 2, #{...} do
      str = str .. tostring(({...})[i]) .. " "
    end
    str = str .. " REASON: " .. tostring(result[2]) .. "\n"
    local app = "CORE_PCALL"
    for i = 1, #{...} do
      if ({...})[i] == tostring(({...})[i]) then app = ({...})[i] break end
    end
    if fs.exists(app) then app = fs.name(app) end
    core.log(4,app,str)
  end
  return table.unpack(result)
end

local function serialize(tbl)
  local text = serial.serialize(tbl)
  text = text:gsub("\"","\5")
  return text
end

local function unserialize(unserTbl)
  local tbl = unserTbl:gsub("\5","\"")
  return serial.unserialize(tbl)
end

local function findTypeAndConvertFromString(value)
  if tonumber(value) then return tonumber(value) end
  if value == "true" then return true elseif value == "false" then return false end
  return unserialize(value)
end

function core.saveSettings()
  local str = ""
  for key, value in pairs(settingsProxy) do
    local _value = value
    if type(value) == "table" or type(value) == "string" then
      _value = serialize(value)
    end
    str = str .. "\"" .. tostring(key) .. "\" \"" .. tostring(_value) .. "\"\n"
  end
  fs.makeDirectory("/TabletOS/")
  local f,r = io.open("/TabletOS/settings.bin","w")
  if not f then return f, r end
  f:write(str)
  f:close()
  return true
end

function core.resetSettings(save)
  if not save then
    settingsProxy = {
      language = "eu_EN",
      langPath = "/TabletOS/Lang/",
    }
  end
  return core.saveSettings()
end

function core.init()
  local settings = {}
  if fs.exists("/TabletOS/settings.bin") then
    for line in io.lines("/TabletOS/settings.bin") do
      local key, value = line:match("\"(.+)\"%s\"(.+)\"")
      if key then
        settings[key] = findTypeAndConvertFromString(value)
      end
    end
    settingsProxy = settings
  else
    core.resetSettings()
  end
  core.loadLanguage(core.settings.language)
  fs.remove("/TabletOS/logs.log")
end

function core.getPackageDirectory()
  for i = 1, math.huge do
    local result = debug.getinfo(i)
    if result and result.what == "main" then
      local path = result.source
      if type(path) == "string" then
        if path:find(".pkg") then
          local left,right = path:find(".pkg")
          return path:sub(2,right) .. "/"
        else
          return nil, "Not a package", path:sub(2)
        end
      end
    end
  end
end

function core.executeFile(path)
  if type(path) ~= "string" then return end
  if path:sub(-4) == ".pkg" then
    local fileToExecute = fs.concat(path,"Main.lua")
    local success, reason = core.pcall(dofile,fileToExecute)
    if errorReport then
      errorReport(path,success,reason)
    end
    return success, reason
  else
    local success, reason = core.pcall(dofile,path)
    if errorReport then
      errorReport(path,success,reason)
    end
    return success, reason
  end
end

local lastLowMemory = 0
local lowMemoryCounter = 0
local highMemoryCounter = 0
function core.memorySpectre()
  local free = computer.freeMemory()
  if free < 65536 then
    lowMemoryCounter = lowMemoryCounter + 1
    highMemoryCounter = 0
    if lowMemoryCounter > 3 and lastLowMemory + core.memoryCheckTimeout < computer.uptime() then
      lastLowMemory = computer.uptime()
      if not core.lowMemory then
        core.lowMemory = true
        core.showGuide("LowMemory")
      end
      lowMemoryCounter = 0
    end
  elseif lastLowMemory + core.memoryCheckTimeout < computer.uptime() then
    lowMemoryCounter = 0
    highMemoryCounter = highMemoryCounter + 1
    if highMemoryCounter > 3 then
      --core.newNotification(0,"N","Normal memory level","TabletOS enabled animations")
      core.lowMemory = false
      highMemoryCounter = 0
    end
  end
end
event.timer(0.25,function() core.memorySpectre() end,math.huge)
core.init()
return core
