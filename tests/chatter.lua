local function capture(player, label)
    game.take_screenshot{player = player, position = {2, 0}, resolution = {1280, 720}, zoom = 1.5,
        path = "chatter/" .. label .. ".png", show_gui = false, daytime = 0, force_render = true}
end

script.on_init(function()
    game.speed = 20
    game.surfaces[1].request_to_generate_chunks({0, 0}, 2)
    game.surfaces[1].force_generate_chunk_requests()
end)

script.on_event(defines.events.on_string_translated, function(event)
    if storage.pool and event.localised_string[1] == storage.pool .. ".0" then
        assert(event.translated, "dialogue count is localized")
        storage.dialogue_count = assert(tonumber(event.result))
    end
end)

script.on_event(defines.events.on_tick, function(event)
    local player = game.get_player(1)
    if not player then return end
    if not storage.started then
        if not player.character then player.create_character() end
        local drone = player.surface.find_entities_filtered{name = "companion"}[1]
        if not drone then return end
        player.teleport({0, 2})
        player.character.destructible = false
        player.surface.always_day = true
        for _, entity in pairs(player.surface.find_entities_filtered{area = {{-30, -20}, {30, 20}}, force = {"neutral", "enemy"}}) do
            if entity.valid and entity.type ~= "resource" then entity.destroy() end
        end
        local tiles = {}
        for x = -30, 30 do for y = -20, 20 do tiles[#tiles + 1] = {name = "grass-1", position = {x, y}} end end
        player.surface.set_tiles(tiles)
        drone.teleport({2, 0})
        drone.grid.clear()
        drone.grid.put{name = "companion-roboport-mk3"}
        player.set_shortcut_toggled("companion-construction-toggle", true)
        player.get_main_inventory().clear()
        local pools = {deadpan = "idle-line", unhinged = "idle-line-unhinged", roast = "idle-line-roast", sitcom = "idle-line-sitcom", scifi = "idle-line-scifi"}
        storage.pool = assert(pools[settings.get_player_settings(player)["companion-humor-style"].value])
        player.request_translation({storage.pool .. ".0"})
        storage.drone, storage.started = drone, event.tick
    end
    local elapsed = event.tick - storage.started
    storage.observed = storage.observed or {}
    storage.spoken = storage.spoken or {}
    local visible = 0
    for _, object in pairs(rendering.get_all_objects("companion-drones-luan")) do
        local text = object.type == "text" and object.text
        if type(text) == "table" and type(text[1]) == "string" and text[1]:match("^idle%-line[^%.]*%.") then
            visible = visible + 1
            assert(text[1]:sub(1, #storage.pool + 1) == storage.pool .. ".", "only the selected humor style speaks")
            assert(settings.startup["companion-voice-lines"].value, "disabled chatter creates no speech")
            assert(object.visible and #object.players == 1 and object.players[1] == player, "speech is visible only to its owner")
            assert(object.target.entity == storage.drone, "speech follows its companion")
            if not storage.observed[object.id] then
                storage.observed[object.id] = text[1]
                assert(not (elapsed >= 650 and elapsed < 1210), "working crew does not start idle chatter")
                assert(not (elapsed >= 1830 and elapsed < 2410), "unavailable owner does not start idle chatter")
                local phase = elapsed < 610 and "idle" or elapsed >= 1230 and elapsed < 1810 and "resumed"
                    or elapsed >= 2430 and "returned"
                if phase and not storage.spoken[phase] then
                    storage.spoken[phase] = true
                    capture(player, phase .. "-spoken")
                end
            end
        end
    end
    assert(visible <= 1, "new quips replace the previous line instead of overlapping")
    if elapsed >= 900 and elapsed < 1210 or elapsed >= 2200 and elapsed < 2410 then
        assert(visible == 0, "speech expires while busy or unavailable")
    end
    if elapsed == 300 or elapsed == 450 or elapsed == 600 then
        capture(player, "idle-" .. elapsed)
    elseif elapsed == 610 then
        player.insert{name = "stone", count = 5}
        storage.target = assert(player.surface.create_entity{name = "entity-ghost", inner_name = "stone-furnace",
            position = {8, 0}, force = player.force})
    elseif elapsed == 900 or elapsed == 1200 then
        assert(player.surface.count_entities_filtered{name = "companion-crafter"} == 1, "a long craft is active")
        capture(player, "working-" .. elapsed)
    elseif elapsed == 1210 then
        player.set_shortcut_toggled("companion-construction-toggle", false)
        storage.target.destroy()
    elseif elapsed == 1500 or elapsed == 1650 or elapsed == 1800 then
        assert(player.surface.count_entities_filtered{name = "companion-crafter"} == 0, "canceled crafter returned")
        assert(player.get_item_count("stone") + storage.drone.get_item_count("stone") == 5, "cancellation refunds ingredients")
        capture(player, "resumed-" .. elapsed)
    elseif elapsed == 1810 then
        storage.character = player.character
        player.set_controller{type = defines.controllers.spectator}
    elseif elapsed == 2200 or elapsed == 2400 then
        assert(not player.character, "owner has no physical character")
        capture(player, "unavailable-" .. elapsed)
    elseif elapsed == 2410 then
        player.set_controller{type = defines.controllers.character, character = storage.character}
    elseif elapsed == 2700 or elapsed == 2850 or elapsed == 3000 then
        capture(player, "returned-" .. elapsed)
    elseif elapsed == 3010 then
        assert(storage.dialogue_count and storage.dialogue_count > 0, "locale declares its dialogue count")
        for _, key in pairs(storage.observed) do
            local index = tonumber(key:match("%.(%d+)$"))
            assert(index and index >= 1 and index <= storage.dialogue_count, "speech selects an existing dialogue line")
        end
        if settings.startup["companion-voice-lines"].value then
            assert(storage.spoken.idle and storage.spoken.resumed and storage.spoken.returned,
                "idle chatter starts and resumes after work and owner absence")
        else
            assert(not next(storage.observed), "chatter toggle suppresses every line")
        end
        game.set_wait_for_screenshots_to_finish()
        log("COMPANION humor style " .. storage.pool .. ", idle chatter, work and owner pauses, privacy, expiry and toggle PASS")
        log("COMPANION INTEGRATION PASS")
        script.on_event(defines.events.on_tick, nil)
    end
end)
