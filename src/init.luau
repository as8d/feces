
--!strict
--!optimize 2
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Jecs = require(ReplicatedStorage.Packages.Jecs)
local Dictionary = require(ReplicatedStorage.Packages.Freeze).Dictionary
local Wildcard = Jecs.Wildcard
local ref = require(ReplicatedStorage.Hooks.ref)
local world = require(ReplicatedStorage.World)
local isServer = game:GetService("RunService"):IsServer()
local pair = Jecs.pair
local refs = require(ReplicatedStorage.refs)

local onRemove = Jecs.OnRemove

type pair<First, Second> = number & { __relation: First }
type entity<T = nil> = number & { __T: T }
type component<T = nil> = entity<T> | pair<entity<T>, entity<unknown>>

type NIL_VALUE = "__n"
local NIL_VALUE: NIL_VALUE = "__n"

type DELETE_VALUE = "__d"
local DELETE_VALUE: DELETE_VALUE = "__d"

export type EntityChanges = {
	[string]: DELETE_VALUE | { --entity<any>]: {
		[string]: any, --component<any>]: any,
	},
}
export type Packet = {
	player: Player?,
	entities: EntityChanges,
}

export type PlayerObject = Player | { Player } | nil

local function makePacket(plr: Player?): Packet
	return {
		entities = {},
		player = plr,
	}
end

local function getPlayers(info: PlayerObject): { Player }?
	if typeof(info) == "table" then
		return info
	end
	return if info ~= nil then { info } else nil
end

--- Checks if a packet contains any changes to replicate, and appends to list
local function addPacket(collection: { Packet }, packet: Packet)
	--use the standard iterator for maps because the # operator doesn't work
	local containsChange = false
	for _, entity: any in packet.entities do
		if entity == DELETE_VALUE then
			containsChange = true
			break
		end
		
		for _ in entity do
			containsChange = true
			break
		end
		if containsChange then
			break
		end
	end
	if not containsChange then
		return
	end
	--add the packet to the collection because there was a change
	table.insert(collection, packet)
end

--- If there is a (shallow) difference in the object it will return the current object, else nil
local function componentChanges<T>(prevComponentValue: T | {}, currComponentValue: T | {}): NIL_VALUE | T | {} | nil
	--new value is nil, then change to nil
	
	
	if currComponentValue == nil then
		if prevComponentValue == NIL_VALUE then
			return
		end
		if prevComponentValue == nil then
			-- print("tag added, registered as change")
			return NIL_VALUE
		end
	end

	local type1, type2 = typeof(prevComponentValue), typeof(currComponentValue)

	--NO CHANGES
	if type1 ~= "table" and type2 ~= "table" and prevComponentValue == currComponentValue then
		-- if debug_component == 1 then print("no difference because values are equal") end
		return nil
	end

	--new value is nil, then change to nil
	if currComponentValue == nil then
		-- print("component set to nil")
		return NIL_VALUE
	end

	--old value is nil, then change to new value
	if prevComponentValue == nil then
		-- print("previous value == nil so curr value HAS to be changed")
		return currComponentValue
	end
	
	if type1 ~= type2 or type2 ~= "table" then
		-- print("both values are tables and different tables")
		return currComponentValue
	end

	if type1 == "table" and type2 == "table" then
		if not Dictionary.equals(currComponentValue, prevComponentValue) then
			return currComponentValue
		end
	end

	--no table changes found!
	return nil
end

local function reverseRef(entity: number): number?
	if not entity then
		return nil
	elseif isServer then
		return entity
	end
	for key, value in refs :: { number } do
		if tonumber(value) == tonumber(entity) then
			return key
		end
	end

	return entity
end

local storage = {}
local previous: EntityChanges = {}
local function addChanges(
	entity,
	componentId,
	componentValue,
	group,
	key,
	playerValue
)
	componentId = tostring(componentId)
	previous[entity] = if previous[entity] then previous[entity] else {}
	local changes = componentChanges(previous[entity][componentId], componentValue)
	if changes == nil then
		return --NO DIFFERENCE IN VALUE
	end

	local players: { Player }? = getPlayers(playerValue)
	previous[entity][componentId] = changes

	entity = tostring(reverseRef(tonumber(entity)))
	-- add to the map of previous entities and constantly check if the world contains them
	--find the right packet to edit and add the component's diff
	if players == nil then
		--add to public packet
		group.public.entities[entity] = group.public.entities[entity] or {}
		group.public.entities[entity][componentId] = changes
	else
		for _, player in players do
			group[player] = group[player] or makePacket(player);
			(group[player] :: Packet).entities[entity] = (group[player].entities :: Packet)[entity] or {};
			(group[player] :: Packet).entities[entity][componentId] = changes;
		end
	end
end
local ECS_ENTITY_MASK = bit32.lshift(1, 24)
local ECS_ID_FLAGS_MASK = 0x10

local replicated = require(ReplicatedStorage.Components).Replicated
type targets = { [number]: number }?

local function target(archetype, index)
	local nth = index or 0
	local idr = world.componentIndex[pair(replicated, Wildcard)]
	if not idr then
		return
	end

	local tr = idr.cache[archetype.id]
	if not tr then
		return
	end

	local count = tr.count
	if nth >= count then
		nth = nth + count + 1
	end

	nth = archetype.types[nth + tr.column]
	if not nth then
		return
	end

	return Jecs.entity_index_get_alive(world.entity_index, if nth > ECS_ENTITY_MASK then (nth // ECS_ID_FLAGS_MASK) % ECS_ENTITY_MASK else nth)
end

local function getAllTargets(archetype, index: number, targets: targets): targets
	targets = targets or {}
	local componentId = target(archetype, index)
	if not componentId then
		return targets
	end

	table.insert(targets, componentId)
	return getAllTargets(archetype, index + 1, targets)
end

local queries = {
	[1] = world:query(replicated):cached(),
	[2] = world:query(pair(replicated, Wildcard)):cached(),
}

local function getPackets(): () -> (number?, Packet?)
	local packets: { Packet } = {}
	local systemPackets: { [boolean]: { public: Packet } & { [Player]: Packet } } = {
		public = makePacket(),
	}

	local playerLinks = {}
	
	for key, query in queries do
		local isPair: boolean = key == 2
		local group = systemPackets
		for _, archetype in query:archetypes() do
			local entities: { number } = archetype.entities
			local columns: { any } = archetype.columns

			--go through entities
			for row, entity: any in entities do
				for columnNumber: number, column in columns do
					if isPair then	
						local targets = getAllTargets(archetype, 0)
						if not targets then
							continue
						end

						for _, componentId in targets do
							local componentValue = world:get(entity, componentId)
							if type(componentValue) == "function" then
								continue
							end
							local playerValue = world:get(entity, pair(replicated, componentId))
							playerLinks[componentId] = playerValue
							
							addChanges(
								tostring(entity),
								componentId,
								componentValue,
								group,
								key,
								playerValue
							)
						end
					else
						local componentId: string = tostring(archetype.types[columnNumber])
						local componentValue = column[row]
						if type(componentValue) == "function" then
							continue
						end
						
						-- componentValue = if componentValue == nil then NIL_VALUE else componentValue
						local playerValue = world:get(entity, replicated)
						playerLinks[componentId] = playerValue

						addChanges(
							tostring(entity),
							componentId,
							componentValue,
							group,
							key,
							playerValue
						)
					end
				end
			end
		end
	end
	
	for entity, components in previous do
		entity = tonumber(entity)
		if not world:contains(entity) then
			systemPackets.public.entities[tostring(entity)] = DELETE_VALUE
			previous[tostring(entity)] = nil
			print("REGISTERING DELETE:", entity)
			continue
		end

		for id in components do
			id = tonumber(id)
			world:set(id, onRemove, function(ent)
				if ent == entity then
					previous[tostring(entity)][tostring(id)] = nil
					local playerData = getPlayers(playerLinks[id])
					if playerData then
						for _, player in playerData do
							systemPackets[player].entities[entity][id] = DELETE_VALUE
						end
						return
					end
					
					entity = tostring(entity)
					systemPackets.public.entities[entity] = systemPackets.public.entities[entity] or {}
					systemPackets.public.entities[entity][tostring(id)] = DELETE_VALUE
				end
			end)
		end
	end

	--add new packets to collections
	for _, packet in systemPackets :: { [any]: Packet } do
		if next(packet.entities) == nil then
			continue
		end

		addPacket(packets, packet)
	end

	local i = 0
	return function(): (number?, Packet?)
		i += 1
		local this = packets[i]
		if this == nil then
			i = 0
			return
		end
		return i, this
	end
end

local Players = game:GetService("Players")
local ctx = require(ReplicatedStorage.Components)
local function applyPackets(entities: EntityChanges)
	for entity: any, components in entities do
		entity = ref(`repl{entity}`)
		if components == DELETE_VALUE then
			local model = entity:get(ctx.Model)
			if model then
				model:Destroy()
			end
			entity:delete()
			continue
		end
		
		for id, component in components do
			if component == game:GetService("Players").LocalPlayer then
				refs["LocalPlayer"] = entity
				refs[component.UserId] = entity
			elseif typeof(component) == "Instance" and component:IsDescendantOf(Players) then
				refs[component.UserId] = entity
			end
			if component == DELETE_VALUE then
				entity:remove(tonumber(id))
				continue
			end
			
			entity:set(tonumber(id), if component == NIL_VALUE then nil else component)
		end
	end
end

local function filterPackets(entities: EntityChanges, ...: component<any>)
	local componentMap: { [component<any>]: true? } = {}
	for _, componentId in { ... } do
		componentMap[componentId] = true
	end

	local filtered = {}
	for entity, components in entities do
		for id, component in components do
			if componentMap[`repl{id}` :: component<any>] then
				filtered[entity] = filtered[entity] or {}
				filtered[entity][id] = component
			end
		end
	end

	return filtered
end

local function skimChanges(
	entity,
	componentId,
	componentValue,
	packet,
	key,
	playerValue
)
	componentId = tostring(componentId)
	packet[entity] = packet[entity] or {}
	packet[entity][componentId] = componentValue
end

local function getFullPacket()
	local packet = {}
	
	for key, query in queries do
		local isPair: boolean = key == 2
		for _, archetype in query:archetypes() do
			local entities: { number } = archetype.entities
			local columns: { any } = archetype.columns

			--go through entities
			for row, entity: any in entities do
				for columnNumber: number, column in columns do
					if isPair then	
						local targets = getAllTargets(archetype, 0)
						if not targets then
							continue
						end

						for _, componentId in targets do
							local componentValue = world:get(entity, componentId)
							if type(componentValue) == "function" then
								continue
							end
							local playerValue = world:get(entity, pair(replicated, componentId))
							if playerValue then
								continue
							end

							skimChanges(
								tostring(entity),
								componentId,
								componentValue,
								packet,
								key,
								playerValue
							)
						end
					else
						local componentId: string = tostring(archetype.types[columnNumber])
						local componentValue = column[row]
						if type(componentValue) == "function" then
							continue
						end

						local playerValue = world:get(entity, replicated)
						if playerValue then
							continue
						end

						skimChanges(
							tostring(entity),
							componentId,
							componentValue,
							packet,
							key,
							playerValue
						)
					end
				end
			end
		end
	end
	
	return packet
end

return {
	getPackets = getPackets,
	applyPackets = applyPackets,
	filterPackets = filterPackets,
	getFullPacket =  getFullPacket,
}