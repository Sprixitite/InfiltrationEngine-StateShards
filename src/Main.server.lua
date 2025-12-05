local apiConsumer = require(script.Parent.APIConsumer)
local warnLogger = require(script.Parent.Slogger)
warnLogger.init{postInit = table.freeze, logFunc = warn}
local glut = require(script.Parent.GLUt)

type APIReference = apiConsumer.APIReference

local warn = warnLogger.new("StateShards")
glut.configure{ warn = warn }

local hookName = nil

local StateShards = {}

local SHARD_ITEM_PATTERN = "%[([%a_][%w_]+)%]"
local SHARD_LABEL_PATTERN = ':' .. SHARD_ITEM_PATTERN
local SHARD_LOCAL_PATTERN = '#' .. SHARD_ITEM_PATTERN

local function expandShard(shard, as)
	local localsExpanded = string.gsub(
		shard,
		SHARD_LOCAL_PATTERN,
		function(s)
			local localName = (as == nil) and s or as
			return '#' .. localName
		end
	)
	return string.gsub(
		localsExpanded,
		SHARD_LABEL_PATTERN,
		function(s)
			local labelName = (as == nil) and s or as
			return ':' .. labelName
		end
	)
end

local function includeShard(warn, shards, shardName)
	local warn = warn.specialize(`Script include {shardName} invalid`)
	local result, failReason = StateShards.FindShard(shards, shardName)
	if result == nil then warn(failReason) return "" end
	return expandShard(result)
end

local function includeShardAs(warn, shards, shardName, shardAs)
	local warn = warn.specialize(`Script include {shardName} invalid`)
	local result, failReason = StateShards.FindShard(shards, shardName)
	if result == nil then warn(failReason) return "" end
	return expandShard(result, shardAs)
end

local preprocessorCommands = {
	["#include[ \t]+<([%a_][%w_%./\\]+)>[%s]*[\r\n]"] = includeShard,
	["#INCLUDE[ \t]+<([%a_][%w_%./\\]+)>[%s]*[\r\n]"] = includeShard,
	["#include[ \t]+<([%a_][%w_%./\\]+)>[ \t]+as[ \t]+<:?([%a_][%w_]+)>[%s]*[\r\n]"] = includeShardAs,
	["#INCLUDE[ \t]+<([%a_][%w_%./\\]+)>[ \t]+AS[ \t]+<:?([%a_][%w_]+)>[%s]*[\r\n]"] = includeShardAs
}

local function isStateComponentScript(pTarget)
	if not pTarget:IsA("BoolValue") then return false end
	local targetType = pTarget:GetAttribute("Type")
	local typeValid = type(targetType) == "string"
	if not typeValid then
		return false, "Type attribute is of non-string datatype"
	end
	local isStateScript = targetType == "StateScript"
	local stateScriptValid = type(pTarget:GetAttribute("ScriptSource")) == "string"
	return (isStateScript and stateScriptValid), (not stateScriptValid) and "ScriptSource attribute is of non-string datatype" or nil
end

local function isPropScript(pTarget)
	if not pTarget:IsA("Part") then return false end
	if not (pTarget.Name == "StateScriptPart") then return false end
	local sourceValid = type(pTarget:GetAttribute("ScriptSource")) == "string"
	return sourceValid, (not sourceValid) and "ScriptSource attribute is of non-string datatype" or nil
end

function StateShards.OnAPILoaded(api: APIReference, shardState)
	hookName = hookName or api.GetRegistrantFactory("Sprix", "StateShards")
	local hookData = {}
	shardState[1] = api.AddHook("PreSerialize", hookName("PreSerialize"), StateShards.OnPreSerialize, hookData)
end

function StateShards.OnAPIUnloaded(api: APIReference, shardState)
	for _, token in ipairs(shardState) do
		api.RemoveHook(token)
	end
end

function StateShards.OnPreSerialize(callbackState, invokeState, mission: Folder)
	local warn = warn.specialize("OnPreSerialize")
	
	local first = true
	repeat
		if not first then coroutine.yield() end
		local _, prefabPresent = invokeState.Get("Sprix_PrefabSystem_PreSerialize_Present")
		local prefabSuccess, prefabDone = invokeState.Get("Sprix_PrefabSystem_PreSerialize", "Done")
		local prefabDone = (not prefabPresent) or (prefabSuccess and prefabDone)
		
		local _, continentPresent = invokeState.Get("Sprix_ContinentController_PreSerialize_Present")
		local continentSuccess, continentDone = invokeState.Get("Sprix_ContinentController_PreSerialize", "Done")
		local continentDone = (not continentPresent) or (continentSuccess and continentDone)
		first = false
	until prefabDone and continentDone
	
	local shardFolder = mission:FindFirstChild("StateScriptShards")
	if not shardFolder then return end
	
	local shards = StateShards.ConstructShardTable(shardFolder)
	
	local stateComponents = mission:FindFirstChild("StateComponents")
	if stateComponents then
		StateShards.RunPreprocessor(shards, stateComponents, isStateComponentScript)
	end
	
	local props = mission:FindFirstChild("Props")
	if props then
		StateShards.RunPreprocessor(shards, props, isPropScript)
	end
	
	print("StateShards : Successfully preprocessed all StateScripts/StateScriptParts")
	shardFolder:Destroy()
end

function StateShards.ConstructShardTable(shardRoot, tbl)
	local warn = warn.specialize("ConstructShardTable")
	tbl = glut.default(tbl, {})
	for _, c in shardRoot:GetChildren() do
		local shardStr = ""
		if c:IsA("Folder") then
			tbl[c.Name] = StateShards.ConstructShardTable(c)
			continue
		elseif c:IsA("LocalScript") then
			warn(c, `Only Script/ModuleScript instances are currently officially supported, behaviour of LocalScripts is reserved & may change in future`, "Shard will be treated like a Script")
			shardStr = c.Source
		elseif c:IsA("ModuleScript") then
			shardStr = require(c)
			if type(shardStr) ~= "string" and type(shardStr) ~= "table" then
				warn(`ModuleScript Shard {c} returned non-string, non-table value`, "Shard will be ignored!")
				continue
			end
		elseif c:IsA("Script") then
			shardStr = c.Source
		else
			warn(`Instance {c} found in {shardRoot} is of unsupported type {c.ClassName}`, "Instance will be ignored!")
			continue
		end
		
		if type(shardStr) == "table" then
			local shardTable = shardStr
			shardStr = shardTable.Source or shardTable.source
			if type(shardTable.DefaultOverride) == "string" then
				local override = glut.str_trimend(glut.str_trimstart(shardTable.DefaultOverride, '%['), '%]')
				shardStr = expandShard(shardStr, '[' .. override .. ']')
			end
		end
		
		if not glut.str_has_match(shardStr, SHARD_LABEL_PATTERN) then
			warn(`StateScriptShard {c} is invalid - no shard labels found!`, "Shard will be ignored!")
			continue
		end
		
		tbl[c.Name] = glut.str_trim(shardStr) .. '\n'
	end
	return tbl
end

function StateShards.FindShard(shardTable, shardPath)
	local separator = glut.str_has_match(shardPath, '/') and '/' or glut.str_has_match(shardPath, '\\') and '\\' or glut.str_has_match(shardPath, '%.') and '.' or nil
	if not separator then
		local result = shardTable[shardPath]
		if type(result) ~= "string" then return nil, `Path pointed to invalid data` end
		return result
	end
	local shardPathSplit = glut.str_split(shardPath, separator)
	local success, shard, failKey = glut.tbl_deepget(shardTable, false, unpack(shardPathSplit))
	if not success and failKey then
		return nil, `Path element {failKey} pointed to invalid data`
	elseif not success then
		return nil, "Path pointed to invalid data"
	end
	
	if type(shard) ~= "string" then
		return nil, `Path led to a folder!`
	end
	
	return shard
end

function StateShards.RunPreprocessor(shards, root, targetId)
	local warn = warn.specialize("RunPreprocessor", root.Name)
	for _, target in ipairs(root:GetDescendants()) do
		local warn = warn.specialize(`StateComponent {target} is invalid`, "Component will be ignored")
		local isTarget, invalidReason = targetId(target)
		if not isTarget and not invalidReason then continue end
		if invalidReason then warn(invalidReason) continue end
		
		local scriptSource = target:GetAttribute("ScriptSource")
		local newSource = scriptSource
		for pattern, handler in pairs(preprocessorCommands) do
			newSource = string.gsub(newSource, pattern, function(...) return handler(warn, shards, ...) end)
		end
		target:SetAttribute("ScriptSource", newSource)
	end
end

apiConsumer.DoAPILoop(plugin, "InfiltrationEngine-StateShards", StateShards.OnAPILoaded, StateShards.OnAPIUnloaded)