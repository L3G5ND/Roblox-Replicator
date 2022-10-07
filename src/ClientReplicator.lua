local RunService = game:GetService('RunService')
local Players = game:GetService("Players")

local Package = script.Parent

local Signal = require(Package.Signal)
local Networker = require(Package.Networker)
local OnChanged = require(Package.OnChanged)

local Util = Package.Util
local Error = require(Util.Error)
local Copy = require(Util.Copy)
local DeepEqual = require(Util.DeepEqual)

local ClientReplicator = {}
local Replicators = {}

function ClientReplicator.new(key, timeOut)
	local replicator

	local startTime = os.time()
	while true do
		local res = Networker.Get('Replicator/RetrieveReplicator', key)
		if res.successful then
			replicator = res.data
			break
		end
		if os.time() - startTime >= (timeOut or 10) then
			Error(res.message)
		end
		RunService.RenderStepped:Wait()
	end

	local self = setmetatable(replicator, { __index = ClientReplicator })
	
	self._changedSignal = Signal.new()
	self._beforeDestroySignal = Signal.new()
	self._onDestroySignal = Signal.new()
	
	Replicators[self.key] = self

	return self
end

function ClientReplicator.isValidReplicator(key)
	local res = Networker.Get('Replicator/RetrieveReplicator', key)
	return res.successful
end

function ClientReplicator:get()
	return self.data
end

function ClientReplicator:expect(value, timeOut, onError)
	local startTime = os.time()
	while true do
		if DeepEqual(self:get(), value) then
			break
		end
		if os.time() - startTime >= (timeOut or 10) then
			if onError then
				onError()
			else
				Error('Invalid argument #1 (self:get() must equal argument #1 within '..timeOut..' seconds)')
			end
		end
		RunService.RenderStepped:Wait()
	end
end

function ClientReplicator:onChanged(...)
	OnChanged(self._changedSignal, ...)
end

function ClientReplicator:beforeDestroy(callback)
	self._beforeDestroySignal:Connect(callback)
end

function ClientReplicator:onDestroy(callback)
	self._onDestroySignal:Connect(callback)
end

function ClientReplicator:Destroy()
	self._beforeDestroySignal:Fire()
	Replicators[self.key] = nil
	self._onDestroySignal:Fire()
end

function ClientReplicator:_updateReplicator(newReplicator)
	local oldData = Copy(self.data)
	for key, value in pairs(newReplicator) do
		self[key] = value
	end
	self._changedSignal:Fire(self.data, oldData)
end

function ClientReplicator:_getSendableData()
	local sendableData = {}
	sendableData.key = self.key
	sendableData.data = self.data
	sendableData.replicators = self.replicators
	return sendableData
end

local function init()
	Networker.OnEvent('Replicator/DestroyReplicator', function(key)
		Replicators[key]:Destroy()
	end)

	Networker.OnEvent('Replicator/ReplicatorChanged', function(newReplicator)
		local startTime = os.time()
		while true do
			if Replicators[newReplicator.key] then
				break
			end
			if os.time() - startTime >= (10) then
				return
			end
			RunService.RenderStepped:Wait()
		end
		Replicators[newReplicator.key]:_updateReplicator(newReplicator)
	end)
end
init()

return ClientReplicator
