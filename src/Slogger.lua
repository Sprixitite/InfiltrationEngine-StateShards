--[[
	Slogger, yet another minimal Lua logging module
	Log function + post-init function are configurable, for dealing with the slog that is lua version compatibility
	
	Tested to be compatible with Lua5.1
	Presumed compatible with Lua5.2-5.5/Luajit/Luau
	
	© Sprixitite, 2025
]]

local slogger = {}

local sloggerCfg = {
	postInit = function(tbl) return tbl end,
	logFunc = print
}

local function varargs(...)
	local argCount = select('#', ...)
	local argTbl = { ... }
	local i = 0
	return function()
		i = i + 1
		if i <= argCount then return i, argTbl[i], argCount end
	end, argTbl
end

function slogger.new(...)
	local loggerPrefix = ""
	local varargsIter, argsTbl = varargs(...)
	
	for i, arg in varargsIter do
		loggerPrefix = loggerPrefix .. tostring(arg) .. " : "
	end
	
	local doWarn = function(tbl, ...)
		local finalMsg = ""
		
		for i, arg, argCount in varargs(...) do
			finalMsg = finalMsg .. tostring(arg)
			if i ~= argCount then
				finalMsg = finalMsg .. " : "
			end
		end
		
		sloggerCfg.logFunc(loggerPrefix .. finalMsg)
	end
	
	local specialize = function(...)
		return slogger.new(unpack(argsTbl), ...)
	end
	
	local newLogger = setmetatable({ specialize = specialize }, {__call = doWarn})
	return sloggerCfg.postInit(newLogger)
end

function slogger.init(cfg)
	for k, v in pairs(cfg) do
		if type(sloggerCfg[k]) == type(v) then
			sloggerCfg[k] = v
		end
	end
	return slogger
end

return slogger