local function check(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function build(player, name, items, expected)
    player.get_main_inventory().clear()
    player.teleport({0, 0})
    for _, item in ipairs(items) do player.insert{name = item, count = 1} end
    player.cursor_stack.set_stack{name = "companion", count = 1}
    player.build_from_cursor{position = {2, 0}}
    local entity = assert(player.surface.find_entities_filtered{name = "companion", position = {2, 0}}[1], name .. " placed")
    local inventory = entity.get_fuel_inventory()
    check(inventory.get_item_count(expected or "coal"), expected and 1 or 0, name .. " chosen fuel")
    check(inventory.get_item_count("uranium-fuel-cell"), 0, name .. " reject nuclear category")
    if expected then check(player.get_item_count(expected), 0, name .. " transfer from player") end
    return {player = player, entity = entity}
end

script.on_init(function()
    game.speed = 1000
    game.surfaces[1].request_to_generate_chunks({0, 0}, 1)
    game.surfaces[1].force_generate_chunk_requests()
end)

script.on_event(defines.events.on_tick, function(event)
    local player = game.get_player(1)
    if not player then return end
    if not storage.started then
        if not player.character then player.create_character() end
        for _, entity in pairs(player.surface.find_entities_filtered{name = "companion"}) do
            player.mine_entity(entity)
        end
        storage.started = event.tick
    end
    local elapsed = event.tick - storage.started
    local best = settings.get_player_settings(player)["set-fuel-preference"].value
    local cases = {
        {"no-fuel", {}},
        {"nonchemical", {"uranium-fuel-cell"}},
        {"fuel-preference", {"coal", "rocket-fuel", "uranium-fuel-cell"}, best and "rocket-fuel" or "coal"},
        {"multiple-categories", {"test-multi-fuel"}, "test-multi-fuel"},
        {"refuel", {"coal"}, "coal"},
    }
    if elapsed >= 10 and elapsed <= 50 and elapsed % 10 == 0 then
        local case = cases[elapsed / 10]
        local built = build(player, case[1], case[2], case[3])
        if elapsed < 50 then
            player.mine_entity(built.entity)
        else
            storage.refuel = built
            built.entity.get_fuel_inventory().clear()
            built.entity.burner.remaining_burning_fuel = 0
            player.insert{name = "rocket-fuel", count = 1}
        end
    end
    if elapsed < 120 then return end
    local entity = storage.refuel.entity
    local fueled = entity.get_fuel_inventory().get_item_count("rocket-fuel") > 0
        or (entity.burner.currently_burning and entity.burner.currently_burning.name == "rocket-fuel")
    check(not not fueled, true, "ongoing refueling")
    check(storage.refuel.player.get_item_count("rocket-fuel"), 0, "refueling transfers one fuel")
    log("COMPANION INTEGRATION PASS")
    script.on_event(defines.events.on_tick, nil)
end)
