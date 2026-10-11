local function check(actual, expected, label)
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check_all_built()
	for _, ghost in ipairs(storage.targets or {}) do
		check(ghost.valid, false, "shared task completed")
	end
end
local function ghost(player, name, position)
	local entity = assert(
		player.surface.create_entity({ name = "entity-ghost", inner_name = name, position = position, force = player.force })
	)
	storage.targets[#storage.targets + 1] = entity
end
local function begin(phase)
	storage.phase, storage.started = phase, game.tick
end
local function pass(label)
	log("ENTOURAGE MULTIPLAYER PASS: " .. label)
end
script.on_init(function()
	game.surfaces[1].request_to_generate_chunks({ 0, 0 }, 2)
	game.surfaces[1].force_generate_chunk_requests()
end)
remote.add_interface("entourage_multiplayer_qa", {
	start = function()
		check(#game.connected_players, 2, "two real clients connected")
		storage.players = { game.connected_players[1], game.connected_players[2] }
		storage.drones = {}
		local surface = game.surfaces[1]
		surface.always_day = true
		for _, entity in
			pairs(
				surface.find_entities_filtered({ area = { { -50, -50 }, { 50, 50 } }, force = { "neutral", "enemy" } })
			)
		do
			if entity.valid and entity.type ~= "resource" then
				entity.destroy()
			end
		end
		local tiles = {}
		for x = -50, 50 do
			for y = -50, 50 do
				tiles[#tiles + 1] = { name = "grass-1", position = { x, y } }
			end
		end
		surface.set_tiles(tiles)
		for i, player in ipairs(storage.players) do
			player.admin = true
			player.color = i == 1 and { r = 0.85, g = 0.15, b = 0.1 } or { r = 0.1, g = 0.4, b = 0.9 }
			player.teleport({ i == 1 and -6 or 6, 0 }, surface)
			player.character.destructible = false
			player.get_main_inventory().clear()
			player.set_shortcut_toggled("companion-construction-toggle", true)
			player.set_shortcut_toggled("companion-attack-toggle", true)
			player.zoom = 1.2
			player.clear_console()
		end
		game.speed = 4
		begin("ownership")
	end,
	reconnect = function()
		check(#game.connected_players, 2, "both clients rejoined")
		for _, drone in ipairs(storage.drones) do
			check(drone.valid, true, "original companion survives reconnect")
		end
		check(
			game.surfaces[1].count_entities_filtered({ name = "companion" }),
			2,
			"reconnect does not duplicate companions"
		)
		pass("disconnect and reconnect retain both companions")
		local b = storage.players[2]
		b.get_main_inventory().clear()
		storage.drones[2].get_inventory(defines.inventory.spider_trunk).clear()
		begin("refund")
	end,
	death = function()
		local b = storage.players[2]
		b.character.destructible = true
		b.character.die()
		b.ticks_to_respawn = 1
		begin("death")
	end,
	verify_reload = function()
		check(#game.connected_players, 2, "both clients reconnect after server restart")
		for _, drone in ipairs(storage.drones) do
			check(drone.valid, true, "companion identity survives server save and load")
		end
		check(
			game.surfaces[1].count_entities_filtered({ name = "companion" }),
			4,
			"server reload does not duplicate researched fleets"
		)
		pass("server save, reload and reconnect retain both fleets")
	end,
	status = function()
		return { phase = storage.phase, tick = game.tick, connected = #game.connected_players }
	end,
})
script.on_event(defines.events.on_player_left_game, function(event)
	if storage.phase == "await-disconnect" and event.player_index == storage.players[2].index then
		storage.players[1].set_shortcut_toggled("companion-construction-toggle", true)
		storage.players[1].insert({ name = "stone", count = 5 })
		begin("disconnected")
	end
end)
script.on_event(defines.events.on_tick, function()
	if not storage.phase then
		return
	end
	local elapsed = game.tick - storage.started
	local a, b = storage.players[1], storage.players[2]
	local surface = a.physical_surface
	if storage.phase == "ownership" and elapsed >= 180 then
		local drones = surface.find_entities_filtered({ name = "companion" })
		check(#drones, 2, "one starter per connected player")
		for _, drone in ipairs(drones) do
			local index = drone.color.r > drone.color.b and 1 or 2
			storage.drones[index] = drone
			local owner = storage.players[index]
			assert(
				(drone.position.x - owner.position.x) ^ 2 + (drone.position.y - owner.position.y) ^ 2 < 12 ^ 2,
				"companion follows its own owner"
			)
		end
		assert(storage.drones[1] and storage.drones[2], "distinct owner colors")
		pass("separate owners, colors and starter companions")
		storage.roboport = assert(surface.create_entity({ name = "roboport", position = { 0, 12 }, force = a.force }))
		storage.roboport.energy = storage.roboport.electric_buffer_size
		storage.provider =
			assert(surface.create_entity({ name = "passive-provider-chest", position = { 0, 8 }, force = a.force }))
		storage.provider.insert({ name = "stone", count = 20 })
		storage.provider.insert({ name = "transport-belt", count = 6 })
		storage.provider.insert({ name = "iron-plate", count = 3 })
		storage.targets = {}
		for i = 1, 4 do
			ghost(a, "stone-furnace", { i * 2 - 5, -6 })
		end
		for i = 1, 6 do
			ghost(a, "transport-belt", { i - 3, -2 })
		end
		begin("shared-network")
	elseif storage.phase == "shared-network" and elapsed >= 900 then
		check_all_built()
		check(storage.provider.get_item_count("stone"), 0, "shared crafting uses exact ingredients")
		check(storage.provider.get_item_count("transport-belt"), 0, "shared building uses exact materials")
		check(storage.provider.get_item_count("iron-plate"), 3, "unrelated shared chest contents untouched")
		for _, player in ipairs(storage.players) do
			check(player.crafting_queue_size, 0, "no player handcrafting")
		end
		pass("two owners share tasks and logistics materials without duplicate consumption")
		a.set_shortcut_toggled("companion-construction-toggle", false)
		b.set_shortcut_toggled("companion-construction-toggle", false)
		a.insert({ name = "transport-belt", count = 10 })
		b.insert({ name = "transport-belt", count = 7 })
		storage.targets = {}
		ghost(a, "transport-belt", { 0, -10 })
		begin("toggles-off")
	elseif storage.phase == "toggles-off" and elapsed >= 180 then
		check(storage.targets[1].valid, true, "both toggles stop shared construction")
		check(a.get_item_count("transport-belt"), 10, "first player inventory untouched while disabled")
		check(b.get_item_count("transport-belt"), 7, "second player inventory untouched while disabled")
		a.set_shortcut_toggled("companion-construction-toggle", true)
		begin("owner-inventory")
	elseif storage.phase == "owner-inventory" and elapsed >= 180 then
		check_all_built()
		check(a.get_item_count("transport-belt"), 9, "enabled owner supplies one belt")
		check(b.get_item_count("transport-belt"), 7, "other player inventory untouched")
		pass("per-player toggles and private player inventory")
		local force = game.create_force("entourage-qa-other")
		b.force = force
		b.set_shortcut_toggled("companion-construction-toggle", true)
		storage.targets = {}
		ghost(b, "transport-belt", { 0, -12 })
		begin("separate-force")
	elseif storage.phase == "separate-force" and elapsed >= 180 then
		check_all_built()
		check(a.get_item_count("transport-belt"), 9, "other force cannot consume first player inventory")
		check(b.get_item_count("transport-belt"), 6, "second force uses its owner inventory")
		check(storage.drones[1].force, a.force, "first companion remains on its force")
		check(storage.drones[2].force, b.force, "second companion changes force")
		pass("force isolation and force changes")
		b.force = a.force
		a.set_shortcut_toggled("companion-construction-toggle", false)
		b.set_shortcut_toggled("companion-construction-toggle", true)
		b.insert({ name = "stone", count = 5 })
		storage.targets = {}
		ghost(b, "stone-furnace", { 1, -14 })
		begin("await-crafter")
	elseif storage.phase == "await-crafter" and elapsed >= 30 then
		check(b.get_item_count("stone"), 0, "second owner reserves crafting materials")
		check(
			surface.count_entities_filtered({ name = "companion-crafter" }),
			1,
			"second owner is crafting before disconnect"
		)
		for _, inventory in ipairs({
			b.get_main_inventory(),
			storage.drones[2].get_inventory(defines.inventory.spider_trunk),
		}) do
			for i = 1, #inventory do
				inventory[i].set_stack({ name = "iron-plate", count = 100 })
			end
		end
		pass("ready for second client disconnect")
		begin("await-disconnect")
	elseif storage.phase == "disconnected" and elapsed >= 600 then
		check(storage.players[2].connected, false, "second client disconnected")
		check_all_built()
		check(storage.drones[2].valid, true, "offline owner keeps companion")
		check(
			surface.count_entities_filtered({ name = "companion-task-manager" }),
			0,
			"offline assignments are recalled"
		)
		check(
			b.get_item_count("stone") + storage.drones[2].get_item_count("stone"),
			0,
			"full inventories keep the reserved ingredients in the returning crafter"
		)
		pass("remaining client keeps working after other client disconnects")
		begin("await-reconnect")
	elseif storage.phase == "refund" and elapsed >= 180 then
		check(
			b.get_item_count("stone") + storage.drones[2].get_item_count("stone"),
			5,
			"reserved materials return after space becomes available"
		)
		check(surface.count_entities_filtered({ name = "companion-crafter" }), 0, "refunded crafter disappears")
		pass("full inventories conserve offline cargo and release its task claim")
		remote.call("entourage_multiplayer_qa", "death")
	elseif storage.phase == "death" and elapsed >= 180 then
		assert(b.character and b.character.valid, "second player respawns")
		check(storage.drones[2].valid, true, "death preserves second owner companion identity")
		pass("second owner death and respawn keep its original companion")
		begin("research")
	elseif storage.phase == "research" and elapsed >= 1 then
		a.force.technologies["companion-crafting-speed-1"].level = 2
		a.force.technologies["companion-planet-vulcanus"].researched = true
		a.force.technologies["companion-planet-fulgora"].researched = true
		begin("fleet")
	elseif storage.phase == "fleet" and elapsed >= 180 then
		check(
			surface.count_entities_filtered({ name = "companion" }),
			4,
			"shared planet research grants one extra to each player"
		)
		pass("shared research expands both owner fleets")
		local other = game.planets.vulcanus.create_surface()
		other.request_to_generate_chunks({ 0, 0 }, 1)
		other.force_generate_chunk_requests()
		local position = other.find_non_colliding_position("character", { 0, 0 }, 100, 1)
		assert(a.teleport(position, other))
		begin("planet")
	elseif storage.phase == "planet" and elapsed >= 180 then
		check(a.physical_surface.count_entities_filtered({ name = "companion" }), 2, "only first owner fleet travels")
		check(b.physical_surface.count_entities_filtered({ name = "companion" }), 2, "other owner fleet remains")
		pass("planet travel moves only the traveling owner fleet")
		local platform = a.force.create_space_platform({
			name = "Entourage QA",
			planet = "vulcanus",
			starter_pack = "space-platform-starter-pack",
		})
		platform.apply_starter_pack()
		storage.platform = platform
		platform.surface.set_tiles({ { name = "space-platform-foundation", position = { 0, 4 } } })
		assert(a.teleport({ 0, 4 }, platform.surface))
		begin("platform")
	elseif storage.phase == "platform" and elapsed >= 180 then
		check(storage.platform.surface.count_entities_filtered({ name = "companion" }), 0, "fleet stays off platform")
		check(b.physical_surface.count_entities_filtered({ name = "companion" }), 2, "other owner remains active")
		pass("one owner parks on a platform while the other keeps its fleet")
		a.teleport({ -6, 0 }, b.physical_surface)
		game.speed = 1
		begin("passed")
		log("ENTOURAGE MULTIPLAYER INTEGRATION PASS")
	end
end)
