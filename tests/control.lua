local function check(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function ghost(name, position, quality, surface)
    return assert((surface or game.surfaces[1]).create_entity{name = "entity-ghost", inner_name = name,
        position = position, force = "player", quality = quality})
end

local function setup(player)
    if not player.character then player.create_character() end
    player.character.destructible = false
    player.teleport({0, 0})
    local surface = player.surface
    for _, entity in pairs(surface.find_entities_filtered{area = {{-40, -40}, {40, 40}}, force = {"neutral", "enemy"}}) do
        if entity.valid and entity ~= player.character and entity.name ~= "companion" and entity.type ~= "resource" then entity.destroy() end
    end
    local tiles = {}
    for x = -40, 40 do for y = -40, 40 do tiles[#tiles + 1] = {name = "grass-1", position = {x, y}} end end
    surface.set_tiles(tiles)
    for name, recipe in pairs(player.force.recipes) do
        assert(name ~= "companion" and name:sub(1, 10) ~= "companion-", "no obsolete companion/equipment recipe: " .. name)
    end
    check(prototypes.entity.companion.mineable_properties.minable, false, "companion prototype cannot be mined")
    check(prototypes.item.companion.hidden, true, "legacy drone item is hidden")
    player.get_main_inventory().clear()
    player.insert{name = "coal", count = 150}
    player.insert{name = "transport-belt", count = 150}
    local entity = assert(surface.find_entities_filtered{name = "companion"}[1], "automatic starter companion")
    entity.teleport({2, 0})
    entity.grid.clear()
    entity.grid.put{name = "companion-roboport-mk3"}
    entity.grid.put{name = "companion-defense-equipment"}
    player.set_shortcut_toggled("companion-construction-toggle", true)
    player.set_shortcut_toggled("companion-attack-toggle", true)
    storage.follower_allowance = player.force.maximum_following_robot_count
    storage.companion = entity
    player.insert{name = "companion", count = 1}
    storage.legacy_drone_ghost = ghost("companion", {12, 0}, nil, player.surface)
    storage.missing = ghost("assembling-machine-1", {-4, 0})
    storage.belt = ghost("transport-belt", {5, 0})
    log("COMPANION scenario started")
end

script.on_init(function()
    game.speed = 1000
    game.surfaces[1].request_to_generate_chunks({0, 0}, 2)
    game.surfaces[1].force_generate_chunk_requests()
end)

script.on_event(defines.events.on_player_died, function(event)
    local drone = storage.companion
    check(drone.valid, true, "drone survives character death")
    check(drone.unit_number, storage.identity, "character death preserves drone identity")
    log("COMPANION permanent identity PASS")
    log("COMPANION INTEGRATION PASS")
    script.on_event(defines.events.on_tick, nil)
end)

script.on_event(defines.events.on_tick, function(event)
    local player = game.get_player(1)
    if not player then return end
    if not storage.started and not player.character then player.create_character() end
    if not storage.started then
        if #player.surface.find_entities_filtered{name = "companion"} == 0 then return end
        setup(player)
        storage.started = event.tick
    end
    local elapsed = event.tick - storage.started
    local drone = storage.companion
    if elapsed > 1140 and elapsed < 1200 then
        local managers = player.surface.find_entities_filtered{name = "companion-task-manager"}
        assert(#managers <= 6, "at most six task managers")
        for _, manager in pairs(managers) do storage.observed_managers[manager.unit_number] = true end
    end
    if elapsed > 700 and elapsed < 900 then
        check(player.crafting_queue_size, 0, "private crafting never enters player queue")
        if not storage.craft_started and player.get_item_count("stone") == 145 then storage.craft_started = event.tick end
        local duration = storage.craft_started and event.tick - storage.craft_started
        local base = settings.startup["companion-crafting-speed"].value
        if duration == 30 then
            local frame = player.gui.screen.companion_crafting_queue
            assert(not frame, "crafting does not add a HUD queue")
            local icon, gear = false, false
            for _, object in pairs(rendering.get_all_objects("companion-drones-luan")) do
                if object.type == "sprite" and object.sprite == "item/stone-furnace" then icon = object.visible end
                if object.type == "animation" and object.animation == "companion-landing-gear" then gear = gear or object.visible end
            end
            assert(icon and gear, "crafting has an overhead icon and deployed modeled landing gear")
            check(storage.player_craft.valid, true, "craft takes recipe time before speed upgrade")
            -- Setting level 2 researches the first level through Factorio's public API.
            player.force.technologies["companion-crafting-speed-1"].level = 2
        end
        if duration and not storage.craft_deadline and player.force.technologies["companion-crafting-speed-1"].level == 2 then
            local work = player.force.recipes["stone-furnace"].energy * 60
            storage.craft_deadline = event.tick + math.ceil((work - duration * base) / (base * 1.5)) + 5
            assert(storage.craft_deadline < storage.craft_started + work / base, "timing check precedes unupgraded completion")
        end
        if event.tick == storage.craft_deadline then
            local output = drone.get_item_count("stone-furnace") + player.get_item_count("stone-furnace")
            for _, robot in pairs(player.surface.find_entities_filtered{name = "companion-construction-robot"}) do
                output = output + robot.get_inventory(defines.inventory.robot_cargo).get_item_count("stone-furnace")
            end
            assert(not storage.player_craft.valid or output >= 1 or player.surface.count_entities_filtered{name = "companion-crafter"} == 0,
                "configured speed and research accelerate a craft already in progress")
            storage.speed_checked = true
            log("COMPANION configurable and researched crafting speed PASS")
        end
    end
    if elapsed >= 365 and elapsed < 420 and settings.startup["set-mode"].value == 0 then
        storage.escort_positions = storage.escort_positions or {}
        for _, robot in pairs(player.surface.find_entities_filtered{name = "companion-combat-robot"}) do
            local old, pos = storage.escort_positions[robot.unit_number], robot.position
            if old then assert((pos.x-old.x)^2 + (pos.y-old.y)^2 <= 0.166^2, "escorts move smoothly each tick: " .. math.sqrt((pos.x-old.x)^2 + (pos.y-old.y)^2)) end
            storage.escort_positions[robot.unit_number] = pos
        end
        if elapsed == 370 then storage.combat_health = storage.enemy.health end
        if elapsed == 418 then check(storage.combat_health - storage.enemy.health, 160, "four escorts preserve the original 200 DPS") end
    end
    if elapsed == 120 then
        check(storage.legacy_drone_ghost.valid, true, "legacy blueprints cannot create unregistered companions")
        check(player.get_item_count("companion"), 1, "legacy drone item is preserved")
        check(player.surface.count_entities_filtered{name = "companion"}, 1, "legacy blueprint cannot bypass fleet capacity")
        storage.legacy_drone_ghost.destroy()
        check(storage.belt.valid, false, "build available belt past missing assembler")
        check(storage.missing.valid, true, "unavailable assembler stays a ghost")
        check(player.get_item_count("transport-belt"), 149, "only required belt taken")
        check(player.get_item_count("coal"), 150, "no fuel taken")
        check(drone.burner, nil, "fuel-free vehicle")
        check(drone.minable, false, "permanent companion cannot be mined")
        check(drone.destructible, false, "permanent companion cannot be destroyed")
        for _, equipment in pairs(drone.grid.equipment) do check(equipment.energy, equipment.max_energy, "instant equipment energy") end
        log("COMPANION bounded supplies and missing-task skip PASS")
        local roboport = assert(player.surface.create_entity{name = "roboport", position = {0, 10}, force = player.force})
        roboport.energy = roboport.electric_buffer_size
        storage.roboport = roboport
        storage.provider = assert(player.surface.create_entity{name = "passive-provider-chest", position = {1, 10}, force = player.force})
        storage.provider.insert{name = "inserter", count = 100}
        player.insert{name = "inserter", count = 100}
        storage.network_build = ghost("inserter", {6, 0})
        storage.wide_build = ghost("transport-belt", {40, 0})
    elseif elapsed == 360 then
        check(storage.wide_build.valid, false, "hidden workers build 40 tiles from owner")
        assert(math.sqrt(drone.position.x^2 + drone.position.y^2) <= 12, "wide work keeps companion near owner")
        check(storage.network_build.valid, false, "build from logistics provider")
        check(storage.provider.get_item_count("inserter"), 99, "only required network item taken")
        check(player.get_item_count("inserter"), 100, "network preferred over player")
        log("COMPANION logistics supply PASS")
        player.insert{name = "stone-furnace", count = 1}
        storage.concurrent = ghost("stone-furnace", {-8, 0})
        storage.blocker = assert(player.surface.create_entity{name = "steel-chest", position = {2, -6}, force = player.force})
        storage.blocked = ghost("transport-belt", {2, -6})
        drone.teleport({9, 0})
        storage.launch_position = {x = drone.position.x, y = drone.position.y - 2}
        drone.grid.put{name = "companion-defense-equipment"}
        storage.enemy = assert(player.surface.create_entity{name = "companion-combat-target", position = {10, 0}, force = "enemy"})
    elseif elapsed == 365 and settings.startup["set-mode"].value == 0 then
        local escorts = player.surface.find_entities_filtered{name = "companion-combat-robot"}
        check(#escorts, 4, "four-drone squad bypasses the vanilla follower limit")
        for _, robot in ipairs(escorts) do
            local a, b = robot.position, storage.launch_position
            assert((a.x - b.x)^2 + (a.y - b.y)^2 < 3^2, "mini drones launch from the companion")
        end
        check(player.force.maximum_following_robot_count, storage.follower_allowance, "vanilla follower allowance unchanged")
    elseif elapsed == 420 then
        check(storage.blocked.valid, true, "blocked ghost remains pending")
        check(storage.concurrent.valid, false, "blocked ghost does not monopolize available work")
        storage.blocker.destroy()
        if settings.startup["set-mode"].value == 0 then
            local escorts = player.surface.find_entities_filtered{name = "companion-combat-robot"}
            check(#escorts, 4, "two defense banks use only four stronger escorts")
            storage.escorts = escorts
            for _, robot in pairs(escorts) do check(robot.combat_robot_owner, player.character, "escort follows owner") end
            assert(not storage.enemy.valid or storage.enemy.get_health_ratio() < 1, "escorts damage nearby enemy")
            check(storage.concurrent.valid, false, "construction continues during combat")
            log("COMPANION independent combat and construction PASS")
        end
        if storage.enemy.valid then storage.enemy.destroy() end
        storage.far = ghost("transport-belt", {20, 0})
        player.teleport({80, 0})
    elseif elapsed == 550 then
        local distance = math.sqrt((drone.position.x - player.position.x)^2 + (drone.position.y - player.position.y)^2)
        assert(distance <= 12, "owner leash recalls drone")
        log("COMPANION owner leash PASS")
        local other = game.create_surface("companion-other", {width = 64, height = 64})
        other.request_to_generate_chunks({0, 0}, 1)
        other.force_generate_chunk_requests()
        player.teleport({0, 0}, other)
    elseif elapsed == 680 then
        check(drone.surface, player.surface, "surface change follows owner")
        log("COMPANION surface recall PASS")
    elseif elapsed == 700 then
        local surface = player.surface
        for _, entity in pairs(surface.find_entities_filtered{force = {"neutral", "enemy"}, area = {{-30, -30}, {30, 30}}}) do
            if entity.valid then entity.destroy() end
        end
        local tiles = {}
        for x = -30, 30 do for y = -30, 30 do tiles[#tiles + 1] = {name = "grass-1", position = {x, y}} end end
        surface.set_tiles(tiles)
        player.get_main_inventory().clear()
        player.insert{name = "stone", count = 150}
        storage.player_craft = ghost("stone-furnace", {6, 0}, nil, surface)
    elseif elapsed == 900 then
        check(storage.speed_checked, true, "crafting speed timing verified")
        check(storage.player_craft.valid, false, "drone independently crafts furnace from player materials")
        check(player.get_item_count("stone"), 145, "craft consumes exactly five stone")
        check(player.crafting_queue_size, 0, "player crafting queue remains untouched")
        log("COMPANION independent crafting from player materials PASS")
        local surface = player.surface
        local port = assert(surface.create_entity{name = "roboport", position = {0, 10}, force = player.force})
        port.energy = port.electric_buffer_size
        storage.craft_port = port
        local chest = assert(surface.create_entity{name = "requester-chest", position = {1, 10}, force = player.force})
        chest.insert{name = "iron-plate", count = 100}
        storage.craft_chest = chest
        player.get_main_inventory().clear()
        storage.recursive_craft = ghost("transport-belt", {8, 0}, nil, surface)
    elseif elapsed == 1140 then
        check(storage.recursive_craft.valid, false, "craft belt with intermediate gear from requester chest")
        check(storage.craft_chest.get_item_count("iron-plate"), 97, "recursive craft consumes exactly three iron")
        check(player.crafting_queue_size, 0, "recursive craft does not use player queue")
        for _, robot in pairs(storage.escorts or {}) do check(robot.valid, false, "single-use escort expired") end
        log("COMPANION network crafting and escort expiry PASS")
        storage.manager_ghosts, storage.observed_managers = {}, {}
        player.insert{name = "transport-belt", count = 48}
        for x = -24, 23 do storage.manager_ghosts[#storage.manager_ghosts + 1] = ghost("transport-belt", {x, -12}, nil, player.surface) end
    elseif elapsed == 1200 then
        for _, target in ipairs(storage.manager_ghosts) do check(target.valid, false, "manager batches construct all 48 exact targets") end
        local count = 0
        for _ in pairs(storage.observed_managers) do count = count + 1 end
        assert(count > 0 and count <= 6, "six or fewer managers own multiple construction tasks")
        log("COMPANION batched laser managers PASS")
        player.get_main_inventory().clear()
        drone.get_inventory(defines.inventory.spider_trunk).clear()
        storage.full_chest = assert(player.surface.create_entity{name = "steel-chest", position = {-10, 0}, force = player.force})
        check(storage.full_chest.insert{name = "iron-plate", count = 4800}, 4800, "full chest fixture")
        storage.full_chest.order_deconstruction(player.force, player)
        storage.second_full_chest = assert(player.surface.create_entity{name = "steel-chest", position = {-10, 3}, force = player.force})
        storage.second_full_chest.insert{name = "iron-plate", count = 4800}
        storage.second_full_chest.order_deconstruction(player.force, player)
    elseif elapsed == 1320 then
        check(storage.full_chest.valid, false, "full chest removed within two seconds")
        check(storage.second_full_chest.valid, false, "manager removes the second full chest in its batch")
    elseif elapsed == 1920 then
        check(storage.overflow_chest.valid, false, "overflow chest removed within two seconds")
    elseif elapsed == 1800 then
        check(storage.full_chest.valid, false, "full chest removal completes without cargo deadlock")
        check(player.get_item_count("iron-plate") + drone.get_item_count("iron-plate"), 9600, "both full chest inventories conserved without spills")
        drone.get_inventory(defines.inventory.spider_trunk).clear()
        local inventory = player.get_main_inventory()
        inventory.clear()
        for index = 1, #inventory do inventory[index].set_stack{name = "stone", count = 100} end
        storage.output_chest = assert(player.surface.create_entity{name = "storage-chest", position = {-2, 10}, force = player.force})
        storage.overflow_chest = assert(player.surface.create_entity{name = "steel-chest", position = {-10, -3}, force = player.force})
        storage.overflow_chest.insert{name = "iron-plate", count = 4800}
        storage.overflow_chest.order_deconstruction(player.force, player)
    elseif elapsed == 2400 then
        check(storage.overflow_chest.valid, false, "full player inventory uses logistics storage while removing a full chest")
        check(storage.output_chest.get_item_count("iron-plate") + drone.get_item_count("iron-plate"), 4800, "network salvage conserves all contents")
        player.get_main_inventory().clear()
        log("COMPANION full chest salvage and storage fallback PASS")
    elseif elapsed == 2500 then
        for _, chest in pairs(player.surface.find_entities_filtered{type = "logistic-container"}) do
            chest.get_inventory(defines.inventory.chest).clear()
        end
        player.get_main_inventory().clear()
        drone.get_inventory(defines.inventory.spider_trunk).clear()
        player.insert{name = "stone", count = 20}
        storage.batch_ghosts = {}
        for i = 1, 4 do storage.batch_ghosts[i] = ghost("stone-furnace", {i * 2 - 6, 4}, nil, player.surface) end
    elseif elapsed == 2540 then
        check(player.get_item_count("stone"), 0, "one batch reserves exact materials for four confirmed targets")
        local batch_overlay = false
        for _, object in pairs(rendering.get_all_objects("companion-drones-luan")) do
            if object.type == "text" and object.text == "×4" then batch_overlay = true end
        end
        assert(batch_overlay, "overhead crafting overlay shows the four-item batch")
        check(player.crafting_queue_size, 0, "batched drone crafting remains independent")
    elseif elapsed == 2900 then
        for _, target in ipairs(storage.batch_ghosts) do check(target.valid, false, "all batch targets constructed") end
        log("COMPANION batched crafting PASS")
        for _, chest in pairs(player.surface.find_entities_filtered{type = "logistic-container"}) do chest.get_inventory(defines.inventory.chest).clear() end
        player.get_main_inventory().clear()
        drone.get_inventory(defines.inventory.spider_trunk).clear()
        player.force.technologies["companion-crafting-speed-1"].level = 1
        player.insert{name = "stone", count = 70}
        storage.parallel_ghosts = {}
        for group = 1, 6 do
            for offset = 0, 1 do
                storage.parallel_ghosts[#storage.parallel_ghosts + 1] = ghost("stone-furnace", {group * 11 - 39 + offset * 2, 20}, nil, player.surface)
            end
        end
    elseif elapsed == 2940 then
        check(player.surface.count_entities_filtered{name = "companion-crafter"}, 6, "six independent crafters work in parallel")
        check(player.get_item_count("stone"), 10, "workers reserve exact separate ingredients")
        check(player.crafting_queue_size, 0, "parallel crafting leaves player queue free")
        storage.landed_crafters = {}
        for _, crafter in pairs(player.surface.find_entities_filtered{name = "companion-crafter"}) do
            storage.landed_crafters[crafter.unit_number] = {entity = crafter, position = crafter.position}
        end
        player.teleport({6, 0})
        player.force.technologies["companion-crafting-speed-1"].level = 2
        for offset = 0, 1 do
            storage.parallel_ghosts[#storage.parallel_ghosts + 1] = ghost("stone-furnace", {offset * 2, -28}, nil, player.surface)
        end
    elseif elapsed == 2980 then
        check(player.surface.count_entities_filtered{name = "companion-crafter"}, 7, "research unlocks a seventh parallel crafter")
        for _, landed in pairs(storage.landed_crafters) do
            check(landed.entity.position.x, landed.position.x, "landed crafter stays fixed while owner walks")
            check(landed.entity.position.y, landed.position.y, "landed crafter stays fixed while owner walks")
        end
        check(player.get_item_count("stone"), 0, "new crafter reserves only its ten stone")
        check(player.surface.count_entities_filtered{name = "companion"}, 1, "worker deployment keeps the permanent companion")
    elseif elapsed == 3500 then
        for _, target in ipairs(storage.parallel_ghosts) do check(target.valid, false, "parallel crafted targets constructed") end
        check(player.surface.count_entities_filtered{name = "companion-crafter"}, 0, "crafters disappear after delivery")
        check(player.surface.count_entities_filtered{name = "companion-task-manager"}, 0, "task managers disappear after delivery")
        log("COMPANION parallel crafters, research capacity and manager returns PASS")
        player.insert{name = "repair-pack", count = 2}
        player.insert{name = "fast-transport-belt", count = 1}
        player.insert{name = "speed-module", count = 1}
        storage.repair_target = assert(player.surface.create_entity{name = "car", position = {-5, 12}, force = player.force})
        storage.repair_target.health = storage.repair_target.max_health - 225
        storage.second_repair = assert(player.surface.create_entity{name = "car", position = {-9, 12}, force = player.force})
        storage.second_repair.health = storage.second_repair.max_health - 225
        storage.repair_durability = player.get_main_inventory().find_item_stack("repair-pack").durability
        storage.upgrade_target = assert(player.surface.create_entity{name = "transport-belt", position = {5, 12}, force = player.force})
        storage.upgrade_target.order_upgrade{force = player.force, target = "fast-transport-belt"}
        storage.delivery_target = assert(player.surface.create_entity{name = "assembling-machine-2", position = {12, 12}, force = player.force})
        storage.delivery_proxy = assert(player.surface.create_entity{name = "item-request-proxy", position = {12, 12},
            force = player.force, target = storage.delivery_target,
            modules = {{id = {name = "speed-module", quality = "normal"},
                items = {in_inventory = {{inventory = defines.inventory.crafter_modules, stack = 0, count = 1}}}}}})
    elseif elapsed == 3580 then
        check(storage.repair_target.health, storage.repair_target.max_health, "task manager repairs exact target")
        check(storage.second_repair.health, storage.second_repair.max_health, "batched repair handles a pack durability boundary")
        check(storage.upgrade_target.valid, false, "task manager fast-replaces upgrade")
        check(#player.surface.find_entities_filtered{name = "fast-transport-belt", position = {5, 12}, radius = 1} == 1, true, "upgraded belt present")
        check(storage.delivery_target.get_module_inventory().get_item_count("speed-module"), 1, "request delivered to specified module slot")
        check(player.get_item_count("fast-transport-belt"), 0, "one upgrade item consumed")
        check(player.get_item_count("transport-belt") + drone.get_item_count("transport-belt"), 1, "old upgrade item returned")
        local pack = player.get_main_inventory().find_item_stack("repair-pack") or drone.get_inventory(defines.inventory.spider_trunk).find_item_stack("repair-pack")
        assert(pack and pack.count == 1 and pack.durability == storage.repair_durability * 2 - 450, "unused repair durability returned")
        check(player.surface.count_entities_filtered{name = "companion-task-manager"}, 0, "completed operation managers disappear")
        log("COMPANION exact repair, upgrade and module delivery PASS")
        for _, inventory in ipairs{player.get_main_inventory(), drone.get_inventory(defines.inventory.spider_trunk)} do
            inventory.clear()
            for slot = 1, math.min(#inventory, inventory == drone.get_inventory(defines.inventory.spider_trunk) and 20 or #inventory) do
                inventory[slot].set_stack{name = "stone", count = 100}
            end
        end
        for _, chest in pairs(player.surface.find_entities_filtered{type = "logistic-container"}) do
            local inventory = chest.get_inventory(defines.inventory.chest)
            inventory.clear()
            for slot = 1, #inventory do inventory[slot].set_stack{name = "stone", count = 100} end
        end
        storage.blocked_return_chest = assert(player.surface.create_entity{name = "steel-chest", position = {-12, 12}, force = player.force})
        storage.blocked_return_chest.insert{name = "iron-plate", count = 10}
        storage.blocked_return_chest.order_deconstruction(player.force)
    elseif elapsed == 3640 then
        check(storage.blocked_return_chest.valid, false, "full return inventories do not prevent exact chest removal")
        check(player.surface.count_entities_filtered{name = "companion-task-manager"}, 1, "manager retains cargo until it can be delivered")
    elseif elapsed == 3700 then
        player.get_main_inventory().clear()
        drone.get_inventory(defines.inventory.spider_trunk).clear()
    elseif elapsed == 3780 then
        check(player.get_item_count("iron-plate") + drone.get_item_count("iron-plate"), 10, "blocked manager returns every salvaged item")
        check(player.surface.count_entities_filtered{name = "companion-task-manager"}, 0, "manager disappears only after cargo delivery")
        log("COMPANION blocked return cargo conservation PASS")
    elseif elapsed == 3790 then
        player.get_main_inventory().clear()
        drone.get_inventory(defines.inventory.spider_trunk).clear()
        for _, chest in pairs(player.surface.find_entities_filtered{type = "logistic-container"}) do chest.get_inventory(defines.inventory.chest).clear() end
        player.insert{name = "stone", count = 5}
        storage.toggle_craft = ghost("stone-furnace", {8, 25}, nil, player.surface)
    elseif elapsed == 3810 then
        check(player.surface.count_entities_filtered{name = "companion-crafter"}, 1, "craft starts before construction is disabled")
        player.set_shortcut_toggled("companion-construction-toggle", false)
    elseif elapsed == 3830 then
        check(storage.toggle_craft.valid, true, "disabled construction does not finish reserved craft")
        check(player.surface.count_entities_filtered{name = "companion-crafter"}, 0, "disabled construction recalls active crafters")
        check(player.get_item_count("stone") + drone.get_item_count("stone"), 5, "disabled craft refunds ingredients")
        storage.toggle_craft.destroy()
        player.set_shortcut_toggled("companion-construction-toggle", true)
        player.insert{name = "stone", count = 5}
        storage.force_craft = ghost("stone-furnace", {8, 25}, nil, player.surface)
    elseif elapsed == 3850 then
        check(player.surface.count_entities_filtered{name = "companion-crafter"}, 1, "craft starts before force change")
        storage.original_force = player.force
        player.force = game.create_force("companion-owner-force-test")
    elseif elapsed == 3890 then
        check(storage.force_craft.valid, true, "crew abandons previous-force target")
        check(player.surface.count_entities_filtered{name = "companion-crafter"}, 0, "force change recalls active crafters")
        check(drone.force, player.force, "permanent companion follows owner force")
        check(player.get_item_count("stone") + drone.get_item_count("stone"), 10, "force change preserves crafting ingredients")
        storage.force_craft.destroy()
        player.force = storage.original_force
        log("COMPANION construction toggle and force-change conservation PASS")
    elseif elapsed == 3900 then
        if not script.active_mods["space-age"] then
            storage.identity = drone.unit_number
            player.character.destructible = true
            player.character.die()
            return
        end
        for _, name in ipairs{"vulcanus", "fulgora", "gleba", "aquilo", "companion-test-planet"} do
            assert(player.force.technologies["companion-planet-" .. name], "research generated for " .. name)
        end
        check(player.force.technologies["companion-planet-nauvis"], nil, "no Nauvis expansion research")
        player.force.technologies["companion-planet-vulcanus"].researched = true
        player.force.technologies["companion-planet-companion-test-planet"].researched = true
    elseif elapsed == 4020 then
        check(#player.surface.find_entities_filtered{name = "companion"}, 2, "two planet researches grant one extra drone")
        player.force.technologies["companion-promethium-1"].level = 3
    elseif elapsed == 4140 then
        check(#player.surface.find_entities_filtered{name = "companion"}, 4, "two promethium levels grant two extras")
        storage.fleet = player.surface.find_entities_filtered{name = "companion"}
        local platform = assert(player.force.create_space_platform{
            name = "Companion test platform", planet = "nauvis", starter_pack = "space-platform-starter-pack"})
        platform.apply_starter_pack()
        storage.platform = platform
        storage.previous_surface = player.surface
        local tiles = {}
        for x = -5, 15 do for y = -5, 5 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
        platform.surface.set_tiles(tiles)
        assert(player.teleport({0, 4}, platform.surface))
        player.insert{name = "transport-belt", count = 10}
        storage.platform_ghost = ghost("transport-belt", {10, 4}, nil, platform.surface)
    elseif elapsed == 4260 then
        check(#storage.platform.surface.find_entities_filtered{name = "companion"}, 0, "no companions active on platform")
        check(storage.platform_ghost.valid, true, "platform work remains untouched")
        for _, companion in ipairs(storage.fleet) do check(companion.surface, storage.previous_surface, "fleet parked on previous planet") end
        log("COMPANION planet, promethium, and platform suspension PASS")
        local surface = game.planets["companion-test-planet"].create_surface()
        surface.request_to_generate_chunks({0, 0}, 1)
        surface.force_generate_chunk_requests()
        surface.set_tiles{{name = "grass-1", position = {0, 0}}}
        assert(player.teleport({0, 0}, surface))
    elseif elapsed == 4380 then
        for _, companion in ipairs(storage.fleet) do
            check(companion.valid, true, "fleet remains present")
            check(companion.surface, player.surface, "same fleet travels to modded planet")
        end
        storage.identity = drone.unit_number
        player.character.destructible = true
        player.character.die()
    end
end)
