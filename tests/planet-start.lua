-- Run alongside actual freeplay and Any Planet Start, including their spawn handlers.
script.on_init(function()
    game.speed = 1000
    remote.call("APS", "set_disable_crashsite", true)
    remote.call("APS", "set_skip_intro", true)
    remote.call("freeplay", "set_skip_intro", true)
    remote.call("freeplay", "set_disable_crashsite", true)
end)

script.on_event(defines.events.on_tick, function(event)
    local player = game.get_player(1)
    if not player then return end
    if not player.character then
        if player.ticks_to_respawn then player.ticks_to_respawn = nil end
        return
    end
    local home = settings.startup["aps-planet"].value
    if not storage.started then
        assert(player.physical_surface.name == home, "APS places the player on selected planet")
        local drones = player.physical_surface.find_entities_filtered{name = "companion", force = player.force}
        assert(#drones == 1, "one companion on starting planet")
        storage.drone, storage.identity = drones[1], drones[1].unit_number
        storage.started = event.tick
        player.character.destructible = false
        local origin = player.physical_position
        for _, entity in pairs(player.surface.find_entities_filtered{area = {{origin.x-8, origin.y-8}, {origin.x+8, origin.y+8}}, force = {"neutral", "enemy"}}) do
            if entity.valid and entity.type ~= "resource" then entity.destroy() end
        end
        local tiles = {}
        for x = -8, 8 do for y = -8, 8 do tiles[#tiles+1] = {name = "grass-1", position = {origin.x+x, origin.y+y}} end end
        player.surface.set_tiles(tiles)
        player.insert{name = "transport-belt", count = 1}
        storage.ghost = assert(player.surface.create_entity{name = "entity-ghost", inner_name = "transport-belt", position = {origin.x+3, origin.y+3}, force = player.force})
        player.insert{name = "stone", count = 5}
        storage.craft_ghost = assert(player.surface.create_entity{name = "entity-ghost", inner_name = "stone-furnace",
            position = {origin.x-3, origin.y+3}, force = player.force})
        local tech = assert(player.force.technologies["companion-planet-" .. home], "starting planet upgrade exists")
        for _, prerequisite in pairs(tech.prerequisites) do
            assert(prerequisite.valid and not prerequisite.prototype.hidden, "no hidden discovery prerequisite: " .. prerequisite.name)
        end
        log("COMPANION APS " .. home .. " spawn PASS")
    end
    local elapsed = event.tick - storage.started
    if elapsed == 180 then
        assert(not storage.ghost.valid, "companion builds on starting planet")
        assert(storage.drone.valid and storage.drone.unit_number == storage.identity, "starter identity persists")
        player.character.destructible = true
        player.character.die()
        player.ticks_to_respawn = nil
        game.reset_game_state()
        log("COMPANION APS death and respawn requested")
    elseif elapsed == 240 then
        assert(player.physical_surface.name == home, "respawn returns to APS starting planet")
        assert(storage.drone.valid and storage.drone.surface == player.physical_surface, "same companion follows respawn")
        local other = home == "vulcanus" and "fulgora" or "vulcanus"
        local surface = game.planets[other].create_surface()
        surface.request_to_generate_chunks({0,0},1)
        surface.force_generate_chunk_requests()
        player.teleport({0,0},surface)
    elseif elapsed == 300 then
        assert(storage.drone.valid and storage.drone.surface == player.physical_surface, "same companion follows planet travel")
        assert(storage.drone.unit_number == storage.identity, "planet travel preserves identity")
        local surface = game.planets[home].create_surface()
        player.teleport(player.force.get_spawn_position(surface),surface)
    elseif elapsed == 360 then
        assert(storage.drone.surface == player.physical_surface and player.physical_surface.name == home, "returns to starting planet")
        assert(not storage.craft_ghost.valid, "autocrafting completes on starting planet")
        assert(player.crafting_queue_size == 0, "drone crafts independently of player queue")
        log("COMPANION APS " .. home .. " construction, respawn and travel PASS")
        log("COMPANION INTEGRATION PASS")
        script.on_event(defines.events.on_tick,nil)
    end
end)
