local RS = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

local Replicator = require(RS.Replicator)

local plr = Players.LocalPlayer

local replicator = Replicator.new(plr.UserId..'_replicator')

replicator.Changed:Connect(function(newValue, oldValue)
    print('Client: [Connect]', newValue, oldValue)
end)
replicator.Changed:Once(function(newValue, oldValue)
    print('Client: [Once]', newValue, oldValue)
end)

replicator.Event:Connect('TestEvent', function(...)
    print('TestEvent: [Connect]', ...)
end)
replicator.Event:Once('TestEvent', function(...)
    print('TestEvent: [Once]', ...)
end)

replicator.Destroyed:Connect(function()
    print('[Destroyed]')
end)

task.wait(5)

replicator:FireEvent('TestEvent', 'a', 'b', 'c')
replicator:FireEvent('TestEvent', 'c', 'b', 'a')

print('-------------------')