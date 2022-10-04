local RS = game:GetService('ReplicatedStorage')
local Replicator = require(RS.Replicator)

game.Players.PlayerAdded:Connect(function(player)
    local replicator = Replicator.new({
        key = 'PlayerData',
        data = {
            name = player.Name,
            id = player.UserId,
            age = player.AccountAge,
            test = {
                testValue = 1
            }
        },
        replicators = {player}
    })

    replicator:onChanged({'test', 'testValue'}, function(newValue, oldValue)
        print('Server: [Changed] -', newValue, oldValue)
    end)
    replicator:beforeDestroy(function()
        print('Server: [BeforeDestroy] -', 'Destroying')
    end)
    replicator:onDestroy(function()
        print('Client: [Destroyed] -', replicator)
    end)

    local data = replicator:get()

    task.wait(3)
    replicator:set({
        test = {
            testValue = data.test.testValue + 1
        }
    })

    task.wait(3)
    replicator:set({
        name = Replicator.None,
        test = {
            testValue = data.test.testValue + 1
        }
    })

    replicator:Destroy()

end)