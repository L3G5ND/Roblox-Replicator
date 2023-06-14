local RS = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

local Replicator = require(RS.Replicator)

local plr = Players.LocalPlayer

local replicator = Replicator.new(plr.UserId..'_replicator')

replicator:Connect(function(newValue, oldValue)
    print('Client: [Changed]', newValue, oldValue)
end)
