--!optimize 2
--!native

local jecs = require(script.Parent.Parent.jecs)
local utils = require(script.Parent.utils)
local common = require(script.Parent.common)
local masking_controller = require(script.Parent.masking)

type Cursor = utils.Cursor

type World = jecs.World
type Entity<T = any> = jecs.Entity<T>

type Set<T> = { [T]: boolean }
type Map<K, V> = { [K]: V }
type Array<T> = { T }

type TrackInfo = {
	entities: { [Entity]: boolean },
	components: { [Entity]: { [Entity]: number } },
}

type EntityStorage = {
	tags: { [Entity]: boolean },
	values: { [Entity]: any },
	pairs: { [Entity]: Set<Entity> },
}

type Storage = { [Entity]: EntityStorage }

export type Server = {
	world: World,
	inited: boolean?,

	shared: common.Shared,

	components: common.Components,
	hooks: common.WorldHooks,
	alive_tracked: { [Entity]: boolean },

	track_info: TrackInfo,
	additions: { [Entity]: boolean },
	custom_ids: { [Entity]: Entity },
	storage: Storage,
	hooked: { () -> () },
	masking: masking_controller.MaskingController,
	connections: { RBXScriptConnection },

	init: (self: Server, world: World?) -> (),
	destroy: (self: Server) -> (),

	get_full: (self: Server, player: Player) -> (buffer, { { any } }),
	collect_updates: (self: Server) -> () -> (Player, buffer, { { any } }),
	collect_unreliable: (self: Server) -> () -> (Player, buffer, { { any } }),
	mark_player_ready: (self: Server, player: Player) -> (),
	is_player_ready: (self: Server, player: Player) -> boolean,
}

local cursor = utils.cursor

local NIL_COMPONENT_VALUE = newproxy()

local COMPONENT_TYPES = masking_controller.COMPONENT_TYPES
local TRACK_TYPES = {
	component = 1,
	tag = 2,
	pair = 3,
}
local ENTITY_ID_TYPES = {
	id = 1,
	custom = 2,
	shared = 3,
}
local ECS_COMPONENT = jecs.Component

local function IS_PAIR(id: Entity): boolean
	return jecs.IS_PAIR(id)
end
local function PAIR_SECOND(world: World, id: Entity): Entity
	return jecs.pair_second(world, id)
end
local function ECS_ID(entity: Entity): number
	return jecs.ECS_ID(entity :: any)
end

local function track_entity_lifetime(server: Server, entity: Entity)
	if server.alive_tracked[entity] then
		return
	end
	server.alive_tracked[entity] = true
	server.world:add(entity, server.components.__alive_tracking__)
end

local function get_or_set_entity_storage(server: Server, entity: Entity)
	local storage = server.storage[entity]

	if not storage then
		storage = {
			tags = {},
			values = {},
			pairs = {},
		}
		server.storage[entity] = storage
	end

	return storage
end

local function allocate_component_change(server: Server, entity: Entity, component: Entity, value: any)
	local storage = get_or_set_entity_storage(server, entity)

	local non_nil = if value == nil then NIL_COMPONENT_VALUE else value

	storage.values[component] = non_nil
	if not server.additions[entity] and server.track_info.entities[entity] then
		server.masking:allocate_component_change(entity, component, non_nil)
	end
end
local function allocate_tag_addition(server: Server, entity: Entity, tag: Entity)
	local storage = get_or_set_entity_storage(server, entity)
	storage.tags[tag] = true

	if not server.additions[entity] and server.track_info.entities[entity] then
		server.masking:allocate_tag_addition(entity, tag)
	end
end
local function allocate_pair_addition(server: Server, entity: Entity, relation: Entity, target: Entity)
	local storage = get_or_set_entity_storage(server, entity)
	local targets = storage.pairs[relation]
	if targets == nil then
		targets = {}
		storage.pairs[relation] = targets
	end
	targets[target] = true

	if not server.additions[entity] and server.track_info.entities[entity] then
		server.masking:allocate_pair_addition(entity, relation, target)
	end
end

local function allocate_component_removal(server: Server, entity: Entity, component: Entity)
	local storage = get_or_set_entity_storage(server, entity)
	storage.values[component] = nil

	if not server.additions[entity] and server.track_info.entities[entity] then
		server.masking:allocate_component_removal(entity, component)
	end
end
local function allocate_tag_removal(server: Server, entity: Entity, tag: Entity)
	local storage = get_or_set_entity_storage(server, entity)
	storage.tags[tag] = nil

	if not server.additions[entity] and server.track_info.entities[entity] then
		server.masking:allocate_tag_removal(entity, tag)
	end
end
local function allocate_pair_removal(server: Server, entity: Entity, relation: Entity, target: Entity)
	local storage = get_or_set_entity_storage(server, entity)
	local targets = storage.pairs[relation]
	if targets then
		targets[target] = nil
	end

	if not server.additions[entity] and server.track_info.entities[entity] then
		server.masking:allocate_pair_removal(entity, relation, target)
	end
end

local function track_component(server: Server, component: Entity<any>)
	local world = server.world
	local hooks = server.hooks

	local info = {}
	server.track_info.components[component] = info

	local function hook(unhook: () -> ())
		table.insert(server.hooked, unhook)
	end

	hook(hooks.added(world, component, function(entity, id, value)
		local track_type = info[entity]
		if not track_type then
			return
		end

		if track_type == TRACK_TYPES.component then
			allocate_component_change(server, entity, component, value)
		elseif track_type == TRACK_TYPES.tag then
			allocate_tag_addition(server, entity, component)
		else
			if not IS_PAIR(id) then
				utils.logerror "a non-pair tag was added to a pair tracked component"
			end
			allocate_pair_addition(server, entity, component, PAIR_SECOND(world, id))
		end
	end))
	hook(hooks.changed(world, component, function(entity, id, value)
		local track_type = info[entity]
		if not track_type then
			return
		end
		-- no check here because only components can trigger changed (I think?)
		allocate_component_change(server, entity, component, value)
	end))
	hook(hooks.removed(world, component, function(entity, id)
		local track_type = info[entity]
		if not track_type then
			return
		end

		if track_type == TRACK_TYPES.component then
			allocate_component_removal(server, entity, component)
		elseif track_type == TRACK_TYPES.tag then
			allocate_tag_removal(server, entity, component)
		else
			if not IS_PAIR(id) then
				utils.logerror "a non-pair tag was removed for a pair tracked component"
			end
			allocate_pair_removal(server, entity, component, PAIR_SECOND(world, id))
		end
	end))

	return info
end

local function track_entity_component(server: Server, entity: Entity, component: Entity<any>)
	local world = server.world

	local info = server.track_info.components[component]
	if not info then
		info = track_component(server, component)
	end

	local entity_storage = get_or_set_entity_storage(server, entity)

	if world:has(component, ECS_COMPONENT) then
		-- component
		if world:has(entity, component) then
			local value = world:get(entity, component)

			if value == nil then
				entity_storage.values[component] = NIL_COMPONENT_VALUE
			else
				entity_storage.values[component] = value
			end
		end

		info[entity] = TRACK_TYPES.component

		return COMPONENT_TYPES.component
	else
		-- tag
		if world:has(entity, component) then
			entity_storage.tags[component] = true
		end
		info[entity] = TRACK_TYPES.tag

		return COMPONENT_TYPES.tag
	end
end

local function track_entity_pair(server: Server, entity: Entity, relation: Entity)
	local world = server.world
	local info = server.track_info.components[relation]
	if not info then
		info = track_component(server, relation)
	end

	local entity_storage = get_or_set_entity_storage(server, entity)
	local targets = {}
	local index = 0

	while true do
		local target = world:target(entity, relation, index)
		if not target then
			break
		end
		index += 1
		targets[target] = true
	end
	entity_storage.pairs[relation] = targets

	info[entity] = TRACK_TYPES.pair
end

local function untrack_entity_component(server: Server, entity: Entity, component: Entity<any>): number?
	local info = server.track_info.components[component]
	if not info then
		return nil
	end
	local listen_type = info[entity]
	info[entity] = nil

	local storage = server.storage[entity]
	if storage then
		storage.values[component] = nil
		storage.tags[component] = nil
	end

	return listen_type
end

local function untrack_entity_pair(server: Server, entity: Entity, relation: Entity)
	local info = server.track_info.components[relation]
	if not info then
		return
	end
	info[entity] = nil

	local storage = server.storage[entity]
	if storage then
		storage.pairs[relation] = nil
	end
end

local function write_component_id(server: Server, c: Cursor, component: Entity)
	local encoded = server.shared.ids[component]
	if not encoded then
		utils.logerror(`attempted to replicate a non-shared component `, utils.logcomponent(server.world, component))
		return
	end
	cursor.writeu8(c, encoded)
end

local function write_component_value(server: Server, c: Cursor, component: Entity, value: any, variants: { any })
	local serdes = server.shared.serdes[component]
	if serdes then
		local output = serdes.serialize(if value == NIL_COMPONENT_VALUE then nil else value)

		local bytespan = server.shared.bytespan[component]
		cursor.write_buffer(c, output)
		if bytespan then
			if bytespan ~= buffer.len(output) then
				utils.logerror(
					`bytespan: {bytespan} mismatch for buffer lenght: {buffer.len(output)} in component`,
					utils.logcomponent(server.world, component)
				)
			end
		else
			local len = buffer.len(output)
			cursor.write_vlq(c, len)
		end
	else
		if value == NIL_COMPONENT_VALUE then
			-- this is zero for vlq
			cursor.writeu8(c, 128)
		else
			table.insert(variants, value :: any)
			cursor.write_vlq(c, #variants)
		end
	end

	write_component_id(server, c, component)
end

local function write_entity_id(server: Server, c: Cursor, entity: Entity, variants: { any }, multiply: number?)
	local custom = server.custom_ids[entity]

	if custom then
		local value = server.world:get(entity, custom)
		write_component_value(server, c, custom, value, variants)
		cursor.writei8(c, ENTITY_ID_TYPES.custom * (multiply or 1))
	else
		local shared_id = server.shared.ids[entity]
		if shared_id then
			cursor.writeu8(c, shared_id)
			cursor.writei8(c, ENTITY_ID_TYPES.shared * (multiply or 1))
		else
			cursor.writeu24(c, ECS_ID(entity :: any))
			cursor.writei8(c, ENTITY_ID_TYPES.id * (multiply or 1))
		end
	end
end

local function write_entity(
	server: Server,
	c: Cursor,
	entity: Entity,
	active: masking_controller.ActiveEntity,
	variants: { any }
)
	local storage = server.storage[entity]

	local all_pairs = 0
	for relation in active.components[COMPONENT_TYPES.pair] do
		local targets = storage.pairs[relation]
		local total_targets = 0

		for target in targets do
			write_entity_id(server, c, target, variants)
			total_targets += 1
		end
		cursor.write_vlq(c, total_targets)
		write_component_id(server, c, relation)
		all_pairs += 1
	end
	cursor.write_vlq(c, all_pairs)

	local components = 0
	for component in active.components[COMPONENT_TYPES.component] do
		local value = storage.values[component]
		write_component_value(server, c, component, value, variants)
		components += 1
	end
	cursor.write_vlq(c, components)

	local tags = 0
	for tag in active.components[COMPONENT_TYPES.tag] do
		local has_tag = storage.tags[tag]
		if has_tag then
			write_component_id(server, c, tag)
			tags += 1
		end
	end
	cursor.write_vlq(c, tags)
	write_entity_id(server, c, entity, variants)
end

type MemberPackets = {
	buffers: { buffer },
	variants: { { any } },
	total_size: number,
}

local function append_packet(
	packets: { [Player]: MemberPackets },
	members: { any },
	output: buffer,
	variants: { { any } }
)
	local len = buffer.len(output)
	for _, member in members do
		local member_packets = packets[member]

		if member_packets then
			table.insert(member_packets.buffers, output)
			table.insert(member_packets.variants, variants)
			member_packets.total_size += len
		else
			member_packets = {
				buffers = { output },
				variants = { variants },
				total_size = len,
			}
			packets[member] = member_packets :: MemberPackets
		end
	end
end

local function combine_packet_outputs(outputs: { buffer }, total_size: number): buffer
	local combined = buffer.create(total_size + utils.vlq_span(#outputs))
	local offset = 0

	for _, output in outputs do
		buffer.copy(combined, offset, output)
		offset += buffer.len(output)
	end
	cursor.write_vlq({
		offset = offset,
		buffer = combined,
	}, #outputs)

	return combined
end

local function create_packet_iterator(packets: { [Player]: MemberPackets })
	local iterated: Player? = nil
	local function iterator()
		local player, packets = next(packets, iterated)
		if not player then
			return nil :: any
		end
		iterated = player

		local combined = combine_packet_outputs(packets.buffers, packets.total_size)
		return player, combined, packets.variants
	end
	return iterator :: () -> (Player, buffer, { { any } })
end

local function get_full(server: Server, member: Player): (buffer, { { any } })
	local index = server.masking.member_indexes[member]
	if index == nil then
		utils.logerror "attempted to replicate for a non registered member"
	end
	local buffers: { buffer } = {}
	local all_variants: { { any } } = {}
	local total_size = 0

	-- maybe edges to quickly find all relevant storages improves performance?
	for _, storage in server.masking.storages do
		if not storage.mask.bitmask:get(index) then
			continue
		end
		local c = cursor.new()
		local variants = {}

		local total_entities = 0
		for entity, active in storage.active do
			write_entity(server, c, entity, active, variants)
			total_entities += 1
		end
		cursor.write_vlq(c, total_entities)

		local output = cursor.close(c)
		table.insert(buffers, output)
		table.insert(all_variants, variants)
		total_size += buffer.len(output)
	end

	return combine_packet_outputs(buffers, total_size), all_variants
end

local function collect_updates(server: Server)
	local packets: { [Player]: MemberPackets } = {}

	for _, storage in server.masking.storages do
		local c = cursor.new()
		local variants = {}

		local total_deleted = 0
		local entity_deletions = storage.deletions.entities
		for entity in entity_deletions do
			write_entity_id(server, c, entity, variants)
			total_deleted += 1
		end
		table.clear(entity_deletions)
		cursor.write_vlq(c, total_deleted)

		local total_component_deleted = 0
		local component_deletions = storage.deletions.components
		for entity, deleted in component_deletions do
			local total_pairs = 0
			for relation in deleted[COMPONENT_TYPES.pair] do
				write_component_id(server, c, relation)
				total_pairs += 1
			end
			cursor.write_vlq(c, total_pairs)

			local total_components = 0
			for component in deleted[COMPONENT_TYPES.component] do
				write_component_id(server, c, component)
				total_components += 1
			end
			cursor.write_vlq(c, total_components)

			local total_tags = 0
			for tag in deleted[COMPONENT_TYPES.tag] do
				write_component_id(server, c, tag)
				total_tags += 1
			end
			cursor.write_vlq(c, total_tags)

			write_entity_id(server, c, entity, variants)
			total_component_deleted += 1
		end
		table.clear(component_deletions)
		cursor.write_vlq(c, total_component_deleted)

		local storage_changes = storage.changes
		local changed = 0
		for entity, changes in storage_changes.changed do
			local total_removed = 0
			for component, value in changes.removed do
				write_component_id(server, c, component)
				total_removed += 1
			end
			cursor.write_vlq(c, total_removed)

			local total_pairs = 0
			for relation, targets in changes.pairs do
				local total_targets = 0

				for target, added in targets do
					if added then
						write_entity_id(server, c, target, variants)
					else
						write_entity_id(server, c, target, variants, -1)
					end
					total_targets += 1
				end
				cursor.write_vlq(c, total_targets)
				write_component_id(server, c, relation)
				total_pairs += 1
			end
			cursor.write_vlq(c, total_pairs)

			local total_components = 0
			for component, value in changes.component do
				write_component_value(server, c, component, value, variants)
				total_components += 1
			end
			cursor.write_vlq(c, total_components)

			local total_tagged = 0
			for tag in changes.tagged do
				write_component_id(server, c, tag)
				total_tagged += 1
			end
			cursor.write_vlq(c, total_tagged)

			write_entity_id(server, c, entity, variants)
			changed += 1
		end
		table.clear(storage_changes.changed)
		cursor.write_vlq(c, changed)

		local total_added = 0
		for entity in storage_changes.added do
			local active = storage.active[entity]
			if not active then
				continue
			end

			write_entity(server, c, entity, active, variants)
			total_added += 1
		end
		table.clear(storage_changes.added)
		cursor.write_vlq(c, total_added)

		local output = cursor.close(c)
		append_packet(packets, storage.mask.members, output, variants)
	end
	table.clear(server.additions)

	return create_packet_iterator(packets)
end

local function collect_unreliable(server: Server)
	-- todo: max packet size (for unreliables 1kb limit)
	local packets: { [Player]: MemberPackets } = {}
	local world = server.world

	-- maybe more lookups to quickly iterate these too? ;-;
	for _, mask_storage in server.masking.storages do
		local c = cursor.new()
		local variants = {}

		local active = mask_storage.active
		local total_entities = 0

		for entity, actives in active do
			local total_unreliable = 0
			for component in actives.components[COMPONENT_TYPES.unreliable] do
				local value = world:get(entity, component)
				if value == nil then
					continue
				end

				write_component_value(server, c, component, value, variants)
				total_unreliable += 1
			end

			if total_unreliable <= 0 then
				continue
			end
			total_entities += 1
			cursor.write_vlq(c, total_unreliable)
			write_entity_id(server, c, entity, variants)
		end

		if total_entities <= 0 then
			continue
		end
		cursor.write_vlq(c, total_entities)

		local output = cursor.close(c)
		append_packet(packets, mask_storage.mask.members, output, variants)
	end

	return create_packet_iterator(packets)
end

local function check_created(server: Server)
	if server.inited == true then
		warn "attempted to init a server twice"
		return false
	end
	if server.inited == nil then
		warn "attempted to create a server twice"
		return false
	end
	return true
end

function init(server: Server, _world: World?)
	if not check_created(server) then
		return
	end
	server.inited = true :: any

	local world = _world or server.world
	server.world = world

	if not world then
		error "Providing a world is required to start replecs"
	end

	local hooks = {
		added = (world :: any).added,
		changed = (world :: any).changed,
		removed = (world :: any).removed,
	}
	server.hooks = hooks

	local components = server.components
	local masking = server.masking

	server.shared = utils.create_shared_lookup(world, components)

	local function hook(unhook: () -> ())
		table.insert(server.hooked, unhook)
	end

	hook(hooks.added(world, components.networked, function(entity, id, filter)
		masking:unregister_stop_entity(entity)
		masking:start_entity(entity, filter)
		masking:propagate_entity_addition(entity)

		server.additions[entity] = true
		server.track_info.entities[entity] = true
		track_entity_lifetime(server, entity)
	end))
	hook(hooks.changed(world, components.networked, function(entity, id, filter)
		masking:set_entity(entity, filter)
	end))
	hook(hooks.removed(world, components.networked, function(entity)
		masking:register_stop_entity(entity)
		masking:stop_entity(entity)

		server.additions[entity] = nil
		server.track_info.entities[entity] = nil
	end))

	hook(hooks.added(world, components.reliable, function(entity, id, filter)
		if not IS_PAIR(id) then
			utils.logerror "reliable should be used with a pair relationship"
		end
		local component = PAIR_SECOND(world, id)

		local component_type = track_entity_component(server :: Server, entity, component)
		masking:unregister_stop_component(entity, component, component_type)
		masking:start_component(entity, component, component_type, filter)
		if server.additions[entity] then
			masking:allocate_entity_addition(entity, component, component_type)
		end
	end))
	hook(hooks.changed(world, components.reliable, function(entity, id, filter)
		if not IS_PAIR(id) then
			utils.logerror "reliable should be used with a pair relationship"
		end
		local component = PAIR_SECOND(world, id)

		if world:has(component, ECS_COMPONENT) then
			masking:set_component(entity, component, COMPONENT_TYPES.component, filter)
		else
			masking:set_component(entity, component, COMPONENT_TYPES.tag, filter)
		end
	end))
	hook(hooks.removed(world, components.reliable, function(entity, id)
		if not IS_PAIR(id) then
			utils.logerror "reliable should be used with a pair relationship"
		end
		local component = PAIR_SECOND(world, id)
		local component_type = untrack_entity_component(server, entity, component)
		if not component_type then
			return
		end
		masking:register_stop_component(entity, component, component_type)
		masking:stop_component(entity, component, component_type)
	end))

	hook(hooks.added(world, components.pair, function(entity, id, filter)
		if not IS_PAIR(id) then
			utils.logerror "pair should be used with a relationship"
		end
		local relation = PAIR_SECOND(world, id)
		track_entity_pair(server, entity, relation)
		masking:unregister_stop_component(entity, relation, COMPONENT_TYPES.pair)
		masking:start_component(entity, relation, COMPONENT_TYPES.pair, filter)
	end))
	hook(hooks.changed(world, components.pair, function(entity, id, filter)
		if not IS_PAIR(id) then
			utils.logerror "reliable should be used with a pair relationship"
		end
		local relation = PAIR_SECOND(world, id)
		masking:set_component(entity, relation, COMPONENT_TYPES.pair, filter)
	end))
	hook(hooks.removed(world, components.pair, function(entity, id)
		if not IS_PAIR(id) then
			utils.logerror "reliable should be used with a pair relationship"
		end
		local relation = PAIR_SECOND(world, id)
		untrack_entity_pair(server, entity, relation)
		masking:register_stop_component(entity, relation, COMPONENT_TYPES.pair)
		masking:stop_component(entity, relation, COMPONENT_TYPES.pair)
	end))

	hook(hooks.added(world, components.unreliable, function(entity, id, filter)
		if not IS_PAIR(id) then
			utils.logerror "unreliable should be used with a pair relationship"
		end
		local component = PAIR_SECOND(world, id)
		masking:unregister_stop_component(entity, component, COMPONENT_TYPES.unreliable)
		masking:start_component(entity, component, COMPONENT_TYPES.unreliable, filter)
		if server.additions[entity] then
			masking:allocate_entity_addition(entity, component, COMPONENT_TYPES.unreliable)
		end
	end))
	hook(hooks.changed(world, components.unreliable, function(entity, id, filter)
		if not IS_PAIR(id) then
			utils.logerror "unreliable should be used with a pair relationship"
		end
		local component = PAIR_SECOND(world, id)
		masking:set_component(entity, component, COMPONENT_TYPES.unreliable, filter)
	end))
	hook(hooks.removed(world, components.unreliable, function(entity, id)
		if not IS_PAIR(id) then
			utils.logerror "unreliable should be used with a pair relationship"
		end
		local component = PAIR_SECOND(world, id)
		untrack_entity_component(server, entity, component, COMPONENT_TYPES.unreliable)
		masking:register_stop_component(entity, component, COMPONENT_TYPES.unreliable)
		masking:stop_component(entity, component, COMPONENT_TYPES.unreliable)
	end))

	hook(hooks.added(world, components.custom_id, function(entity, id)
		if not IS_PAIR(id) then
			utils.logerror "custom_id should be used with a relationship in the server"
		end
		local target = PAIR_SECOND(world, id)
		if server.custom_ids[entity] then
			utils.logwarn("attempted to register a custom_id twice for the same entity", debug.traceback())
			return
		end

		server.custom_ids[entity] = target
	end))
	hook(hooks.removed(world, components.custom_id, function(entity, id)
		server.custom_ids[entity] = nil
	end))

	hook(hooks.removed(world, components.__alive_tracking__, function(entity)
		-- TODO: cleanup entity garbage on deletion
		server.custom_ids[entity] = nil
	end))

	if game and game:GetService("RunService"):IsServer() then
		local added = game:GetService("Players").PlayerAdded:Connect(function(player)
			server.masking:register_member(player)
		end)
		local removed = game:GetService("Players").PlayerRemoving:Connect(function(player)
			server.masking:unregister_member(player)
		end)

		table.insert(server.connections, added)
		table.insert(server.connections, removed)
	end
end

local function mark_player_ready(server: Server, player: Player)
	server.masking:activate_member(player)
end

local function is_player_ready(server: Server, player: Player): boolean
	return server.masking:member_is_active(player)
end

local function destroy(server: Server)
	if server.inited == nil then
		return warn "attempted to destroy a server twice"
	end
	server.inited = nil :: any

	for _, unhook in server.hooked do
		unhook()
	end
	for _, connection in server.connections do
		connection:Disconnect()
	end
end

local server = {}
server.__index = server
server.init = init
server.destroy = destroy
server.get_full = get_full
server.collect_updates = collect_updates
server.collect_unreliable = collect_unreliable
server.mark_player_ready = mark_player_ready
server.is_player_ready = is_player_ready

local function create(world: World?, components: common.Components): Server
	local self = {} :: Server

	self.components = components

	self.shared = {} :: common.Shared
	self.world = world :: any
	self.additions = {}
	self.storage = {}
	self.hooked = {}
	self.track_info = {
		entities = {},
		components = {},
	}
	self.connections = {}
	self.inited = false
	self.masking = masking_controller.create()
	self.alive_tracked = {}
	self.custom_ids = {}

	return setmetatable(self, server) :: any
end

server.create = create

return server :: { create: typeof(create) }
