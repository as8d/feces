--!optimize 2
--!native

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local feces = require(ReplicatedStorage.feces)
local getPackets = feces.getPackets
local applyPackets = feces.applyPackets
local filterPackets = feces.filterPackets
local getFullPacket = feces.getFullPacket

local Remote = ReplicatedStorage.Remote

Players.PlayerAdded:Connect(onPlayerAdded)

local function deepMerge(target: { [string]: any }, source: { [string]: any }): { [string]: any }
	for key, value in source do
		if typeof(value) == "table" and typeof(target[key]) == "table" then
			target[key] = deepMerge(target[key], value)
		else
			target[key] = value
		end
	end
	return target
end

local function replicate()
	local full = nil
	for _, player in network.requestFullPacket.iter() do
		full = full or getFullPacket()
		event.send_to(player, full)
	end
	
	for _, packet in getPackets() do
		local player = packet.player
		if player then
			event.send_to(player, packet.entities)
		else
			task.delay(2, function()
				event.send_to_all(packet.entities)
			end)
		end
	end
end

return function(scheduler)
	if RunService:IsServer() then
		return scheduler.systems.new(replicate, scheduler.phases.Heartbeat)
	else
		network.requestFullPacket.fire()
		event.listen(function(entities)
			applyPackets(entities)
		end)
	end
end