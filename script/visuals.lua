local visuals = {}

function visuals.can_land(companion)
    local player, entity = companion.player, companion.entity
    if not player.connected or not player.character or player.physical_surface.platform
        or entity.surface ~= player.physical_surface then return false end
    local a, b = entity.position, player.physical_position
    return (a.x - b.x)^2 + (a.y - b.y)^2 <= 12^2
end

local function destroy(objects)
    for _, object in pairs(objects or {}) do
        if object.valid then object.destroy() end
    end
end

function visuals.clear(companion)
    local state = companion.visuals
    if not state then return end
    destroy(state.body)
    destroy(state.effects)
    companion.visuals = nil
end

local function body(entity, color)
    local objects = {rendering.draw_sprite{sprite = "companion-ground-shadow",
        surface = entity.surface, target = entity.position, render_layer = "object"}}
    for _, part in ipairs{"base_animation", "animation"} do
        for index = 1, 2 do
            objects[#objects + 1] = rendering.draw_animation{
                animation = "companion-" .. part .. "-" .. index,
                animation_speed = 0, surface = entity.surface, target = entity.position,
                tint = index == 2 and color or {1, 1, 1}, render_layer = "air-object"}
        end
    end
    for index = 6, 7 do
        objects[index] = rendering.draw_animation{animation = "companion-landing-gear",
            animation_speed = 0, surface = entity.surface, target = entity.position,
            tint = index == 6 and {0, 0, 0, 0.25} or {1, 1, 1}, render_layer = "object", visible = false}
    end
    return objects
end

local function effects(entity, craft)
    local objects = {
        rendering.draw_sprite{surface = entity.surface, target = entity.position,
            sprite = "companion-work-glow", tint = {0.02, 0.08, 0.09, 0.1}, render_layer = "air-object"},
        rendering.draw_sprite{surface = entity.surface, target = entity.position,
            sprite = "item/" .. craft.item, x_scale = 0.85, y_scale = 0.85, render_layer = "arrow"},
    }
    for index = 3, 4 do
        objects[index] = rendering.draw_line{surface = entity.surface, from = entity.position,
            to = entity.position, color = index == 3 and {0.15, 0.2, 0.22} or {0.2, 0.65, 0.7}, width = 5}
    end
    objects[5] = rendering.draw_text{surface = entity.surface, target = entity.position,
        text = "×" .. (craft.count or 1), color = {1, 1, 1}, scale = 1.1,
        alignment = "center", use_rich_text = false, render_layer = "arrow"}
    return objects
end

function visuals.update(companion)
    local entity, craft = companion.entity, companion.craft
    local state = companion.visuals
    if state and (state.surface ~= entity.surface or not state.body[1].valid or not state.body[7]) then
        visuals.clear(companion)
        state = nil
    end
    if not state then
        state = {surface = entity.surface, altitude = 2, body = body(entity, companion.player.color)}
        companion.visuals = state
    end
    local landed = craft and (companion.worker and companion.landed and not craft.finished
        or not companion.worker and visuals.can_land(companion))
    local destination = landed and 0.25 or 2
    state.altitude = state.altitude + math.max(-0.08, math.min(0.08, destination - state.altitude))
    local pos = entity.position
    if companion.worker then
        for _, object in ipairs(state.body) do object.x_scale = 0.55; object.y_scale = 0.55 end
    end
    local torso = {pos.x, pos.y - state.altitude}
    state.body[1].target = pos
    for index = 2, 5 do
        state.body[index].target = torso
        state.body[index].animation_offset = index >= 4 and math.floor(entity.orientation * 64) % 64 or 0
        if index % 2 == 1 then state.body[index].color = companion.player.color end
    end
    local extension = math.max(0, math.min(1, (2 - state.altitude) / 1.75))
    for index = 6, 7 do
        state.body[index].target = {pos.x, pos.y - state.altitude + 0.25 + (index == 6 and 0.08 or 0)}
        state.body[index].animation_offset = math.floor(extension * 5 + 0.5)
        state.body[index].visible = extension > 0.05
    end
    if not craft then
        destroy(state.effects)
        state.effects = nil
        state.item = nil
        return
    end
    if state.item ~= craft.item or not state.effects or not state.effects[5] then
        destroy(state.effects)
        state.effects = effects(entity, craft)
        state.item = craft.item
    end
    local objects = state.effects
    local pulse = 0.75 + 0.25 * math.sin(game.tick * math.pi / 45)
    objects[1].target = torso
    objects[1].color = {0.02 * pulse, 0.08 * pulse, 0.09 * pulse, 0.1 * pulse}
    objects[1].visible = not not landed
    local head = {pos.x, pos.y - state.altitude - 1.6}
    objects[5].target = {head[1] + 0.65, head[2] + 0.15}
    objects[2].target = head
    objects[2].color = landed and {1, 1, 1} or {0.5, 0.5, 0.5}
    local start = {head[1] - 0.6, head[2] + 0.65}
    local progress = math.max(0, math.min(1, 1 - craft.remaining / math.max(1, craft.plan.energy * 60)))
    objects[3].from, objects[3].to = start, {head[1] + 0.6, start[2]}
    objects[4].from, objects[4].to = start, {start[1] + 1.2 * progress, start[2]}
end

return visuals
