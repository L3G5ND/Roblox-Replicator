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

    replicator:Connect(function(newValue, oldValue)
        print('Server: [Changed]', newValue, oldValue)
    end)

    task.wait(5)
    
    replicator:set({
        c = {
            a = 'b',
            b = 'a'
        }
    })

    task.wait(1)

    replicator:set({
        b = Replicator.None,
        c = {
            a = 'a',
            b = Replicator.None
        }
    })

    task.wait(1)

    replicator:set({
        c = Replicator.None
    })

    task.wait(1)

    replicator:set(Replicator.None)

    task.wait(1)

    replicator:Destroy()
end)