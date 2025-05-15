local RunService = game:GetService("RunService")

local Replicator = RunService:IsServer() and require(script.ServerReplicator) or require(script.ClientReplicator)

local ReplicatorAPI = {}

ReplicatorAPI.new = Replicator.new

ReplicatorAPI.getReplicator = Replicator.getReplicator

ReplicatorAPI.is = Replicator.is

ReplicatorAPI.None = require(script.None)

return ReplicatorAPI
