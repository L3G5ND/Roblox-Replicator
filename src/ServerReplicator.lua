local Players = game:GetService("Players")
local Package = script.Parent

local Signal = require(Package.Signal)
local None = require(Package.None)

local Util = Package.Util
local Assert = require(Util.Assert)
local Assign = require(Util.Assign)
local Type = require(Util.Type)
local TypeMarker = require(Util.Typemarker)
local Copy = require(Util.Copy)

local ServerReplicator = {}
ServerReplicator.type = TypeMarker.Mark("ServerReplicator")

local Replicators = {}

local replicatorChanged
local destroyReplicator

function ServerReplicator.new(data)
	Assert(data.key, "Invalid argument #1 ('key' required)")
	local replicatorType = typeof(data.replicators)
	Assert(
		replicatorType == "table" or replicatorType == "nil" or replicatorType == "string" and data.replicators == "All",
		"Invalid argument #1 ('replicators' must be of type 'table', 'string' ('All'), or 'nil' )"
	)

	local self = setmetatable({}, { __index = ServerReplicator })
	Type.SetType(self, ServerReplicator.type)

	self.key = data.key
	self.data = data.data
	self.replicators = data.replicators or {}

	self._changedSignal = Signal.new()

	self._connections = {}
	self.destroyCallbacks = {}
	self.onDestroyCallbacks = {}

	if not Replicators[data.key] then
		Replicators[data.key] = {}
	end
	table.insert(Replicators[data.key], self)

	return self
end

function ServerReplicator.getReplicators(key)
	Assert(Replicators[key], "Invalid argument #1 (must be a valid Replicator))")
	return Replicators[key]
end

function ServerReplicator:set(value)
	local oldData = Copy(self.data)
	if typeof(value) == "table" and typeof(self.data) == "table" then
		Assign(self.data, value)
	else
		self.data = value
	end
	self._changedSignal:Fire(self.data, oldData)
	return self.data
end

function ServerReplicator:get()
	return self.data
end

function ServerReplicator:setReplicators(newReplicators)
	Assert(
		typeof(newReplicators) == "table" or typeof(newReplicators) == "string" and newReplicators == "All",
		"Invalid argument #1 ('replicators' must be of type 'table' or 'string' ('All'))"
	)
	local oldReplicators = self.replicators == "All" and "All" or Copy(self.replicators)
	self.replicators = newReplicators

	if newReplicators == "All" then
		if oldReplicators == "All" then
			replicatorChanged:FireAllClients(self)
		else
			for _, plr in pairs(Players:GetPlayers()) do
				local hasPlr
				for _, oldPlr in pairs(oldReplicators) do
					if plr == oldPlr then
						hasPlr = true
					end
				end
				if hasPlr then
					replicatorChanged:FireAllClients(self)
				end
			end
		end
	else
		if oldReplicators == "All" then
			if typeof(newReplicators) == "table" then
				for _, plr in pairs(Players:GetPlayers()) do
					local hasPlr
					for _, oldPlr in pairs(oldReplicators) do
						if plr == oldPlr then
							hasPlr = true
						end
					end
					if not hasPlr then
						self._connections[plr]()
						destroyReplicator:FireClient(plr, self.key)
					end
				end
			end
		else
			for _, plr in pairs(oldReplicators) do
				local hasPlr
				for _, oldPlr in pairs(newReplicators) do
					if plr == oldPlr then
						hasPlr = true
					end
				end
				if hasPlr then
					replicatorChanged:FireClient(plr, self)
				else
					self._connections[plr]()
					destroyReplicator:FireClient(plr, self.key)
				end
			end
		end
	end
	return newReplicators
end

function ServerReplicator:onChanged(...)
	local args = { ... }
	if #args == 1 then
		local callback = args[1]
		Assert(typeof(callback) == "function", "Invalid argument #1 (type 'function' expected)")

		return self._changedSignal:Connect(callback)
	elseif #args == 2 then
		local arg1Type = typeof(args[1])
		Assert(arg1Type == "string" or arg1Type == "table", "Invalid argument #1 (must be type 'string' or 'table')")

		if arg1Type == "string" then
			local key = args[1]
			local callback = args[2]

			return self._changedSignal:Connect(function(newData, oldData)
				local newValue = newData[key]
				local oldValue = oldData[key]
				if newValue ~= oldValue then
					callback(newValue, oldValue)
				end
			end)
		elseif arg1Type == "table" then
			local path = args[1]
			local callback = args[2]

			return self._changedSignal:Connect(function(newData, oldData)
				local newValue = ServerReplicator.getPath(path, newData)
				local oldValue = ServerReplicator.getPath(path, oldData)
				if newValue ~= oldValue then
					callback(newValue, oldValue)
				end
			end)
		end
	end
end

function ServerReplicator:getPriority()
	local replicators = self.replicators
	if replicators == "All" then
		return 1
	elseif typeof(replicators) == "table" then
		return 2
	end
	return nil
end

function ServerReplicator:isPlayerReplicated(plr)
	if self.replicators == "All" then
		return true
	end
	for _, _plr in pairs(self.replicators) do
		if plr == _plr then
			return true
		end
	end
	return false
end

function ServerReplicator:beforeDestroy(callback)
	self.destroyCallbacks[#self.destroyCallbacks + 1] = callback
end

function ServerReplicator:onDestroy(callback)
	self.onDestroyCallbacks[#self.onDestroyCallbacks + 1] = callback
end

function ServerReplicator:Destroy()
	local onDestroyCallbacks = Copy(self.onDestroyCallbacks)
	local replicators = self.replicators == "All" and "All" or Copy(self.replicators)
	local key = self.key

	for _, callback in pairs(self.destroyCallbacks) do
		callback()
	end

	Replicators[self.key] = nil
	local function destroyRecursive(tbl)
		for key, value in pairs(tbl) do
			if typeof(value) == "table" then
				destroyRecursive(value)
			elseif Type.GetType(value) == ServerReplicator.type then
				value:Destroy()
			end
			tbl[key] = nil
		end
	end
	destroyRecursive(self)

	if replicators == "All" then
		destroyReplicator:FireAllClients(key)
	else
		for _, plr in pairs(replicators) do
			destroyReplicator:FireClient(plr, key)
		end
	end

	for _, callback in pairs(onDestroyCallbacks) do
		callback()
	end
end

function ServerReplicator.retrieveReplicator(plr, key)
	if Replicators[key] then
		local currentPriority = 0
		local currentReplicator
		for _, replicator in pairs(Replicators[key]) do
			local priority = replicator:getPriority()
			local isPlayerReplicated = replicator:isPlayerReplicated(plr)
			if isPlayerReplicated then
				if priority > currentPriority then
					currentPriority = priority
					currentReplicator = replicator
				end
			end
		end
		if currentReplicator then
			return {
				successful = true,
				data = currentReplicator,
			}
		else
			print(plr, Replicators[key])
			return {
				successful = false,
				message = "Access denied",
			}
		end
	else
		return {
			successful = false,
			message = "Invalid replicator key",
		}
	end
end

function ServerReplicator.listenToChange(plr, key)
	local res = ServerReplicator.retrieveReplicator(plr, key)
	if res.successful then
		local replicator = res.data
		local connection = replicator._changedSignal:Connect(function()
			local res = ServerReplicator.retrieveReplicator(plr, key)
			if res.successful then
				replicatorChanged:FireClient(plr, res.data)
			end
		end)
		replicator._connections[plr] = connection
		return {
			successful = true,
		}
	else
		return res
	end
end

function ServerReplicator.getPath(path, tbl)
	local currentPath = tbl
	for _, value in pairs(path) do
		currentPath = currentPath[value]
		if not currentPath then
			return nil
		end
	end
	return currentPath
end

local init = function()
	local function createRemote(name, parent)
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = parent
		return remote
	end

	local function createRemoteFunction(name, parent)
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = parent
		return remote
	end

	local Remotes = Instance.new("Folder", script.Parent)
	Remotes.Name = "Remotes"

	local retrieveReplicator = createRemoteFunction("RetrieveReplicator", Remotes)
	retrieveReplicator.OnServerInvoke = ServerReplicator.retrieveReplicator

	local listenToChange = createRemoteFunction("ListenToChange", Remotes)
	listenToChange.OnServerInvoke = ServerReplicator.listenToChange

	destroyReplicator = createRemote("DestroyReplicator", Remotes)
	replicatorChanged = createRemote("ReplicatorChanged", Remotes)
end
init()

return ServerReplicator
