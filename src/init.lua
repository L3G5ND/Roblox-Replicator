local RunService = game:GetService("RunService")

local None = require(script.None)
local Replicator

if RunService:IsServer() then
	Replicator = require(script.ServerReplicator)
else
	Replicator = require(script.ClientReplicator)
end

Replicator.None = None

return Replicator
