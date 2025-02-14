local RunService = game:GetService("RunService")

local jecs = require("../roblox_packages/jecs")
local feces = require("../src")

local world = jecs.World.new()
local getPackets = feces.getPackets
local applyPackets = feces.applyPackets
local getFullPacket = feces.getFullPacket

local Remote = path.to.Remote

local function replicate()
	-- iterate through new packets (difference is calculated from last getPackets call)
	for _, packet in getPackets() do
		-- use packet.player to tell who the packet is for
		local player = packet.player
		if player then
			Remote:FireClient(player, packet.entities)
		else
			Remote:FireAllClients(packet.entities)
		end
	end
end

return function()
	feces.init(world)
	if RunService:IsServer() then
		-- send the full packet to the client when requested
		Remote.OnServerEvent:Connect(function(player)
			Remote:FireCLient(player, getFullPacket())
			-- no packet.entities here because full packet is just the public entity changes
		end)

		RunService.Heartbeat:Connect(replicate) -- check for new packets every frame
	else
		Remote:FireServer() -- please give me the full packet

		Remote.OnClientEvent:Connect(function(packet)
			applyPackets(packet) -- apply packets to the world as the server sends them
		end)
	end
end