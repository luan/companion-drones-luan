local supply = {}

local function network_id(pole)
    local id
    for _, network in pairs(pole.electric_network.parent_network.sub_networks) do
        if not id or network.id < id then id = network.id end
    end
    return id
end

-- Chests have no electrical connection of their own; pole coverage defines membership.
function supply.chests(player)
    local surface, force = player.physical_surface, player.force
    storage.supply_grids = storage.supply_grids or {}
    local key = surface.index .. ":" .. force.index
    local grid = storage.supply_grids[key]
    if not grid or game.tick >= grid.refresh then
        grid = {poles = surface.find_entities_filtered{type = "electric-pole", force = force},
            cursor = 1, networks = {}, refresh = game.tick + 300}
        storage.supply_grids[key] = grid
    end
    local closest, distance
    for _, radius in ipairs{16, 64, 256} do
        for _, pole in ipairs(surface.find_entities_filtered{
            type = "electric-pole", force = force, position = player.physical_position, radius = radius}) do
            local p, owner = pole.position, player.physical_position
            local d = (p.x - owner.x)^2 + (p.y - owner.y)^2
            if pole.electric_network and (not distance or d < distance or d == distance and pole.unit_number < closest.unit_number) then
                closest, distance = pole, d
            end
        end
        if closest then break end
    end
    if not closest then
        for _, pole in ipairs(grid.poles) do
            if pole.valid and pole.electric_network then
                local p, owner = pole.position, player.physical_position
                local d = (p.x - owner.x)^2 + (p.y - owner.y)^2
                if not distance or d < distance or d == distance and pole.unit_number < closest.unit_number then closest, distance = pole, d end
            end
        end
    end
    if not closest then return {} end
    local network = network_id(closest)
    local function scan(pole)
        if not pole.valid or not pole.electric_network then return end
        local parent = network_id(pole)
        local members = grid.networks[parent]
        if not members then members = {}; grid.networks[parent] = members end
        local p, radius = pole.position, pole.prototype.get_supply_area_distance(pole.quality)
        for _, chest in ipairs(surface.find_entities_filtered{force = force,
            type = {"container", "logistic-container", "infinity-container", "linked-container"},
            area = {{p.x - radius, p.y - radius}, {p.x + radius, p.y + radius}}}) do
            members[chest.unit_number] = {chest = chest, pole = pole}
        end
    end
    scan(closest)
    -- Share a bounded coverage scan across owners instead of rescanning the factory for each drone.
    if grid.tick ~= game.tick then
        grid.tick = game.tick
        for _ = 1, math.min(32, #grid.poles) do
            scan(grid.poles[grid.cursor])
            grid.cursor = grid.cursor % #grid.poles + 1
        end
    end
    local result = {}
    for id, member in pairs(grid.networks[network] or {}) do
        local chest, pole = member.chest, member.pole
        if chest.valid and chest.force == force and not chest.to_be_deconstructed(force)
            and pole.valid and pole.electric_network and network_id(pole) == network then
            result[#result + 1] = chest
        else grid.networks[network][id] = nil end
    end
    return result
end

return supply
