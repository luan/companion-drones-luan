-- Routine damage checks must rotate; urgent repair and explicit jobs must not wait for that scan.
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
        local surface=player.surface
        for _,entity in pairs(surface.find_entities_filtered{area={{-40,-40},{40,40}},force={"neutral","enemy"}}) do
            if entity.valid and entity.type~="resource" then entity.destroy() end
        end
        local tiles={}
        for x=-40,40 do for y=-40,40 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
        surface.set_tiles(tiles)
        for x=-32,31 do for y=-32,31 do
            assert(surface.create_entity{name="transport-belt",position={x,y},force=player.force})
        end end
        player.insert{name="repair-pack",count=20}
        player.insert{name="transport-belt",count=1}
        storage.turret=assert(surface.create_entity{name="laser-turret",position={35,0},force=player.force})
        storage.turret.health=100
        storage.furnace=assert(surface.create_entity{name="stone-furnace",position={-35,0},force=player.force})
        storage.furnace.health=100
        storage.rock=assert(surface.create_entity{name="big-rock",position={-35,8}})
        storage.rock.order_deconstruction(player.force)
        storage.ghost=assert(surface.create_entity{name="entity-ghost",inner_name="transport-belt",position={-35,4},force=player.force})
        storage.started=event.tick
        log("COMPANION 4096 healthy belts with urgent and routine repairs prepared")
    end
    local elapsed=event.tick-storage.started
    if elapsed==60 then
        assert(storage.turret.health>100,"military repair does not wait for routine scan")
        assert(not storage.ghost.valid,"construction does not wait for routine scan")
        assert(not storage.rock.valid,"neutral deconstruction does not wait for routine scan")
    elseif elapsed==300 then
        assert(storage.furnace.health==storage.furnace.max_health,"routine damage scan reaches entities beyond its first batch")
        log("COMPANION repair scan rotation, urgent repair, construction and neutral deconstruction PASS")
        log("COMPANION INTEGRATION PASS")
        script.on_event(defines.events.on_tick,nil)
    end
end)
