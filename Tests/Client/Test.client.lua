local RS = game:GetService('ReplicatedStorage')
local Replicator = require(RS.Replicator)

local replicator = Replicator.new('PlayerData')

replicator:onChanged({'test', 'testValue'}, function(newValue, oldValue)
    print('Client: [Changed] -', newValue, oldValue)
end)
replicator:beforeDestroy(function()
    print('Client: [BeforeDestroy] -', 'Destroying')
end)
replicator:onDestroy(function()
    print('Client: [Destroyed] -', replicator)
end)
