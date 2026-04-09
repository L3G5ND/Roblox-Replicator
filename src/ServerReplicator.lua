local Players = game:GetService("Players")

local Package = script.Parent
local Networker = require(Package.Networker)
local Signal = require(Package.Signal)
local ChangedCallback = require(Package.ChangedCallback)
local None = require(Package.None)

local Util = Package.Util
local Assert = require(Util.Assert)
local Assign = require(Util.Assign)
local DeepEqual = require(Util.DeepEqual)
local Copy = require(Util.Copy)
local TypeMarker = require(Util.TypeMarker)

local getReplicatorRemote = Networker.new("Replicator/Get")
local shareReplicatorRemote = Networker.new("Replicator/Share")
local destroyReplicatorRemote = Networker.new("Replicator/Destroy")
local replicatorChangedRemote = Networker.new("Replicator/Changed")
local eventReplicatorRemote = Networker.new("Replicator/Event")

local RequestedReplicators = {}
local ServerReplicator = {}
local Replicators = {}

local ReplicatorType = TypeMarker.Mark("[Replicator]")

local function getLength(tbl)
	if typeof(tbl) ~= "table" then
		return 0
	end
	local count = 0
	for _, _ in tbl do
		count += 1
	end
	return count
end

local function signalWrapper(signal, events)
	events = events or {}
	return {
		Connect = function(_, ...)
			if events.Connect then
				return events.Connect(signal, ...)
			end
			return signal:Connect(...)
		end,
		Once = function(_, ...)
			if events.Once then
				return events.Once(signal, ...)
			end
			return signal:Once(...)
		end,
		Wait = function()
			if events.Wait then
				return events.Wait(signal)
			end
			return signal:Wait()
		end,
		DisconnectAll = function()
			if events.DisconnectAll then
				return events.DisconnectAll(signal)
			end
			signal:DisconnectAll()
		end
	}
end

local function removeNone(tbl)
	for key, value in pairs(tbl) do
		if value == None or value == "[Replicator]-[None]" then
			tbl[key] = nil
		elseif typeof(value) == "table" then
			removeNone(value)
		end
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

	local self = setmetatable({}, {
		__index = ServerReplicator,
		__tostring = function()
			return ReplicatorType
		end,
	})

	self._type = ReplicatorType

	self.key = data.key
	self.data = data.data
	self.players = data.players or "all"

	self._pendingUpdates = {}
	self._deferedUpdateThread = nil

	self._ChangedSignal = Signal.new()
	self.Changed = signalWrapper(self._ChangedSignal, {
		Connect = function(_, ...)
			return self._ChangedSignal:Connect(ChangedCallback(...))
		end,
		Once = function(_, ...)
			return self._ChangedSignal:Once(ChangedCallback(...))
		end
	})

	self._EvenetSignal = Signal.new()
	self.Event = signalWrapper(self._EvenetSignal, {
		Connect = function(_, eventName, callback)
			return self._EvenetSignal:Connect(function(otherEventName, ...)
				if eventName == otherEventName then
					callback(...)
				end
			end)
		end,
		Once = function(_, eventName, callback)
			local connection
			connection = self._EvenetSignal:Connect(function(otherEventName, ...)
				if eventName == otherEventName then
					connection:Disconnect()
					callback(...)
				end
			end)
			return connection
		end,
		Wait = function(_, eventName)
			local thread = coroutine.running()
			local connection
			connection = self._EvenetSignal:Connect(function(otherEventName, ...)
				if eventName == otherEventName then
					connection:Disconnect()
					task.spawn(thread, ...)
				end
			end)
			return coroutine.yield()
		end,
	})

	self._DestroyedSignal = Signal.new()
	self.Destroyed = signalWrapper(self._DestroyedSignal)

	self.isAlive = true

	Replicators[self.key] = self

	for _, player in self:playerIterator(self.players) do
		if RequestedReplicators[player] and RequestedReplicators[player][self.key] then
			RequestedReplicators[player][self.key] = nil
			shareReplicatorRemote:Fire(player, self:_getSendableData())
		end
	end

	return self
end

function ServerReplicator.getReplicator(key)
	return Replicators[key]
end

function ServerReplicator.is(replicator)
	if typeof(replicator) == "table" then
		return replicator._type == ReplicatorType
	end
	return false
end

function ServerReplicator:get()
	return Copy(self.data)
end

function ServerReplicator:set(value, hard)
	local oldData = Copy(self.data)
	if hard then
		self.data = value
	else
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
	end
	if not DeepEqual(self.data, oldData) then
		self._ChangedSignal:Fire(self.data, oldData)
		if typeof(value) == "table" and typeof(oldData) == "table" then
			local function getUpdatedData(data, oldData)
				local updatedData = {}
				for key, value in data do
					if oldData[key] == nil then
						updatedData[key] = value
					elseif typeof(value) == "table" then
						if typeof(oldData[key]) == "table" then
							local data = getUpdatedData(value, oldData[key])
							if data then
								updatedData[key] = data
							end
						else
							updatedData[key] = value
						end
					elseif value ~= oldData[key] then
						updatedData[key] = value
					end
				end

				for key, value in oldData do
					if data[key] == nil then
						updatedData[key] = "[Replicator]-[None]"
					elseif typeof(value) == "table" then
						local data = getUpdatedData(data[key], value)
						if data then
							updatedData[key] = data
						end
					end
				end

				if getLength(updatedData) > 0 then
					return updatedData
				end
			end
			self:_updateClients(getUpdatedData(self.data, oldData))
		else
			self:_updateClients()
		end
	end
end

function ServerReplicator:merge(table)
	Assert(typeof(self:get()) == "table", "Can only merge when typeof(self.data) == 'table'")
	Assert(typeof(table) == 'table', "Invalid argument #1 (must be a 'table')")
	local function merge(tbl1, tbl2)
		for key, value in pairs(tbl2) do
			if typeof(value) == "table" and typeof(tbl1[key]) == "table" then
				merge(tbl1[key], value)
			elseif tbl1[key] == nil then
				tbl1[key] = value
			end
		end
		return tbl1
	end
	self:set(merge(self:get(), table), true)
end

function ServerReplicator:FireEvent(eventName, ...)
	for _, plr in self:playerIterator(self.players) do
		eventReplicatorRemote:Fire(plr, self.key, eventName, ...)
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

	for _, player in self:playerIterator(oldPlayers) do
		local hasPlayer = false
		for _, otherPlayer in self:playerIterator(newPlayers) do
			if otherPlayer == player then
				hasPlayer = true
			end
		end
		if not hasPlayer then
			destroyReplicatorRemote:Fire(player, self.key)
		end
	end
	for _, player in self:playerIterator(newPlayers) do
		if RequestedReplicators[player] and RequestedReplicators[player][self.key] then
			RequestedReplicators[player][self.key] = nil
			shareReplicatorRemote:Fire(player, self:_getSendableData())
		end
	end
	self:_updateClients()
end

function ServerReplicator:getKey()
	return self.key
end

function ServerReplicator:playerIterator(players)
	if players == "all" then
		return pairs(Players:GetPlayers())
	else
		return pairs(players)
	end
end

function ServerReplicator:getPlayers()
	return Copy(self.players)
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

function ServerReplicator:getSelf()
	local tbl = {}
	for key, value in self do
		tbl[key] = value
	end
	return tbl
end

function ServerReplicator:Destroy()
	self._DestroyedSignal:Fire()
	self._DestroyedSignal:DisconnectAll()
	self._ChangedSignal:DisconnectAll()
	self._EvenetSignal:DisconnectAll()
	for _, player in self:playerIterator(self.players) do
		destroyReplicatorRemote:Fire(player, self.key)
	end
	self.isAlive = false
	Replicators[self.key] = nil
end

function ServerReplicator:_updateClients(data)
	data = data or self.data
	table.insert(self._pendingUpdates, data)
	if not self._deferedUpdateThread then
		self._deferedUpdateThread = task.defer(function()
			self._deferedUpdateThread = nil

			local combinedData = self._pendingUpdates[1]
			if #self._pendingUpdates > 1 then
				for i = 2, #self._pendingUpdates do
					local function combine(tbl1, tbl2)
						for key, value in pairs(tbl2) do
							if typeof(value) == "table" and typeof(tbl1[key]) == "table" then
								combine(tbl1[key], value)
							else
								tbl1[key] = value
							end
						end
						return tbl1
					end
					combine(combinedData, self._pendingUpdates[i])
				end
			end

			for _, plr in self:playerIterator(self.players) do
				replicatorChangedRemote:Fire(plr, self:_getSendableData(data))
			end

			self._pendingUpdates = {}
		end)
	end
end

function ServerReplicator:_getSendableData(updatedData)
	local data = {}
	data.key = self.key
	data.data = updatedData or self.data
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
	else
		if not RequestedReplicators[plr] then
			RequestedReplicators[plr] = {}
		end
		RequestedReplicators[plr][key] = true
	end
end)

eventReplicatorRemote:Connect(function(plr, key, eventName, ...)
	local replicator = Replicators[key]
	if replicator then
		local isReplicated = replicator:isPlayerReplicated(plr)
		if isReplicated then
			replicator._EvenetSignal:Fire(eventName, plr, ...)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	RequestedReplicators[player] = nil
end)

return ServerReplicator
