local RunService = game:GetService("RunService")

local Replicator = RunService:IsServer() and require(script.ServerReplicator) or require(script.ClientReplicator)

local ReplicatorAPI = {}

ReplicatorAPI.new = Replicator.new

ReplicatorAPI.None = require(script.None)

return ReplicatorAPI
