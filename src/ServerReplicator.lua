local Players = game:GetService("Players")
local http = game:GetService('HttpService')
local Package = script.Parent

local Signal = require(Package.Signal)
local Networker = require(Package.Networker)
local OnChanged = require(Package.OnChanged)
local None = require(Package.None)

local Util = Package.Util
local Assert = require(Util.Assert)
local Assign = require(Util.Assign)
local DeepEqual = require(Util.DeepEqual)
local Copy = require(Util.Copy)

local ServerReplicator = {}
local Replicators = {}

local function removeNone(tbl)
	for key, value in pairs(tbl) do
		if value == None then
			tbl[key] = nil
		elseif typeof(value) == 'table' then
			removeNone(value)
		end
	end
end

function ServerReplicator.new(data)
	Assert(data.key, "Invalid argument #1 ('key' required)")
	local replicatorType = typeof(data.replicators)
	Assert(
		replicatorType == "table" or replicatorType == "nil" or replicatorType == "string" and data.replicators == "All",
		"Invalid argument #1 ('replicators' must be of type 'table', 'string' ('All'), or 'nil' )"
	)

	local self = setmetatable({}, { __index = ServerReplicator })

	self.key = data.key
	self.data = data.data
	self.replicators = data.replicators or {}
	self.Guid = http:GenerateGUID(false)

	self._changedSignal = Signal.new()
	self._beforeDestroySignal = Signal.new()
	self._onDestroySignal = Signal.new()

	self._changedSignal:Connect(function()
		for _, plr in self:replicatorIterator() do
			Networker.Send('Replicator/ReplicatorChanged', plr, self:_getSendableData())
		end
	end)

	if not Replicators[data.key] then
		Replicators[data.key] = {}
	end
	Replicators[data.key][self.Guid] = self

	return self
end

function ServerReplicator:get()
	return self.data
end

function ServerReplicator:set(value)
	local oldData = Copy(self.data)
	if typeof(value) == "table" and typeof(self.data) == "table" then
		Assign(self.data, value)
	else
		self.data = value
	end
	if typeof(self.data) == 'table' then
		removeNone(self.data)
	end
	if not DeepEqual(self.data, oldData) then
		self._changedSignal:Fire(self.data, oldData)
	end
	return self.data
end

function ServerReplicator:setReplicators(newReplicators)
	Assert(
		typeof(newReplicators) == "table" or typeof(newReplicators) == "string" and newReplicators == "All",
		"Invalid argument #1 ('replicators' must be of type 'table' or 'string' ('All'))"
	)
	local oldReplicators = Copy(self.replicators)
	self.replicators = newReplicators

	if newReplicators == "All" then
		if oldReplicators == "All" then
			Networker.SendAll('Replicator/ReplicatorChanged', self:_getSendableData())
		else
			for _, plr in pairs(Players:GetPlayers()) do
				local hasPlr
				for _, oldPlr in pairs(oldReplicators) do
					if plr == oldPlr then
						hasPlr = true
					end
				end
				if hasPlr then
					Networker.SendAll('Replicator/ReplicatorChanged', self:_getSendableData())
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
						Networker.Send('Replicator/DestroyReplicator', plr, self.key)
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
					Networker.SendAll('Replicator/ReplicatorChanged', self:_getSendableData())
				else
					Networker.Send('Replicator/DestroyReplicator', plr, self.key)
				end
			end
		end
	end
	return newReplicators
end

function ServerReplicator:onChanged(...)
	OnChanged(self._changedSignal, ...)
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
	self._beforeDestroySignal:Connect(callback)
end

function ServerReplicator:onDestroy(callback)
	self._onDestroySignal:Connect(callback)
end

function ServerReplicator:replicatorIterator()
	if self.replicators == 'All' then
		return pairs(Players:GetPlayers())
	else
		return pairs(self.replicators)
	end
end

function ServerReplicator:Destroy()
	local onDestroyCallbacks = Copy(self.onDestroyCallbacks)
	local replicators = self.replicators == "All" and "All" or Copy(self.replicators)

	self._beforeDestroySignal:Fire()

	Replicators[self.key][self.Guid] = nil

	if replicators == "All" then
		Networker.SendAll('Replicator/DestroyReplicator', self.key)
	else
		for _, plr in pairs(replicators) do
			Networker.Send('Replicator/DestroyReplicator', plr, self.key)
		end
	end

	self._onDestroySignal:Fire()
end

function ServerReplicator:_getSendableData()
	local sendableData = {}
	sendableData.key = self.key
	sendableData.data = self.data
	sendableData.replicators = self.replicators
	sendableData.Guid = self.Guid
	return sendableData
end

local function retrieveReplicator(plr, key)
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
			return {successful = true, data = currentReplicator}
		else
			return {successful = false, message = "Access denied",}
		end
	else
		return {successful = false, message = "Invalid replicator key",}
	end
end

local function retrieveSendableReplicator(plr, key)
	local replicator = retrieveReplicator(plr, key)
	replicator.data = replicator.data and replicator.data:_getSendableData()
	return replicator
end

local init = function()
	Networker.createNetworker('Replicator/RetrieveReplicator', 'RemoteFunction')
	Networker.OnInvoke('Replicator/RetrieveReplicator', retrieveSendableReplicator)

	Networker.createNetworker('Replicator/DestroyReplicator', 'RemoteEvent')
	Networker.createNetworker('Replicator/ReplicatorChanged', 'RemoteEvent')
end
init()

return ServerReplicator
