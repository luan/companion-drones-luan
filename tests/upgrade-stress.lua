-- Unavailable upgrades must not block other jobs; supplying target items later must resume upgrades.
script.on_init(function()
    game.speed=1000
    game.surfaces[1].request_to_generate_chunks({0,0},2)
    game.surfaces[1].force_generate_chunk_requests()
end)
script.on_event(defines.events.on_tick,function(event)
    local player=game.get_player(1)
    if not player then return end
    if not player.character then player.create_character() end
    if not storage.started then
        player.character.destructible=false
        player.teleport({0,0})
        player.set_shortcut_toggled("companion-construction-toggle",false)
        local surface=player.surface
        for _,entity in pairs(surface.find_entities_filtered{area={{-40,-40},{40,40}},force={"neutral","enemy"}}) do
            if entity.valid and entity.type~="resource" then entity.destroy() end
        end
        local tiles={}
        for x=-40,40 do for y=-40,40 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
        surface.set_tiles(tiles)
        for x=-32,31 do for y=-32,31 do
            local belt=assert(surface.create_entity{name="transport-belt",position={x,y},force=player.force})
            assert(belt.order_upgrade{force=player.force,target="fast-transport-belt"})
        end end
        player.get_main_inventory().clear()
        player.force.recipes["fast-transport-belt"].enabled=false
        player.insert{name="transport-belt",count=1}
        storage.ghost=assert(surface.create_entity{name="entity-ghost",inner_name="transport-belt",position={-35,4},force=player.force})
        storage.started=event.tick
        game.auto_save("upgrade-stress")
        log("COMPANION 4096 unavailable belt upgrades prepared")
    end
    local elapsed=event.tick-storage.started
    if elapsed>480 then
        local count=player.surface.count_entities_filtered{name="companion-crafter",force=player.force}
        if count>0 then storage.observed_crafting=true end
        assert(count<=6,"upgrade autocrafting respects crafter capacity")
    end
    if elapsed==1 then player.set_shortcut_toggled("companion-construction-toggle",true)
    elseif elapsed==180 then
        assert(not storage.ghost.valid,"unavailable upgrades do not block supplied construction")
        assert(player.surface.count_entities_filtered{name="fast-transport-belt",force=player.force}==0,"no upgrades without materials")
        player.insert{name="fast-transport-belt",count=64}
    elseif elapsed==480 then
        assert(player.surface.count_entities_filtered{name="fast-transport-belt",force=player.force}==64,"late supplies complete exactly 64 upgrades")
        log("COMPANION upgrade stress construction and late material retry PASS")
        player.force.recipes["fast-transport-belt"].enabled=true
        player.insert{name="iron-plate",count=640}
    elseif elapsed==1500 then
        assert(storage.observed_crafting,"remaining upgrades start parallel autocrafting")
        assert(player.surface.count_entities_filtered{name="fast-transport-belt",force=player.force}>64,"autocrafted items complete further upgrades")
        assert(player.crafting_queue_size==0,"upgrade autocrafting stays out of player handcraft queue")
        log("COMPANION parallel upgrade autocrafting PASS")
        log("COMPANION INTEGRATION PASS")
        script.on_event(defines.events.on_tick,nil)
    end
end)
