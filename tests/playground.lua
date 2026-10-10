local function flatten(surface)
    if storage.prepared and storage.prepared[surface.index] then return end
    storage.prepared = storage.prepared or {}
    surface.request_to_generate_chunks({0, 0}, 2)
    surface.force_generate_chunk_requests()
    for _, entity in pairs(surface.find_entities_filtered{area = {{-64, -64}, {64, 64}}, force = {"neutral", "enemy"}}) do
        if entity.valid then entity.destroy() end
    end
    local tiles = {}
    for x = -64, 63 do for y = -64, 63 do tiles[#tiles + 1] = {name = "grass-1", position = {x, y}} end end
    surface.set_tiles(tiles)
    surface.always_day = true
    storage.prepared[surface.index] = true
end

local function ghost(player, name, x, y)
    return player.physical_surface.create_entity{name = "entity-ghost", inner_name = name,
        position = {x, y}, force = player.force}
end

local function build_test(player, crafting)
    if player.physical_surface.platform then return end
    local p = player.physical_position
    if crafting then
        ghost(player, "stone-furnace", p.x + 5, p.y + 4)
        ghost(player, "small-lamp", p.x + 7, p.y + 4)
        ghost(player, "assembling-machine-1", p.x + 11, p.y + 4)
    else
        for x = 5, 11 do ghost(player, "transport-belt", p.x + x, p.y) end
        ghost(player, "inserter", p.x + 5, p.y - 4)
        ghost(player, "assembling-machine-3", p.x - 6, p.y)
    end
end

local function panel(player)
    if player.gui.left.companion_playground then player.gui.left.companion_playground.destroy() end
    local frame = player.gui.left.add{type = "frame", name = "companion_playground", caption = "Companion playground", direction = "vertical"}
    local label = frame.add{type = "label", caption = settings.startup["companion-work-radius"].value .. "-tile work radius · cyan work / red combat"}
    label.style.single_line = false
    local actions = {
        {"mixed", "Mixed workload: 180+ tasks"}, {"starve", "Empty raw supplies"}, {"clear", "Clear workload"},
        {"radius", "Show / hide work radius"},
        {"build", "Build + impossible task"}, {"craft", "Autocraft from chests"}, {"attack", "Spawn 4 small biters"},
        {"repair", "Repair + deconstruct"}, {"salvage", "Remove full chest: 4,800 items"}, {"overflow", "Full inventory + storage salvage"}, {"leash", "Move 50 tiles away"}, {"home", "Return to test area"},
        {"speed", "Research crafting speed +1"}, {"planets", "Research next 2 planets"},
        {"promethium", "Research extra drone +1"}, {"vulcanus", "Travel to Vulcanus"},
        {"platform", "Travel to platform"}, {"refill", "Refill test supplies"},
    }
    for _, action in ipairs(actions) do frame.add{type = "button", name = "playground_" .. action[1], caption = action[2]} end
end

local function refill(player)
    local surface = game.surfaces.nauvis
    for _, fixture in ipairs{
        {"port", "roboport", {0, 14}}, {"raw_chest", "requester-chest", {4, 14}},
        {"finished_chest", "passive-provider-chest", {-4, 14}},
    } do
        local entity = storage[fixture[1]]
        if not entity or not entity.valid then
            storage[fixture[1]] = surface.find_entities_filtered{name = fixture[2], position = fixture[3], radius = 1}[1]
                or surface.create_entity{name = fixture[2], position = fixture[3], force = player.force}
        end
    end
    local items = {coal = 100, ["transport-belt"] = 100, inserter = 20, ["fast-transport-belt"] = 20,
        ["repair-pack"] = 20, ["iron-plate"] = 20, ["copper-plate"] = 20, stone = 20, wood = 20,
        ["submachine-gun"] = 1, ["firearm-magazine"] = 100, ["deconstruction-planner"] = 1,
        ["upgrade-planner"] = 1}
    for name, count in pairs(items) do
        local have = player.get_item_count(name)
        if have < count then player.insert{name = name, count = count - have} end
    end
    for _, chest in ipairs{storage.raw_chest, storage.finished_chest} do
        if chest and chest.valid then chest.get_inventory(defines.inventory.chest).clear() end
    end
    if storage.raw_chest and storage.raw_chest.valid then
        for _, name in ipairs{"iron-plate", "copper-plate", "stone", "steel-plate"} do storage.raw_chest.insert{name = name, count = 500} end
    end
    if storage.finished_chest and storage.finished_chest.valid then
        storage.finished_chest.insert{name = "transport-belt", count = 100}
        storage.finished_chest.insert{name = "inserter", count = 100}
    end
end

script.on_init(function()
    game.speed = 1
    flatten(game.surfaces.nauvis)
    game.forces.player.enable_all_recipes()
    game.forces.player.chart(game.surfaces.nauvis, {{-64, -64}, {64, 64}})
end)

local function mixed_workload(player)
    if player.physical_surface.platform then return end
    player.teleport({0, 0}, game.surfaces.nauvis)
    local surface = player.physical_surface
    for y = -12, -6, 2 do for x = -36, 36, 2 do ghost(player, "transport-belt", x, y) end end
    for x = -24, 24, 6 do ghost(player, "assembling-machine-2", x, 20) end
    for x = -21, 21, 3 do ghost(player, "small-lamp", x, 16) end
    local obstruction = surface.create_entity{name = "steel-chest", position = {-2, 4}, force = player.force}
    ghost(player, "transport-belt", -2, 4)
    ghost(player, "assembling-machine-3", -7, 4)
    for x = -20, 20, 4 do
        local belt = surface.create_entity{name = "transport-belt", position = {x, -20}, force = player.force}
        if belt then belt.order_upgrade{target = "fast-transport-belt", force = player.force, player = player} end
    end
    for i = 1, 4 do
        local car = surface.create_entity{name = "car", position = {5 + i * 4, 6}, force = player.force}
        if car then car.health = car.health * 0.25 end
        local chest = surface.create_entity{name = "steel-chest", position = {-10 - i * 3, 6}, force = player.force}
        if chest then chest.insert{name = "iron-plate", count = 10}; chest.order_deconstruction(player.force, player) end
    end
    for i = 1, 6 do surface.create_entity{name = "small-biter", position = {10 + i, -28}, force = "enemy"} end
    storage.wave_tick = game.tick + 300
    player.zoom = 0.4
end

script.on_event(defines.events.on_tick, function(event)
    if storage.port and storage.port.valid then storage.port.energy = storage.port.electric_buffer_size end
    local player = game.get_player(1)
    if player and storage.wave_tick and event.tick == storage.wave_tick then
        local pos = player.physical_position
        for i = 1, 8 do player.physical_surface.create_entity{name = "medium-biter", position = {pos.x + 14 + i, pos.y - 8}, force = "enemy"} end
        storage.wave_tick = nil
    end
    if player and not storage.started then
        if not player.character then player.create_character() end
        player.teleport({0, 0}, game.surfaces.nauvis)
        player.character.destructible = false
        player.get_main_inventory().clear()
        player.insert{name = "power-armor-mk2", count = 1}
        local armor = player.get_inventory(defines.inventory.character_armor)[1]
        if armor.valid_for_read and armor.grid then
            armor.grid.put{name = "fission-reactor-equipment"}
            armor.grid.put{name = "exoskeleton-equipment"}
            armor.grid.put{name = "night-vision-equipment"}
        end
        storage.port = player.surface.create_entity{name = "roboport", position = {0, 14}, force = player.force}
        storage.raw_chest = player.surface.create_entity{name = "requester-chest", position = {4, 14}, force = player.force}
        storage.finished_chest = player.surface.create_entity{name = "passive-provider-chest", position = {-4, 14}, force = player.force}
        for _, entry in ipairs{{"Raw crafting materials", {4, 12}}, {"Finished build items", {-4, 12}}} do
            rendering.draw_text{text = entry[1], surface = player.surface, target = entry[2], color = {1, 1, 1}, alignment = "center", scale = 0.9}
        end
        refill(player)
        panel(player)
        player.zoom = 0.65
        storage.started = event.tick
        log("COMPANION PLAYGROUND READY")
    elseif storage.started and event.tick == storage.started + 120 then
        mixed_workload(player)
        game.auto_save("companion-playground")
    end
end)

local function clear_workload(player)
    game.speed = 1
    storage.wave_tick = nil
    for _, entity in pairs(player.physical_surface.find_entities_filtered{area = {{-45, -35}, {45, 35}}}) do
        if entity.valid and entity ~= player.character and entity.name ~= "companion"
            and entity ~= storage.port and entity ~= storage.raw_chest and entity ~= storage.finished_chest
            and entity.force.name ~= "neutral" then entity.destroy() end
    end
end

script.on_event(defines.events.on_gui_click, function(event)
    local player = game.get_player(event.player_index)
    local name = event.element.valid and event.element.name or ""
    local pos = player.physical_position
    if name == "playground_mixed" then mixed_workload(player)
    elseif name == "playground_starve" then
        if storage.raw_chest and storage.raw_chest.valid then storage.raw_chest.get_inventory(defines.inventory.chest).clear() end
        for _, item in ipairs{"iron-plate", "copper-plate", "stone", "steel-plate"} do player.remove_item{name = item, count = 1000000} end
    elseif name == "playground_clear" then
        clear_workload(player)
    elseif name == "playground_radius" then
        if storage.radius and storage.radius.valid then storage.radius.destroy(); storage.radius = nil
        else storage.radius = rendering.draw_circle{surface = player.physical_surface, target = player.character,
            radius = settings.startup["companion-work-radius"].value, filled = false, width = 2, color = {0.1, 0.8, 1, 0.6}} end
    elseif name == "playground_build" then build_test(player, false)
    elseif name == "playground_craft" then build_test(player, true)
    elseif name == "playground_attack" then
        for i = 1, 4 do player.physical_surface.create_entity{name = "small-biter", position = {pos.x + 12 + i, pos.y - 9}, force = "enemy"} end
    elseif name == "playground_repair" then
        if player.physical_surface.platform then return end
        local car = player.physical_surface.create_entity{name = "car", position = {pos.x - 5, pos.y + 6}, force = player.force}
        if car then car.health = car.health / 2 end
        local chest = player.physical_surface.create_entity{name = "steel-chest", position = {pos.x - 5, pos.y - 4}, force = player.force}
        if chest then chest.insert{name = "iron-plate", count = 10}; chest.order_deconstruction(player.force) end
    elseif name == "playground_salvage" or name == "playground_overflow" then
        if player.physical_surface.platform then return end
        if name == "playground_overflow" then
            local inventory = player.get_main_inventory()
            for index = 1, #inventory do
                if not inventory[index].valid_for_read then inventory[index].set_stack{name = "stone", count = 100} end
            end
            player.physical_surface.create_entity{name = "storage-chest", position = {pos.x - 4, pos.y + 10}, force = player.force}
        end
        local chest = player.physical_surface.create_entity{name = "steel-chest", position = {pos.x - 8, pos.y + 4}, force = player.force}
        if chest then chest.insert{name = "iron-plate", count = 4800}; chest.order_deconstruction(player.force, player) end
    elseif name == "playground_leash" then player.teleport({-50, 0}, player.physical_surface)
    elseif name == "playground_home" then player.teleport({0, 0}, game.surfaces.nauvis)
    elseif name == "playground_speed" then
        local tech = player.force.technologies["companion-crafting-speed-1"]
        tech.level = tech.level + 1
    elseif name == "playground_planets" then
        local names = {}
        for name, tech in pairs(player.force.technologies) do
            if name:sub(1, #"companion-planet-") == "companion-planet-" and not tech.researched then names[#names + 1] = name end
        end
        table.sort(names)
        for i = 1, math.min(2, #names) do player.force.technologies[names[i]].researched = true end
    elseif name == "playground_promethium" then
        local tech = player.force.technologies["companion-promethium-1"]
        tech.level = tech.level + 1
    elseif name == "playground_vulcanus" then
        local surface = game.planets.vulcanus.create_surface()
        flatten(surface)
        player.force.chart(surface, {{-64, -64}, {64, 64}})
        player.teleport({0, 0}, surface)
    elseif name == "playground_platform" then
        if not storage.platform then
            storage.platform = player.force.create_space_platform{name = "Companion playground", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
            storage.platform.apply_starter_pack(true)
            local tiles = {}
            for x = -16, 16 do for y = -16, 16 do tiles[#tiles + 1] = {name = "space-platform-foundation", position = {x, y}} end end
            storage.platform.surface.set_tiles(tiles)
        end
        player.teleport({0, 5}, storage.platform.surface)
        ghost(player, "transport-belt", 8, 5)
    elseif name == "playground_refill" then refill(player)
    end
end)

-- Manual QA invokes the same fixture used by the visible button.
remote.add_interface("companion_playground", {
    mixed = function() game.speed = 1; mixed_workload(game.get_player(1)) end,
    clear = function() clear_workload(game.get_player(1)) end,
    visual = function()
        local player = game.get_player(1)
        local pos = player.physical_position
        for i = 1, 8 do ghost(player, "assembling-machine-2", pos.x + i * 4, pos.y + 6) end
        for i = 1, 8 do
            local enemy = player.physical_surface.create_entity{name = "big-biter", position = {pos.x + 12 + i, pos.y - 5}, force = "enemy"}
            if enemy and enemy.commandable then enemy.commandable.set_command{type = defines.command.attack, target = player.character, distraction = defines.distraction.none} end
        end
        player.zoom = 1.3
    end,
})
