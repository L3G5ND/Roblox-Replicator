local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Package = script.Parent
local Networker = require(Package.Networker)
local WrapChangedConnection = require(Package.WrapChangedConnection)
local None = require(Package.None)

local Util = Package.Util
local Assert = require(Util.Assert)
local Error = require(Util.Error)
local Assign = require(Util.Assign)
local DeepEqual = require(Util.DeepEqual)
local Copy = require(Util.Copy)

local getReplicatorRemote = Networker.new("Replicator/Get")
local destroyReplicatorRemote = Networker.new("Replicator/Destroy")
local replicatorChangedRemote = Networker.new("Replicator/Changed")

local ClientReplicator = {}
local Replicators = {}

local function removeNone(tbl)
	for key, value in pairs(tbl) do
		if value == None then
			tbl[key] = nil
		elseif typeof(value) == "table" then
			removeNone(value)
		end
	end
end

function ClientReplicator.new(key, timeOut)
	Assert(typeof(key) == "string", "Invalid argument #1 (must be a 'string')")
	Assert(typeof(timeOut) == "number" or timeOut == nil, "Invalid argument #1 (must be a 'string')")

	if Replicators[key] then
		return Replicators[key]
	end

	local replicator

	local startTime = os.clock()
	while true do
		local result, shouldError = getReplicatorRemote:Invoke(key)
		if shouldError then
			Error(result)
		end
		if result then
			replicator = result
			break
		end
		if os.clock() - startTime >= (timeOut or 5) then
			Error("Invalid replicator key ('" .. key .. "')")
		end
		task.wait()
	end

	local self = setmetatable(replicator, { __index = ClientReplicator })

	self._changedConnection = {}

	if not Replicators[self.key] then
		Replicators[self.key] = {}
	end
	Replicators[self.key] = self

	return self
end

function ClientReplicator.getReplicator(key)
	return Replicators[key]
end

function ClientReplicator:get()
	return Copy(self.data)
end

function ClientReplicator:Connect(...)
	local connections = self._changedConnection

	local connection = {
		_metadata = {
			callback = nil,
		},
		_id = HttpService:GenerateGUID(false),
		_isAlive = true,
	}

	function connection:Disconnect()
		self._isAlive = false
		connections[self._id] = nil
	end

	setmetatable(connection, { __index = connection })

	connections[connection._id] = connection

	WrapChangedConnection(connection, ...)

	return connection
end

function ClientReplicator:DisconnectAll()
	for _, connection in self._changedConnection do
		connection:Disconnect()
	end
end

function ClientReplicator:isPlayerReplicated(player)
	if self.players == "all" then
		return true
	end
	for _, otherPlayer in pairs(self.players) do
		if player == otherPlayer then
			return true
		end
	end
	return false
end

function ClientReplicator:Destroy()
	self:DisconnectAll()
	Replicators[self.key] = nil
end

function ClientReplicator:_update(updatedReplicator)
	local oldData = Copy(self.data)
	self.data = updatedReplicator.data
	self.players = updatedReplicator.players
	for _, connection in pairs(self._changedConnection) do
		connection._metadata.callback(self.data, oldData)
	end
end

destroyReplicatorRemote:Connect(function(key)
	local replicator = Replicators[key]
	if replicator then
		replicator:Destroy()
	end
end)

replicatorChangedRemote:Connect(function(updatedReplicator)
	local replicator = Replicators[updatedReplicator.key]
	if replicator then
		replicator:_update(updatedReplicator)
	end
end)

return ClientReplicator
