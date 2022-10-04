local Players = game:GetService("Players")

local Package = script.Parent

local Signal = require(Package.Signal)

local Util = Package.Util
local Assert = require(Util.Assert)
local Error = require(Util.Error)
local Type = require(Util.Type)
local TypeMarker = require(Util.Typemarker)
local Copy = require(Util.Copy)

local ClientReplicator = {}
ClientReplicator.type = TypeMarker.Mark("ClientReplicator")

local Replicators = {}

local retrieveReplicator
local listenToChange

function ClientReplicator.new(key)
	local res = retrieveReplicator:InvokeServer(key)
	Assert(res.successful, "Invalid argument #1 (" .. (res.message or "") .. ")")

	local replicator = res.data
	local self = setmetatable({}, { __index = ClientReplicator })
	Type.SetType(self, ClientReplicator.type)

	self.key = replicator.key
	self.data = replicator.data
	self.replicators = replicator.replicators

	self.destroyCallbacks = {}
	self.onDestroyCallbacks = {}
	self._changedSignal = Signal.new()

	Replicators[self.key] = self
	listenToChange:InvokeServer(self.key)

	return self
end

function ClientReplicator:_updateReplicator(newReplicator)
	local oldData = Copy(self.data)
	self.data = newReplicator.data
	self.replicators = newReplicator.replicators
	self._changedSignal:Fire(newReplicator.data, oldData)
end

function ClientReplicator:get()
	return self.data
end

function ClientReplicator:onChanged(...)
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
				local newValue = ClientReplicator.getPath(path, newData)
				local oldValue = ClientReplicator.getPath(path, oldData)
				if newValue ~= oldValue then
					callback(newValue, oldValue)
				end
			end)
		end
	end
end

function ClientReplicator:beforeDestroy(callback)
	self.destroyCallbacks[#self.destroyCallbacks + 1] = callback
end

function ClientReplicator:onDestroy(callback)
	self.onDestroyCallbacks[#self.onDestroyCallbacks + 1] = callback
end

function ClientReplicator:Destroy()
	local onDestroyCallbacks = Copy(self.onDestroyCallbacks)

	for _, callback in pairs(self.destroyCallbacks) do
		callback()
	end

	Replicators[self.key] = nil
	local function destroyRecursive(tbl)
		for key, value in pairs(tbl) do
			if Type.GetType(value) == Signal.type then
				value:Destroy()
			elseif typeof(value) == "table" then
				destroyRecursive(value)
			elseif Type.GetType(value) == ClientReplicator.type then
				value:Destroy()
			end
			tbl[key] = nil
		end
	end
	destroyRecursive(self)

	for _, callback in pairs(onDestroyCallbacks) do
		callback()
	end
end

function ClientReplicator.getPath(path, tbl)
	local currentPath = tbl
	for _, value in pairs(path) do
		currentPath = currentPath[value]
		if not currentPath then
			return nil
		end
	end
	return currentPath
end

local function init()
	Assert(Package:FindFirstChild("Remotes"), "Server never initialized")

	local destroyReplicator = Package.Remotes.DestroyReplicator
	destroyReplicator.OnClientEvent:Connect(function(key)
		Replicators[key]:Destroy()
	end)

	local replicatorChanged = Package.Remotes.ReplicatorChanged
	replicatorChanged.OnClientEvent:Connect(function(newReplicator)
        local replicator = Replicators[newReplicator.key]
        replicator:_updateReplicator(newReplicator)
    end)

	retrieveReplicator = Package.Remotes.RetrieveReplicator
	listenToChange = Package.Remotes.ListenToChange
end
init()

return ClientReplicator
