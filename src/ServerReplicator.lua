local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Package = script.Parent
local Networker = require(Package.Networker)
local WrapChangedConnection = require(Package.WrapChangedConnection)
local None = require(Package.None)

local Util = Package.Util
local Assert = require(Util.Assert)
local Assign = require(Util.Assign)
local DeepEqual = require(Util.DeepEqual)
local Copy = require(Util.Copy)

local getReplicatorRemote = Networker.new("Replicator/Get")
local destroyReplicatorRemote = Networker.new("Replicator/Destroy")
local replicatorChangedRemote = Networker.new("Replicator/Changed")

local ServerReplicator = {}
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

local function playerIterator(players)
	if players == "all" then
		return pairs(Players:GetPlayers())
	else
		return pairs(players)
	end
end

function ServerReplicator.new(data)
	Assert(typeof(data) == "table", "Invalid argument #1 (must be a 'table')")

	if Replicators[data.key] then
		return Replicators[data.key]
	end

	Assert(typeof(data.key) == "string", "Invalid argument #1 ('data.key' must be a 'string')")
	Assert(
		typeof(data.players) == "table" or data.players == "all" or data.players == nil,
		"Invalid argument #1 ('data.players' must be a 'table', 'string' ('all'), or 'nil')"
	)

	local self = setmetatable({}, { __index = ServerReplicator })

	self.key = data.key
	self.data = data.data
	self.players = data.players or "all"

	self._changedConnection = {}

	if not Replicators[self.key] then
		Replicators[self.key] = {}
	end
	Replicators[self.key] = self

	return self
end

function ServerReplicator.getReplicator(key)
	return Replicators[key]
end

function ServerReplicator:get()
	return Copy(self.data)
end

function ServerReplicator:set(value)
	local oldData = Copy(self.data)
	if typeof(value) == "table" and typeof(self.data) == "table" then
		Assign(self.data, value)
		removeNone(self.data)
	else
		if value == None then
			self.data = nil
		else
			self.data = value
		end
	end
	if not DeepEqual(self.data, oldData) then
		for _, connection in pairs(self._changedConnection) do
			connection._metadata.callback(self.data, oldData)
		end
		self:_updateClients()
	end
end

function ServerReplicator:setPlayers(newPlayers)
	Assert(
		typeof(newPlayers) == "table" or newPlayers == "all" or newPlayers == nil,
		"Invalid argument #1 (must be a 'table', 'string' ('all'), or 'nil')"
	)

	local oldPlayers = Copy(self.players)
	if not newPlayers then
		newPlayers = {}
	end
	self.players = newPlayers

	for _, player in playerIterator(oldPlayers) do
		local hasPlayer = false
		for _, otherPlayer in playerIterator(newPlayers) do
			if otherPlayer == player then
				hasPlayer = true
			end
		end
		if not hasPlayer then
			destroyReplicatorRemote:Fire(player, self.key)
		end
	end
	self:_updateClients()
end

function ServerReplicator:Connect(...)
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

function ServerReplicator:DisconnectAll()
	for _, connection in self._changedConnection do
		connection:Disconnect()
	end
end

function ServerReplicator:isPlayerReplicated(player)
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

function ServerReplicator:Destroy()
	self:DisconnectAll()
	for _, player in playerIterator(self.players) do
		destroyReplicatorRemote:Fire(player, self.key)
	end
	Replicators[self.key] = nil
end

function ServerReplicator:_updateClients()
	for _, plr in playerIterator(self.players) do
		replicatorChangedRemote:Fire(plr, self:_getSendableData())
	end
end

function ServerReplicator:_getSendableData()
	local data = {}
	data.key = self.key
	data.data = self.data
	data.players = self.players
	return data
end

getReplicatorRemote:OnInvoke(function(plr, key)
	local replicator = Replicators[key]
	if replicator then
		local isReplicated = replicator:isPlayerReplicated(plr)
		if isReplicated then
			return replicator:_getSendableData()
		end
		return "Access denied", true
	end
end)

return ServerReplicator
