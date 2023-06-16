local Players = game:GetService("Players")

local Package = script.Parent
local Networker = require(Package.Networker)
local Signal = require(Package.Signal)
local ChangedCallback = require(Package.ChangedCallback)
local None = require(Package.None)

local Util = Package.Util
local Assert = require(Util.Assert)
local Copy = require(Util.Copy)
local TypeMarker = require(Util.TypeMarker)
local Error = require(Util.Error)

local getReplicatorRemote = Networker.new("Replicator/Get")
local destroyReplicatorRemote = Networker.new("Replicator/Destroy")
local replicatorChangedRemote = Networker.new("Replicator/Changed")
local eventReplicatorRemote = Networker.new("Replicator/Event")

local ClientReplicator = {}
local Replicators = {}

local ReplicatorType = TypeMarker.Mark("[Replicator]")

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

	local self = setmetatable(replicator, {
		__index = ClientReplicator,
		__tostring = function()
			return ReplicatorType
		end,
	})

	self._type = ReplicatorType

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

	if not Replicators[self.key] then
		Replicators[self.key] = {}
	end
	Replicators[self.key] = self

	return self
end

function ClientReplicator.getReplicator(key)
	return Replicators[key]
end

function ClientReplicator.is(replicator)
	if typeof(replicator) == "table" then
		return replicator._type == ReplicatorType
	end
	return false
end

function ClientReplicator:get()
	return Copy(self.data)
end

function ClientReplicator:FireEvent(eventName, ...)
	eventReplicatorRemote:Fire(self.key, eventName, ...)
end

function ClientReplicator:getKey()
	return self.key
end

function ClientReplicator:playerIterator(players)
	if players == "all" then
		return pairs(Players:GetPlayers())
	else
		return pairs(players)
	end
end

function ClientReplicator:getPlayers()
	return Copy(self.players)
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

function ClientReplicator:getSelf()
	local tbl = {}
	for key, value in self do
		tbl[key] = value
	end
	return tbl
end

function ClientReplicator:Destroy()
	self._DestroyedSignal:Fire()
	self._DestroyedSignal:DisconnectAll()
	self._ChangedSignal:DisconnectAll()
	self._EvenetSignal:DisconnectAll()
	Replicators[self.key] = nil
end

function ClientReplicator:_update(updatedReplicator)
	local oldData = Copy(self.data)
	self.data = updatedReplicator.data
	self.players = updatedReplicator.players
	self._ChangedSignal:Fire(self.data, oldData)
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

eventReplicatorRemote:Connect(function(key, eventName, ...)
	local replicator = Replicators[key]
	if replicator then
		replicator._EvenetSignal:Fire(eventName, ...)
	end
end)

return ClientReplicator
