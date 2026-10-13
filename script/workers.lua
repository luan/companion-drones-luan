local tasks = require("script/tasks")
local crafting = require("script/crafting")
local visuals = require("script/visuals")
local workers = {}

function workers.spawn(companion, name, inventory)
    local entity = companion.entity.surface.create_entity{name = name, position = companion.entity.position,
        force = companion.player.force}
    entity.destructible = false
    return {entity = entity, player = companion.player, inventory = inventory, worker = true}
end

function workers.claims(companion, result)
    local function craft_keys(craft)
        for key in pairs(craft.task_keys or {}) do result[key] = true end
        if craft.task_key then result[craft.task_key] = true end
    end
    if companion.craft then craft_keys(companion.craft) end
    for _, worker in ipairs(companion.crafters or {}) do
        if not worker.craft.produced then craft_keys(worker.craft) end
    end
    for _, worker in ipairs(companion.managers or {}) do
        if worker.task then result[worker.task.key] = true end
        for _, task in ipairs(worker.tasks or {}) do result[task.key] = true end
    end
    if companion.job then
        for _, task in ipairs(companion.job.tasks) do result[task.key] = true end
    end
end

function workers.return_inventory(companion, inventory, targets, outputs)
    if targets then
        companion.crafted_tasks = companion.crafted_tasks or {}
        for _, task in ipairs(targets) do companion.crafted_tasks[task.key] = task end
    end
    -- Leave surplus available for a nearby crew search before returning it to the owner.
    if outputs then
        companion.crafted_outputs = companion.crafted_outputs or {}
        for name in pairs(outputs) do
            companion.crafted_outputs[name .. ":normal"] = game.tick + math.max(120, storage.companion_update_interval * 2)
        end
    end
    -- transfer_from_stack preserves durability, quality and item metadata.
    for i = 1, #inventory do
        local stack = inventory[i]
        if stack.valid_for_read then companion:get_inventory().transfer_from_stack(stack) end
        if stack.valid_for_read then
            local inserted = companion:insert_to_player_or_vehicle(stack)
            stack.count = stack.count - inserted
        end
    end
    companion:try_to_shove_inventory()
    for i = 1, #inventory do
        if inventory[i].valid_for_read then companion:get_inventory().transfer_from_stack(inventory[i]) end
    end
    return inventory.is_empty()
end

local function remove(worker)
    visuals.clear(worker)
    if worker.entity.valid then worker.entity.destroy() end
    worker.inventory.destroy()
end

local function move(worker, position, surface, speed)
    if not worker.entity.valid then return false end
    if worker.entity.surface ~= surface then
        local name = worker.entity.name
        visuals.clear(worker)
        worker.entity.destroy()
        worker.entity = surface.create_entity{name = name, position = position, force = worker.player.force}
        worker.entity.destructible = false
        return true
    end
    speed = speed * settings.global["companion-mini-drone-speed"].value
    local pos = worker.entity.position
    local distance = tasks.distance(pos, position)
    if distance > 0.01 then worker.facing = math.atan2(position.x - pos.x, pos.y - position.y) / (2 * math.pi) % 1 end
    if distance <= speed then worker.entity.teleport(position); return true end
    worker.entity.teleport({pos.x + (position.x - pos.x) * speed / distance,
        pos.y + (position.y - pos.y) * speed / distance})
    return false
end

function workers.update_crafters(companion, speed)
    for index = #(companion.crafters or {}), 1, -1 do
        local worker = companion.crafters[index]
        local craft = worker.craft
        if not companion:player_wants_construction() or not companion.can_construct then craft.finished = true end
        if not worker.entity.valid then
            worker.entity = workers.spawn(companion, "companion-crafter", worker.inventory).entity
        end
        local owner = companion.player.physical_position
        if not worker.landing then
            local slot = worker.slot or index
            local angle = slot * 2.3999632297
            local radius = 2 + math.min(8, math.sqrt(slot))
            worker.landing = {position = {x = owner.x + math.cos(angle) * radius,
                y = owner.y + math.sin(angle) * radius}, surface = companion.player.physical_surface}
        end
        local landing = worker.landing
        if not craft.finished then
            if not worker.landed then worker.landed = move(worker, landing.position, landing.surface, 0.10) end
            if worker.landed and worker.visuals and worker.visuals.altitude <= 0.3 then
                craft.remaining = math.max(0, craft.remaining - (game.tick - craft.last_tick) * speed)
            end
        end
        craft.last_tick = game.tick
        if craft.remaining == 0 and not craft.finished then
            local plan = craft.plan
            if craft.targets then
                local needed = 0
                for _, task in ipairs(craft.targets) do
                    if tasks.pending(task, companion.player.force) then needed = needed + task.item.count end
                end
                if needed < craft.count then
                    local available = {}
                    for _, stack in ipairs(craft.inventory.get_contents()) do available[stack.name] = stack.count end
                    plan = needed > 0 and crafting.plan(crafting.recipes(companion.player, craft.item), available, craft.item, needed) or nil
                    if plan then
                        craft.count = needed
                        local slots = 0
                        for name, count in pairs(plan.outputs) do slots = slots + math.ceil(count / prototypes.item[name].stack_size) end
                        craft.inventory.resize(#craft.inventory + slots)
                    end
                end
            end
            local valid = plan ~= nil
            for _, name in ipairs(plan and plan.steps or {}) do
                if not crafting.recipe(companion.player, name) then valid = false; break end
            end
            if valid then
                for name, count in pairs(plan.ingredients) do
                    if count > 0 then assert(craft.inventory.remove{name = name, count = count} == count) end
                end
                for name, count in pairs(plan.outputs) do
                    assert(craft.inventory.insert{name = name, count = count} == count)
                end
                craft.plan = plan
                craft.produced = true
            end
            craft.finished = true -- Ineligible recipes return their original ingredients.
        end
        if craft.finished then
            -- Retract the feet and lift off before moving; keep delivered cargo safe throughout.
            if (not worker.visuals or worker.visuals.altitude >= 1.95)
                and move(worker, companion.entity.position, companion.entity.surface, 0.10)
                and workers.return_inventory(companion, worker.inventory, craft.produced and craft.targets, craft.produced and craft.plan.outputs) then
                remove(worker)
                table.remove(companion.crafters, index)
                companion.next_search_tick = game.tick
            end
        end
    end
end

local function cargo_slots(entity)
    local slots = 1
    for index = 1, entity.get_max_inventory_index() do
        local inventory = entity.get_inventory(index)
        if inventory then slots = slots + #inventory end
    end
    if entity.type == "transport-belt" or entity.type == "splitter" or entity.type == "underground-belt" then
        for index = 1, entity.get_max_transport_line_index() do
            slots = slots + #entity.get_transport_line(index)
        end
    end
    for _, product in pairs(entity.prototype.mineable_properties.products or {}) do
        if product.type == "item" then
            slots = slots + math.ceil((product.amount_max or product.amount or 1) / prototypes.item[product.name].stack_size)
        end
    end
    return slots
end

local function perform(worker)
    local task, inventory = worker.task, worker.inventory
    local entity, item = task.entity, task.item
    local success = false
    if task.kind == "build" then
        local collisions = entity.revive{raise_revive = true, overflow = inventory}
        success = collisions ~= nil
    elseif task.kind == "upgrade" then
        inventory.resize(math.max(#inventory, #inventory - inventory.count_empty_stacks() + cargo_slots(entity) + 1))
        success = entity.apply_upgrade(nil, inventory) ~= nil
    elseif task.kind == "deconstruct" then
        if entity.type == "cliff" then success = entity.destroy{raise_destroy = true}
        else
            inventory.resize(math.max(#inventory, #inventory - inventory.count_empty_stacks() + cargo_slots(entity)))
            success = entity.mine{inventory = inventory, force = true, raise_destroyed = true}
        end
    elseif task.kind == "repair" then
        local stack = inventory.find_item_stack(item)
        if stack then
            local amount = math.min(entity.max_health - entity.health, stack.durability)
            entity.health = entity.health + amount
            if stack.durability <= amount then
                if stack.count == 1 then stack.clear()
                else
                    stack.count = stack.count - 1
                    stack.durability = stack.prototype.get_durability(stack.quality)
                end
            else stack.durability = stack.durability - amount end
            success = true
            return success -- Durability, rather than a whole repair pack, pays for repairs.
        end
    elseif task.kind == "deliver" then
        local target = entity.proxy_target
        if not target or not target.valid then return false end
        local plans = entity.insert_plan
        for _, plan in ipairs(plans) do
            if plan.id.name == item.name and (plan.id.quality or "normal") == item.quality then
                for _, position in ipairs(plan.items.in_inventory or {}) do
                    position.count = position.count or 1
                    local destination = target.get_inventory(position.inventory)
                    local stack = inventory.find_item_stack(item)
                    if destination and stack and position.stack + 1 <= #destination then
                        local amount = math.min(stack.count, position.count)
                        local transfer = game.create_inventory(1)
                        transfer[1].set_stack(stack)
                        transfer[1].count = amount
                        destination[position.stack + 1].transfer_stack(transfer[1])
                        local inserted = amount - (transfer[1].valid_for_read and transfer[1].count or 0)
                        stack.count = stack.count - inserted
                        transfer.destroy()
                        position.count = position.count - inserted
                        success = success or inserted > 0
                    end
                end
                local equipment_prototype = prototypes.item[item.name].place_as_equipment_result
                if target.grid and equipment_prototype then
                    for _, equipment in pairs(target.grid.equipment) do
                        if (plan.items.grid_count or 0) > 0 and inventory.get_item_count(item) > 0
                            and equipment.name == "equipment-ghost" and equipment.ghost_name == equipment_prototype.name
                            and equipment.quality.name == item.quality then
                            target.grid.revive(equipment)
                            inventory.remove{name = item.name, quality = item.quality, count = 1}
                            plan.items.grid_count = plan.items.grid_count - 1
                            success = true
                        end
                    end
                end
            end
        end
        local remaining = {}
        for _, plan in ipairs(plans) do
            local positions = {}
            for _, position in ipairs(plan.items.in_inventory or {}) do
                if (position.count or 1) > 0 then positions[#positions + 1] = position end
            end
            plan.items.in_inventory = positions
            if #positions > 0 or (plan.items.grid_count or 0) > 0 then remaining[#remaining + 1] = plan end
        end
        entity.insert_plan = remaining
    end
    if success and item and task.kind ~= "deliver" then inventory.remove(item) end
    return success
end

function workers.update_managers(companion)
    for index = #(companion.managers or {}), 1, -1 do
        local worker = companion.managers[index]
        if not worker.entity.valid then
            worker.entity = workers.spawn(companion, "companion-task-manager", worker.inventory).entity
        end
        -- Convert managers already flying in an unreleased sandbox save.
        if worker.task then worker.tasks, worker.task = {worker.task}, nil end
        worker.tasks = worker.tasks or {}
        local task = worker.tasks[1]
        local owner = companion.player.physical_position
        if not companion:player_wants_construction() or not companion.can_construct then
            worker.tasks = {}
            task = nil
        end
        if task and (not tasks.pending(task, companion.player.force)
            or task.entity.surface ~= companion.player.physical_surface
            or tasks.distance(task.entity.position, owner) > settings.startup["companion-work-radius"].value) then
            table.remove(worker.tasks, 1)
            task = nil
        end
        if task then
            local position = task.entity.position
            local distance = tasks.distance(worker.entity.position, position)
            if distance > 12 then
                move(worker, position, task.entity.surface, math.min(0.12, distance - 10))
            else
                worker.task = task
                local success = perform(worker)
                worker.task = nil
                if success then
                    local source = worker.entity.position
                    worker.entity.surface.create_entity{name = "inserter-beam", position = source,
                        source_position = {source.x, source.y - 2}, target_position = position, duration = 8, max_length = 16}
                else companion.deferred[task.key] = game.tick + 120 end
                table.remove(worker.tasks, 1)
            end
        elseif #worker.tasks == 0 and move(worker, companion.entity.position, companion.entity.surface, 0.12) then
            if workers.return_inventory(companion, worker.inventory) then
                remove(worker)
                table.remove(companion.managers, index)
                companion.next_search_tick = game.tick
            end
        end
    end
end

function workers.park(companion)
    for _, group in ipairs{companion.crafters or {}, companion.managers or {}} do
        for index = #group, 1, -1 do
            local worker = group[index]
            worker.task, worker.tasks = nil, {}
            if worker.craft then
                worker.craft.finished = true
                worker.craft.task_key, worker.craft.task_keys = nil, nil
                worker.craft.last_tick = game.tick
            end
            visuals.clear(worker)
            if worker.entity.valid then move(worker, companion.entity.position, companion.entity.surface, 1000000) end
            -- Release task claims even when the owner's trunk cannot accept all the returned cargo.
            for i = 1, #worker.inventory do
                local stack = worker.inventory[i]
                if stack.valid_for_read then companion:get_inventory().transfer_from_stack(stack) end
            end
            if worker.inventory.is_empty() then
                remove(worker)
                table.remove(group, index)
            end
        end
    end
end

function workers.visuals(companion)
    if not companion.player.connected or not companion.player.character or companion.player.physical_surface.platform then return end
    for _, group in ipairs{companion.crafters or {}, companion.managers or {}} do
        for _, worker in ipairs(group) do if worker.entity.valid then visuals.update(worker, companion.entity.color or companion.player.color) end end
    end
end

function workers.destroy(companion)
    for _, group in ipairs{companion.crafters or {}, companion.managers or {}} do
        for _, worker in ipairs(group) do
            for i = 1, #worker.inventory do
                if worker.inventory[i].valid_for_read then
                    companion.player.physical_surface.spill_item_stack{position = companion.player.physical_position,
                        stack = worker.inventory[i], enable_looted = true, force = companion.player.force, allow_belts = false}
                end
            end
            remove(worker)
        end
    end
    companion.crafters, companion.managers = nil, nil
end

return workers
