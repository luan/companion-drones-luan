-- Thousands of unavailable tile jobs must not block unrelated work or later delivery.
script.on_init(function()
    game.speed = 1000
    game.surfaces[1].request_to_generate_chunks({0,0},2)
    game.surfaces[1].force_generate_chunk_requests()
end)

script.on_event(defines.events.on_tick, function(event)
    local player = game.get_player(1)
    if not player then return end
    if not player.character then player.create_character() end
    if not storage.started then
        player.character.destructible = false
        player.teleport({0,0})
        player.set_shortcut_toggled("companion-construction-toggle",false)
        local tiles = {}
        for x=-40,39 do for y=-40,39 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
        player.surface.set_tiles(tiles)
        for _,e in pairs(player.surface.find_entities_filtered{area={{-40,-40},{40,40}},force={"neutral","enemy"}}) do
            if e.valid and e.type ~= "resource" then e.destroy() end
        end
        player.get_main_inventory().clear()
        storage.tiles = {}
        for x=-40,39 do for y=-40,39 do
            local name=(x+y)%2==0 and "concrete" or "refined-concrete"
            storage.tiles[#storage.tiles+1]=assert(player.surface.create_entity{
                name="tile-ghost",inner_name=name,position={x,y},force=player.force})
        end end
        player.insert{name="transport-belt",count=1}
        storage.belt=assert(player.surface.create_entity{name="entity-ghost",inner_name="transport-belt",position={3,3},force=player.force})
        storage.started=event.tick
        game.auto_save("concrete-stress")
        log("COMPANION 6400 concrete ghosts prepared")
    end
    local elapsed=event.tick-storage.started
    if elapsed==1 then player.set_shortcut_toggled("companion-construction-toggle",true)
    elseif elapsed==180 then
        assert(not storage.belt.valid,"unavailable concrete does not block supplied entity construction")
        assert(#player.surface.find_entities_filtered{type="tile-ghost"}==6400,"unavailable concrete remains pending")
        player.insert{name="concrete",count=192}
    elseif elapsed==480 then
        local remaining=#player.surface.find_entities_filtered{type="tile-ghost"}
        assert(remaining<6400,"tile managers use concrete supplied after the large paste")
        assert(#player.surface.find_entities_filtered{name="companion-task-manager"}<=6,"bounded manager deployment")
        log("COMPANION concrete stress construction and material retry PASS; tiles built=" .. (6400-remaining))
        log("COMPANION INTEGRATION PASS")
        script.on_event(defines.events.on_tick,nil)
    end
end)
