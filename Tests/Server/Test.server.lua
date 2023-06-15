local RS = game:GetService('ReplicatedStorage')
local Replicator = require(RS.Replicator)

game.Players.PlayerAdded:Connect(function(player)

    local replicator = Replicator.new({
        key = player.UserId..'_replicator',
        data = {
            a = 'a',
            b = 'b',
            c = {
                a = 'a',
                b = 'b'
            }
        },
        players = { player }
    })

    replicator.Event:Connect('TestEvent', function(...)
        print('TestEvent: [Connect]', ...)
    end)
    replicator.Event:Once('TestEvent', function(...)
        print('TestEvent: [Once]', ...)
    end)
    
    task.wait(4)
    
    replicator:FireEvent('TestEvent', 'a', 'b', 'c')
    replicator:FireEvent('TestEvent', 'c', 'b', 'a')

    replicator.Changed:Connect(function(newValue, oldValue)
        print('Server: [Connect]', newValue, oldValue)
    end)
    replicator.Changed:Once(function(newValue, oldValue)
        print('Server: [Once]', newValue, oldValue)
    end)

    task.wait(5)

    print('-------------------')
    
    replicator:set({
        c = {
            a = 'b',
            b = 'a'
        }
    })
    

    task.wait(1)

    print('-------------------')

    replicator:set({
        b = Replicator.None,
        c = {
            a = 'a',
            b = Replicator.None
        }
    })

    task.wait(1)

    print('-------------------')

    replicator:set({
        c = Replicator.None
    })

    task.wait(1)

    print('-------------------')

    replicator:set(Replicator.None)

    task.wait(1)

    replicator:Destroy()
end)