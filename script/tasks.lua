local tasks = {}
local repair_items

function tasks.distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
end

local function placement_item(prototype, quality)
    local items = prototype and prototype.items_to_place_this
    local item = items and items[1]
    if item then return {name = item.name, count = item.count or 1, quality = quality} end
end

local function task_for(entity, force, repair_items)
    local quality = entity.quality.name
    if entity.to_be_deconstructed(force) then
        if (not entity.minable and entity.type ~= "cliff") or entity.name == "companion" then return end
        local item
        if entity.type == "cliff" then
            item = {name = entity.prototype.cliff_explosive_prototype, count = 1, quality = "normal"}
        end
        return "deconstruct", item
    elseif entity.type == "entity-ghost" or entity.type == "tile-ghost" then
        if entity.type == "entity-ghost" and not entity.surface.can_place_entity{
            name = entity.ghost_name, position = entity.position, direction = entity.direction,
            force = force, quality = entity.quality, build_check_type = defines.build_check_type.ghost_revive,
        } then return end
        return "build", placement_item(entity.ghost_prototype, quality)
    elseif entity.to_be_upgraded() then
        local prototype, target_quality = entity.get_upgrade_target()
        return "upgrade", placement_item(prototype, target_quality and target_quality.name or quality)
    elseif entity.type == "item-request-proxy" then
        return "deliver", entity.item_requests[1]
    elseif entity.health and entity.get_health_ratio() < 1 and entity.is_entity_with_owner then
        return "repair", repair_items[1]
    end
end

function tasks.collect(player, companion, recent_area, recent_tick, tile_cursor)
    local candidates = {}
    if not repair_items then
        repair_items = {}
        for name, prototype in pairs(prototypes.item) do
            if prototype.type == "repair-tool" then
                for quality in pairs(prototypes.quality) do
                    repair_items[#repair_items + 1] = {name = name, count = 1, quality = quality}
                end
            end
        end
        table.sort(repair_items, function(a, b)
            if a.quality ~= b.quality then return prototypes.quality[a.quality].level < prototypes.quality[b.quality].level end
            return a.name < b.name
        end)
    end
    local surface, position = player.physical_surface, player.physical_position
    local radius = settings.startup["companion-work-radius"].value
    local entities = surface.find_entities_filtered{position = position, radius = radius, type = "tile-ghost", invert = true}
    local tiles = surface.find_entities_filtered{position = position, radius = radius, type = "tile-ghost", force = player.force}
    -- Rotate through bulk tile work; entity construction and urgent repairs are checked every search.
    local total = #tiles
    local cursor, count = (tile_cursor or 0) % math.max(1, total), math.min(512, total)
    for offset = 1, count do entities[#entities + 1] = tiles[(cursor + offset - 1) % total + 1] end
    for _, entity in ipairs(entities) do
        if entity ~= companion and (entity.force == player.force or entity.force.name == "neutral") then
            local kind, item = task_for(entity, player.force, repair_items)
            if kind and (item or kind == "deconstruct") then
                if item then item = {name = item.name, count = item.count or 1, quality = item.quality or "normal"} end
                local position = entity.position
                local recent = recent_area and recent_tick and game.tick - recent_tick < 600
                    and position.x >= recent_area.left_top.x and position.x <= recent_area.right_bottom.x
                    and position.y >= recent_area.left_top.y and position.y <= recent_area.right_bottom.y
                local urgent = kind == "repair" and entity.get_health_ratio() < 0.7
                    and (entity.type == "car" or entity.type == "spider-vehicle" or entity.is_military_target)
                local reach = companion.logistic_cell and companion.logistic_cell.construction_radius or 0
                candidates[#candidates + 1] = {
                    entity = entity, kind = kind, item = item, alternatives = kind == "repair" and repair_items or nil,
                    key = table.concat({entity.surface.index, entity.unit_number or entity.name, position.x, position.y, kind, item and item.name or "",
                        item and item.quality or entity.quality.name}, ":"),
                    priority = urgent and 0 or recent and 1 or 2,
                    reachable = tasks.distance(companion.position, position) <= reach,
                    distance = tasks.distance(companion.position, position),
                }
            end
        end
    end
    return candidates, (cursor + count) % math.max(1, total)
end

function tasks.less(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    if a.reachable ~= b.reachable then return a.reachable end
    if a.onboard ~= b.onboard then return a.onboard end
    local a_cost, b_cost = a.distance - a.age, b.distance - b.age
    if a_cost ~= b_cost then return a_cost < b_cost end
    return a.key < b.key
end

function tasks.pending(task, force)
    local entity = task.entity
    if not entity.valid or (entity.force ~= force and entity.force.name ~= "neutral") then return false end
    if task.kind == "repair" then return entity.get_health_ratio() < 1 end
    if task.kind == "upgrade" then
        if not entity.to_be_upgraded() then return false end
        local prototype, quality = entity.get_upgrade_target()
        local item = placement_item(prototype, quality and quality.name or entity.quality.name)
        return item and item.name == task.item.name and item.quality == task.item.quality
    end
    if task.kind == "deconstruct" then return entity.to_be_deconstructed(force) end
    if task.kind == "deliver" then return #entity.item_requests > 0 end
    return entity.type == "entity-ghost" or entity.type == "tile-ghost"
end

function tasks.progress(batch, force)
    local progress, pending = 0, false
    for _, task in ipairs(batch) do
        if not tasks.pending(task, force) then progress = progress + 1
        else
            pending = true
            if task.kind == "deconstruct" then
                local inventory = task.entity.get_inventory(defines.inventory.chest)
                if inventory then progress = progress + 1 / (inventory.get_item_count() + 1) end
            elseif task.kind == "repair" then progress = progress + task.entity.get_health_ratio()
            elseif task.kind == "deliver" then
                local count = 0
                for _, item in pairs(task.entity.item_requests) do count = count + item.count end
                progress = progress + 1 / (count + 1)
            end
        end
    end
    return progress, pending
end

return tasks
