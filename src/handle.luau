--!strict
--!optimize 2

local jecs = require("../roblox_packages/Jecs")
type entity<T = nil> = jecs.Entity<T>
type id<T = nil> = entity<T> | jecs.Pair<any, any>

type interface = {
	__index: interface,

	new: (world: jecs.World, entity: entity) -> handle,

	--- Checks if the entity has all of the given components
	has: (self: handle, ...id) -> boolean,
	--- Retrieves the value of up to 4 components. These values may be nil.
	get: (self: handle, id: id, id2: id?, id3: id?, id4: id?) -> any,
	--- Adds a component to the entity with no value
	add: <T>(self: handle, id: id<T>) -> handle,
	--- Assigns a value to a component on the given entity
	set: <T>(self: handle, id: id<T>, data: T) -> handle,
	--- Removes a component from the given entity
	remove: (self: handle, id: id) -> handle,
	--- Deletes the entity and all its related components and relationships. **Does not** refer to deleting the handle
	delete: (self: handle) -> (),
	clear: (self: handle) -> handle,
	--- Gets the entitys id
	id: (self: handle) -> entity,
}

export type handle = typeof(setmetatable({} :: { entity: entity }, {} :: interface))

local world: jecs.World? = nil
local handle = {} :: interface
handle.__index = handle

function handle.new(world, entity: entity)
    world = world
	local self = {
		entity = entity,
	}

	return setmetatable(self, handle)
end

function handle:has(...: id): boolean
    if not world then
        return false
    end
	return world:has(self.entity, ...) :: boolean
end

function handle:get<V...>(...: V...)
    if not world then
        return
    end
	return world:get(self.entity, ...)
end

function handle:add<T>(id: id<T>): handle
    if world then
	    world:add(self.entity, id)
    end
	return self
end

function handle:set<T>(id: id<T>, value: T): handle
    if world then
	    world:set(self.entity, id, value)
    end
	return self
end

function handle:clear()
    if world then
	    world:clear(self.entity)
    end
	return self
end

function handle:remove(id: id): handle
    if world then
	    world:remove(self.entity, id)
    end
	return self
end

function handle:delete()
    if world then
	    world:delete(self.entity)
    end
end

function handle:id(): entity
	return self.entity
end

return handle.new