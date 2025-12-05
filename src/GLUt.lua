--[[
	GLUt // GoodLuaUtilities // Lua5.1 utilities module
	
	© Sprixitite, 2025
]]

local GLUt = {}

local GLUtCfg = {
	print = print,
	warn  = function(...) print("WARNING", ...) end,
	error = error,
	type  = type
}

local patternSpecChars = { '(', ')', '.', '%', '+', '-', '*', '?', '[', ']', '^', '$' }

function GLUt.configure(tbl)
	for k, v in pairs(tbl) do
		if GLUtCfg[k] ~= nil then
			GLUtCfg[k] = v
		else
			GLUtCfg.warn("Attempt to set invalid GLUtCfg Key \"" .. tostring(k) .. "\"")
		end
	end
end

function GLUt.default(arg, default)
	return (arg == nil) and default or arg
end

function GLUt.default_exec(arg, fn)
	return (arg == nil) and fn() or arg
end

function GLUt.default_typed(arg, default, argName, funcName)
	local argType = GLUtCfg.type(arg)
	local defaultType = GLUtCfg.type(default)
	if argType == defaultType then return arg end
	if argType == "nil" then return default end
	GLUt.type_warn(argName, funcName, defaultType, argType)
	return default
end

function GLUt.type_warn(argName, funcName, expected, got, isErr)
	if argName == nil or expected == got then return end
	isErr = GLUt.default(isErr, false)

	local logFun = isErr and GLUtCfg.error or GLUtCfg.warn

	local warnStart = GLUt.type_is(funcName, "string") and (funcName .. ": expected arg \"") or "Expected arg \""
	logFun(warnStart .. argName .. "\" of type \"" .. expected .. "\" got type \"" .. got .. "\"!")
	logFun("Traceback: " .. debug.traceback())
end

function GLUt.type_check(arg, expected, argName, funcName, isErr)
	isErr = GLUt.default(isErr, false)
	local argType = GLUtCfg.type(arg)

	expected = string.gsub(expected, '?', "|nil")
	for _, validType in pairs(GLUt.str_split(expected, '|')) do
		if validType == argType then return true end
	end

	GLUt.type_warn(argName, funcName, expected, argType, isErr)

	return false
end

function GLUt.type_is(a1, t)
	return GLUtCfg.type(a1) == t
end

function GLUt.type_eq(a1, a2)
	return GLUtCfg.type(a1) == GLUtCfg.type(a2)
end

function GLUt.vararg_capture(...)
	local n = select('#', ...)
	return n, { ... }
end

function GLUt.vararg_iter(...)
	local n, t = GLUt.vararg_capture(...)
	local i = 0
	return function()
		i = i + 1
		if i <= n then return i, t[i], n end
	end, t
end

function GLUt.str_split(str, separator)
	str = str .. separator
	separator = GLUt.str_escape_pattern(separator)

	local substrs = {}
	for substr in string.gmatch(str, "(.-)" .. separator) do
		substrs[#substrs+1] = substr
	end
	return substrs
end

function GLUt.str_has_match(str, pattern)
	return string.match(str, pattern) ~= nil
end

function GLUt.str_escape_pattern(str)
	local escaped = str
	for _, specChar in ipairs(patternSpecChars) do
		local escapedSpec = '%' .. specChar
		escaped = string.gsub(escaped, escapedSpec, (specChar == '%') and "%%" or '%' .. escapedSpec)
	end
	return escaped
end

function GLUt.str_double_substr(str, substr)
	local safe = GLUt.str_escape_pattern(substr)
	return string.gsub(str, safe, safe .. safe)
end

function GLUt.str_isempty(str)
	return string.match(str, "^%s$") ~= nil
end

function GLUt.str_chariter(str)
	local n = #str
	local i = 0
	return function()
		i = i + 1
		if i <= n then return GLUt.str_getchar(str, i) end
	end
end

function GLUt.str_trim(str, pattern)
	pattern = GLUt.default(pattern, "%s")
	return GLUt.str_trimend(GLUt.str_trimstart(str, pattern), pattern)
end

function GLUt.str_trimstart(str, pattern)
	pattern = GLUt.default(pattern, "%s")
	return string.gsub(str, '^' .. pattern, "")
end

function GLUt.str_trimend(str, pattern)
	pattern = GLUt.default(pattern, "%s")
	return string.gsub(str, pattern .. '$', "")
end

function GLUt.str_getchar(str, i)
	return string.sub(str, i, i)
end

local unidentified = -1
function GLUt.str_runlua(source, fenv, chunkName)
	chunkName = GLUt.default_exec(chunkName, function()
		unidentified = unidentified + 1
		return "loadstring#" .. tostring(unidentified) 
	end)

	local strFun, failReason = loadstring(source, chunkName)
	if GLUtCfg.type(strFun) ~= "function" then
		return false, "Loadstring : " .. chunkName .. " : Evaluation failed : " .. failReason
	end

	strFun = setfenv(strFun, fenv)

	return pcall(function()
		return GLUt.vararg_capture(strFun())
	end)
end

function GLUt.str_runlua_unsafe(source, chunkName)
	local strFun, failReason = loadstring(source, chunkName)
	if GLUtCfg.type(strFun) ~= "function" then
		return false, "Loadstring : " .. chunkName .. " : Evaluation failed : " .. failReason
	end

	return pcall(function()
		return GLUt.vararg_capture()
	end)
end

function GLUt.kvp_tostring(k, v)
	return tostring(k) .. " = " .. tostring(v)
end

function GLUt.tbl_tryindex(tbl, ...)
	local indexing = tbl
	for _, k in GLUt.vararg_iter(...) do
		if GLUtCfg.type(indexing) ~= "table" then
			return false, indexing
		end
		indexing = indexing[tostring(k)]
	end

	return true, indexing
end

function GLUt.tbl_deepget(tbl, create_missing, ...)
	local indexing = tbl
	for i, k, n in GLUt.vararg_iter(...) do
		k = tostring(k)

		if indexing[k] == nil and create_missing then
			indexing[k] = {}
		end

		indexing = indexing[k]
		if GLUtCfg.type(indexing) ~= "table" and not (i == n) then
			return false, indexing, k
		end
	end

	return true, indexing
end

function GLUt.tbl_getkeys(tbl)
	local keys = {}
	for k, _ in pairs(tbl) do keys[#keys+1] = k end
	return keys
end

function GLUt.tbl_clone(tbl, shallow)
	shallow = GLUt.default(shallow, false)

	local cloned = {}
	for k, v in pairs(tbl) do
		if GLUtCfg.type(v) == "table" and not shallow then
			cloned[k] = GLUt.tbl_clone(v, shallow)
		else
			cloned[k] = v
		end
	end
	return cloned
end

function GLUt.tbl_merge(tbl1, tbl2, priority)
	priority = GLUt.default(priority, 1)
	local secondPriority = priority == 2
	local merged = {}
	for k, v in pairs(tbl1) do
		merged[k] = v
	end
	for k, v in pairs(tbl2) do
		local existing = merged[k]
		if GLUtCfg.type(existing) == "table" then
			merged[k] = GLUt.tbl_merge(existing, v, priority)
		elseif existing ~= nil and secondPriority then
			merged[k] = v
		elseif merged[k] == nil then
			merged[k] = v
		end
	end
	return merged
end

function GLUt.tbl_findsize(tbl)
	local i = 0
	for _, _ in pairs(tbl) do i = i + 1 end
	return i
end

local function tbl_tostring(tblName, tbl, levels, level)
	local str = tblName .. " = {"
	local indent = string.rep("  ", level)
	local n = GLUt.tbl_findsize(tbl)
	local i = 0
	for k, v in pairs(tbl) do
		i = i + 1
		str = str .. '\n' .. indent
		if GLUtCfg.type(v) == "table" and levels > level then
			str = str .. tbl_tostring(k, v, levels, level+1)
		else
			str = str .. GLUt.kvp_tostring(k, v)
		end
		if i < n then str = str .. ',' end
	end
	return str
end

function GLUt.tbl_tostring(tbl, levels, tblName)
	GLUt.default(tblName, tostring(tbl))
	return tbl_tostring(tblName, tbl, levels, 1)
end

function GLUt.tbl_any(tbl, f)
	local anySucceed = nil
	for k, v in pairs(tbl) do
		anySucceed = GLUt.default(anySucceed, false) or f(k, v)
		if anySucceed then break end
	end
	return anySucceed
end

function GLUt.tbl_all(tbl, f)
	local allSucceed = nil
	for k, v in pairs(tbl) do
		allSucceed = GLUt.default(allSucceed, true) and f(k, v)
		if not allSucceed then break end
	end
	return allSucceed
end

function GLUt.tbl_is_arr(tbl)
	local isArr = true
	for k, v in pairs(tbl) do
		isArr = isArr and GLUtCfg.type(k) == "number"
		if not isArr then break end
	end
	return isArr
end

local function tbl_arginfo(argType, name, index, expectedType)
	local typeStr = GLUt.type_is(expectedType, "string") and (" <T:" .. expectedType .. ">") or ""
	return argType .. " \"" .. name .. "\" (#" .. tostring(index) .. ")" .. typeStr 
end

local function tbl_argextract(fname, t, arglayout)
	local index = arglayout[1]
	local name = arglayout[2]
	local expectedType = arglayout[3]
	local canName = arglayout[4]
	local default = arglayout.Default or arglayout.default
	local vital = GLUt.default(arglayout.Vital or arglayout.vital, false)

	local tVal = t[index]
	if canName and tVal ~= nil then
		if t[name] ~= nil then
			return GLUtCfg.error(fname .. "@tblcall : " .. tbl_arginfo("Arg", name, index, expectedType) .. " passed both by name and index!")
		end
	elseif canName then
		tVal = t[name]
	end

	if tVal == nil and default ~= nil then
		tVal = default
	end

	if tVal == nil and expectedType == false then
		return nil
	elseif tVal == nil and not GLUt.str_has_match(expectedType, "%?") then
		local argType = vital and "Vital Arg" or "Arg"
		return GLUtCfg.error(fname .. "@tblcall : " .. tbl_arginfo(argType, name, index, expectedType) .. " not passed!")
	end

	if expectedType == false then return tVal end
	if not GLUt.type_check(tVal, expectedType, name, fname, true) then return nil end
	return tVal
end

function GLUt.fun_tblcallable(fname, f, ...)
	local n, callingConvention = GLUt.vararg_capture(...)
	return function(tbl)
		for k, v in pairs(tbl) do
			local isValid = false
			for i=1, n do
				if isValid then break end
				local validArg = callingConvention[i]
				isValid = (k == i) or (k == validArg[2])
			end
			if not isValid then
				GLUtCfg.error("Received unexpected argument \"" .. tostring(k) .. "\" of type \"" .. GLUtCfg.type(v) .. "\"!")
			end
		end
		local args = {}
		for i=1, n do
			local argLayout = callingConvention[i]
			args[i] = tbl_argextract(fname, tbl, argLayout)
		end
		return f(unpack(args, 1, n))
	end
end

return GLUt