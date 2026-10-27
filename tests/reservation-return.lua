local function ghost(player, name, position)
    return assert(player.surface.create_entity{name = "entity-ghost", inner_name = name,
        position = position, force = player.force})
end

local function fill_trunk(drone)
    local inventory = drone.get_inventory(defines.inventory.spider_trunk)
    inventory.clear()
    for slot = 1, 20 do inventory[slot].set_stack{name = "stone", count = 100} end
    return inventory
end

script.on_init(function()
    game.speed = 1000
    game.surfaces[1].request_to_generate_chunks({0, 0}, 2)
    game.surfaces[1].force_generate_chunk_requests()
end)

script.on_event(defines.events.on_tick, function(event)
    local player = game.get_player(1)
    if not player then return end
    if not player.character then player.create_character() end
    if not storage.started then
        local drone = player.surface.find_entities_filtered{name = "companion"}[1]
        if not drone then return end
        player.character.destructible = false
        player.teleport({0, 0})
        for _, entity in pairs(player.surface.find_entities_filtered{area = {{-20, -20}, {20, 20}}, force = {"neutral", "enemy"}}) do
            if entity.valid and entity.type ~= "resource" then entity.destroy() end
        end
        local tiles = {}
        for x = -20, 20 do for y = -20, 20 do tiles[#tiles + 1] = {name = "grass-1", position = {x, y}} end end
        player.surface.set_tiles(tiles)
        drone.teleport({2, 0})
        drone.grid.clear()
        drone.grid.put{name = "companion-roboport-mk3"}
        player.set_shortcut_toggled("companion-construction-toggle", true)
        local inventory = player.get_main_inventory()
        for slot = 1, #inventory do inventory[slot].set_stack{name = "stone", count = 100} end
        inventory[#inventory].set_stack{name = "transport-belt", count = 1}
        fill_trunk(drone)
        storage.drone = drone
        storage.belt = ghost(player, "transport-belt", {4, 0})
        storage.started = event.tick
    end
    local elapsed, drone = event.tick - storage.started, storage.drone
    local trunk = drone.get_inventory(defines.inventory.spider_trunk)
    if elapsed == 60 then
        assert(storage.belt.valid, "a full trunk leaves the unsupplied task pending")
        assert(player.get_item_count("transport-belt") == 1, "failed reservation preserves uncollected materials")
        assert(player.surface.count_entities_filtered{name = "companion-task-manager"} == 0,
            "empty failed reservations do not leave managers behind")
        trunk.clear()
    elseif elapsed == 180 then
        assert(not storage.belt.valid, "the task resumes when trunk space becomes available")
        assert(player.get_item_count("transport-belt") + drone.get_item_count("transport-belt") == 0,
            "the successful retry consumes exactly one belt")
        log("COMPANION empty failed reservation and retry PASS")
        local inventory = player.get_main_inventory()
        for slot = 1, #inventory do inventory[slot].set_stack{name = "stone", count = 100} end
        inventory[#inventory].set_stack{name = "stone-furnace", count = 1}
        fill_trunk(drone)[20].set_stack{name = "transport-belt", count = 3}
        storage.partial_belt = ghost(player, "transport-belt", {4, 4})
        storage.furnace = ghost(player, "stone-furnace", {6, 4})
    elseif elapsed == 240 then
        assert(storage.partial_belt.valid and storage.furnace.valid, "partially supplied batches stay pending")
        assert(player.get_item_count("transport-belt") + drone.get_item_count("transport-belt") == 3,
            "failed batches return every reserved belt")
        assert(player.get_item_count("stone-furnace") == 1, "failed batches preserve the unavailable furnace")
        assert(player.surface.count_entities_filtered{name = "companion-task-manager"} == 0,
            "refunded failed reservations do not leave managers behind")
        -- Free space without discarding the materials needed by the pending batch.
        trunk.remove{name = "stone", count = trunk.get_item_count("stone")}
    elseif elapsed == 360 then
        assert(not storage.partial_belt.valid and not storage.furnace.valid, "both tasks resume after a partial refund")
        assert(player.get_item_count("transport-belt") + drone.get_item_count("transport-belt") == 2,
            "retry consumes one belt without losing or duplicating the refund")
        assert(player.get_item_count("stone-furnace") + drone.get_item_count("stone-furnace") == 0,
            "retry consumes exactly one furnace")
        assert(player.surface.count_entities_filtered{name = "companion-task-manager"} == 0,
            "successful retry cleans up its manager")
        log("COMPANION partial failed reservation, refund and retry PASS")
        log("COMPANION INTEGRATION PASS")
        script.on_event(defines.events.on_tick, nil)
    end
end)
