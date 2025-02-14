local Players = game:GetService("Players")

local jecs = require("../roblox_packages/jecs")
local feces = require("../src")

local pair = jecs.pair
local world = jecs.World.new()

local Player = world:component()

Players.PlayerAdded:Connect(function(player: Player)
    local id = world:entity()
    world:set(id, Player, player)
    world:add(id, pair(Player, feces.replicated))
end)

Players.PlayerRemoving:Connect(function(player: Player)
    local id = nil
    for entityId, otherPlayer in world:each(Player) do
        if otherPlayer == player then
            id = entityId
            break
        end
    end
    world:remove(id, pair(Player, feces.replicated))
    world:remove(id, Player) -- or delete the entity
end)

return function()
    --idk system stuff
end