script.on_init(function()
    game.speed = 1000
    game.surfaces[1].request_to_generate_chunks({0, 0}, 4)
    game.surfaces[1].force_generate_chunk_requests()
end)

script.on_event(defines.events.on_entity_damaged, function(event)
    if event.entity == storage.enemy then
        storage.damage = event.original_damage_amount
        local elapsed = game.tick - storage.started
        if elapsed >= 1700 and elapsed < 1800 then storage.base_shots = (storage.base_shots or 0) + 1 end
        if elapsed >= 1880 and elapsed < 1980 then storage.advanced_shots = (storage.advanced_shots or 0) + 1 end
    end
end)

script.on_event(defines.events.on_tick, function(event)
    local player = game.get_player(1)
    if not player then return end
    if not player.character then player.create_character() end
    local surface = player.physical_surface
    if not storage.started then
        local drone = surface.find_entities_filtered{name = "companion"}[1]
        if not drone then return end
        player.character.destructible = false
        player.teleport({0, 0})
        for _, entity in ipairs(surface.find_entities_filtered{force = {"neutral", "enemy"}, area = {{-40, -40}, {120, 40}}}) do
            if entity.valid and entity.type ~= "resource" then entity.destroy() end
        end
        local tiles = {}
        for x = -40, 120 do for y = -40, 40 do tiles[#tiles + 1] = {name = "grass-1", position = {x, y}} end end
        surface.set_tiles(tiles)
        player.get_main_inventory().clear()
        for _, x in ipairs{0, 16, 32} do
            assert(surface.create_entity{name = "substation", position = {x, 10}, force = player.force})
        end
        storage.supply = assert(surface.create_entity{name = "steel-chest", position = {32, 8}, force = player.force})
        storage.supply.insert{name = "iron-plate", count = 20}
        assert(surface.create_entity{name = "substation", position = {0, -20}, force = player.force})
        storage.isolated = assert(surface.create_entity{name = "steel-chest", position = {0, -20}, force = player.force})
        storage.isolated.insert{name = "iron-plate", count = 99}
        storage.drone, storage.targets = drone, {}
        for _, x in ipairs{-15, 15} do
            storage.targets[#storage.targets + 1] = assert(surface.create_entity{
                name = "entity-ghost", inner_name = "transport-belt", position = {x, 0}, force = player.force})
        end
        storage.started = event.tick
    end
    local elapsed = event.tick - storage.started
    storage.positions = storage.positions or {}
    for _, entity in ipairs(surface.find_entities_filtered{name = {"companion-crafter", "companion-task-manager", "companion-combat-robot"}}) do
        local previous, position = storage.positions[entity.unit_number], entity.position
        local speed = entity.name == "companion-crafter" and 0.075 or entity.name == "companion-task-manager" and 0.09 or 0.045
        if previous then
            assert((position.x - previous.x)^2 + (position.y - previous.y)^2 <= (speed + math.sqrt(2) / 256)^2,
                "mini drone displacement stays within its default flight speed")
        end
        storage.positions[entity.unit_number] = position
    end
    if elapsed == 200 then
        assert(surface.count_entities_filtered{name = "companion-crafter"} == 1, "one two-output recipe supplies both separated tasks: " .. surface.count_entities_filtered{name = "companion-crafter"} .. " plates " .. storage.supply.get_item_count("iron-plate"))
        assert(storage.supply.get_item_count("iron-plate") == 17, "one belt recipe reserves exactly three plates from a remote ordinary chest")
        assert(storage.isolated.get_item_count("iron-plate") == 99, "a disconnected electrical network stays private")
        local items, small = {}, false
        for _, object in pairs(rendering.get_all_objects("companion-drones-luan")) do
            if object.type == "sprite" then items[object.sprite] = true end
            if object.type == "animation" and object.animation == "companion-animation-1" then small = object.x_scale == 0.5 end
        end
        assert(items["item/iron-gear-wheel"] and items["item/transport-belt"], "floating queue shows intermediate and final product")
        assert(small, "main companion renders at half size")
        storage.crafter = surface.find_entities_filtered{name = "companion-crafter"}[1]
        storage.landing = storage.crafter.position
        player.teleport({100, 0})
        game.auto_save("crew-qa")
    elseif elapsed == 300 then
        assert(storage.crafter.valid, "walking away keeps the crafter alive")
        assert(storage.crafter.position.x == storage.landing.x and storage.crafter.position.y == storage.landing.y,
            "crafter continues at its original landing position")
    elseif elapsed == 650 then
        assert(storage.crafter.valid, "finished crafter keeps its output while returning")
        assert(storage.crafter.position.x > storage.landing.x + 1, "finished crafter flies back toward the distant owner")
        player.teleport({0, 0})
    elseif elapsed == 1600 then
        for _, ghost in ipairs(storage.targets) do assert(not ghost.valid, "both tasks use the single craft's output") end
        assert(storage.supply.get_item_count("iron-plate") == 17, "no second recipe is crafted after delivery")
        assert(surface.count_entities_filtered{name = "companion-crafter"} == 0, "finished crafter returns and disappears")
        assert(player.crafting_queue_size == 0, "crew queue is separate from player crafting")
        log("COMPANION surplus reservation, floating recipe queue, half size and distant crafter completion PASS")
        storage.enemy = assert(surface.create_entity{name = "companion-combat-target", position = {8, 0}, force = "enemy"})
    elseif elapsed == 1800 then
        assert(storage.damage and storage.damage > 0, "baseline escorts attack")
        storage.base_damage = storage.damage
        storage.base_squad = surface.count_entities_filtered{name = "companion-combat-robot"}
        storage.base_banks = 0
        for _, equipment in pairs(storage.drone.grid.equipment) do
            if equipment.name == "companion-defense-equipment" then storage.base_banks = storage.base_banks + 1 end
        end
        player.force.technologies["military-2"].researched = true
        player.force.technologies["military-3"].researched = true
        player.force.technologies["military-4"].researched = true
        player.force.set_ammo_damage_modifier("laser", 1)
        player.force.set_gun_speed_modifier("laser", 1)
    elseif elapsed == 1980 then
        local banks = 0
        for _, equipment in pairs(storage.drone.grid.equipment) do
            if equipment.name == "companion-defense-equipment" then banks = banks + 1 end
        end
        assert(storage.damage == storage.base_damage * 6 * banks / storage.base_banks * storage.base_squad / surface.count_entities_filtered{name = "companion-combat-robot"}, "military tiers, laser damage and firing-speed research scale squad power: " .. tostring(storage.damage) .. " vs " .. tostring(storage.base_damage))
        local squad = surface.count_entities_filtered{name = "companion-combat-robot"}
        local rate = storage.advanced_shots / storage.base_shots * storage.base_squad / squad
        assert(rate > 1.5 and rate < 2.5, "laser speed research doubles native firing rate")
        log("COMPANION military tier and laser research scaling PASS")
        player.force.technologies.electronics.researched = true
        storage.supply.insert{name = "copper-plate", count = 4}
        local chest = assert(surface.create_entity{name = "infinity-chest", position = {34, 8}, force = player.force})
        chest.remove_unfiltered_items = false
        chest.insert{name = "stone-furnace", quality = "uncommon", count = 1}
        storage.intermediate_targets = {}
        for _, x in ipairs{-15, 15} do
            storage.intermediate_targets[#storage.intermediate_targets + 1] = assert(surface.create_entity{
                name = "entity-ghost", inner_name = "inserter", position = {x, 4}, force = player.force})
        end
        storage.quality_target = assert(surface.create_entity{name = "entity-ghost", inner_name = "stone-furnace",
            quality = "uncommon", position = {15, -8}, force = player.force})
    elseif elapsed == 2800 then
        for _, ghost in ipairs(storage.intermediate_targets) do assert(not ghost.valid, "both inserters complete") end
        assert(storage.supply.get_item_count("iron-plate") == 9, "two inserters consume eight iron plates")
        assert(storage.supply.get_item_count("copper-plate") == 1, "second craft reuses the first craft's spare cable")
        assert(not storage.quality_target.valid, "quality chest materials reach the manager without substitution")
        assert(surface.find_entities_filtered{name = "stone-furnace", quality = "uncommon"}[1], "construction retains item quality")
        log("COMPANION intermediate surplus collaboration and quality construction PASS")
        log("COMPANION INTEGRATION PASS")
        script.on_event(defines.events.on_tick, nil)
    end
end)
