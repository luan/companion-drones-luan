local visuals = {}
local main_pods = {{-.63, -.38}, {.63, -.38}, {-.63, .39}, {.63, .39}}
local manager_pods = {{-.43, .10}, {.43, .10}}

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
    local manager = entity.name == "companion-task-manager" or entity.name == "companion-crafter"
    local objects = {rendering.draw_sprite{sprite = "companion-ground-shadow",
        surface = entity.surface, target = entity.position, render_layer = "object"}}
    for _, part in ipairs{"base_animation", "animation"} do
        for index = 1, 2 do
            objects[#objects + 1] = rendering.draw_animation{
                animation = manager and part == "animation" and (index == 1 and "companion-manager" or "companion-manager-mask")
                    or "companion-" .. part .. "-" .. index,
                animation_speed = 0, surface = entity.surface, target = entity.position,
                tint = index == 2 and color or {1, 1, 1}, render_layer = "air-object"}
        end
    end
    for index = 6, 7 do
        objects[index] = rendering.draw_animation{animation = "companion-landing-gear",
            animation_speed = 0, surface = entity.surface, target = entity.position,
            tint = index == 6 and {0, 0, 0, 0.25} or {1, 1, 1}, render_layer = "object", visible = false}
    end
    local pods = manager and manager_pods or main_pods
    for index in ipairs(pods) do
        objects[index + 7] = rendering.draw_animation{animation = "companion-turbine",
            animation_speed = 0.8, animation_offset = index * 3, surface = entity.surface,
            target = entity.position, render_layer = "arrow"}
    end
    return objects
end

function visuals.update_combat(entity, color, slot)
    local state = slot.visuals
    if not state or not state.body[1].valid or not state.body[2].valid then
        visuals.clear(slot)
        state = {body = {}}
        for index, animation in ipairs{"companion-combat-body-1", "companion-combat-mask-1"} do
            state.body[index] = rendering.draw_animation{animation = animation, animation_speed = 0,
                surface = entity.surface, target = entity, tint = index == 2 and color or {1, 1, 1},
                render_layer = "air-object"}
        end
        slot.visuals = state
    end
    -- Both layers must use the same direction and plasma/banking pose.
    local frame = math.floor(entity.orientation * 128 + 0.5) % 128
    local pose = math.floor(game.tick * 0.4) % 4 + 1
    for index, object in ipairs(state.body) do
        object.animation = "companion-combat-" .. (index == 1 and "body-" or "mask-") .. pose
        object.animation_offset = frame
        if index == 2 then object.color = color end
    end
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

function visuals.update(companion, color)
    local entity, craft = companion.entity, companion.craft
    color = color or entity.color or companion.player.color
    local utility = entity.name == "companion-task-manager" or entity.name == "companion-crafter"
    local model = utility and "companion-manager" or "companion-animation-1"
    local revision = 3
    local state = companion.visuals
    if state and (state.revision ~= revision or state.model ~= model or state.surface ~= entity.surface or not state.body[1].valid or not state.body[7] or not state.body[8]) then
        visuals.clear(companion)
        state = nil
    end
    if not state then
        state = {revision = revision, model = model, surface = entity.surface, altitude = 2, orientation = companion.worker and craft and 0.5 or companion.facing or entity.orientation, body = body(entity, color)}
        companion.visuals = state
    end
    if not companion.worker then
        local current, previous = companion.player.color, state.owner_color
        -- Factorio has no color-change event; observe the owner while preserving manual drone paint.
        if previous and (current.r ~= previous.r or current.g ~= previous.g
            or current.b ~= previous.b or current.a ~= previous.a) then entity.color = current end
        state.owner_color = current
        color = entity.color or current
    end
    local landed = craft and (companion.worker and companion.landed and not craft.finished
        or not companion.worker and visuals.can_land(companion))
    local destination = landed and 0.25 or 2
    state.altitude = state.altitude + math.max(-0.08, math.min(0.08, destination - state.altitude))
    local pos = entity.position
    if companion.worker then
        for _, object in ipairs(state.body) do object.x_scale = 0.55; object.y_scale = 0.55 end
    end
    -- Crafters retain a fixed tool-facing pose so their articulated landing feet align.
    local facing = companion.worker and craft and 0.5 or companion.facing or state.heading or entity.orientation
    if not companion.worker then
        -- The legless spider does not update native orientation while following.
        local previous = state.position
        if previous then
            local dx, dy = pos.x - previous.x, pos.y - previous.y
            local distance = dx * dx + dy * dy
            if distance > 0.01^2 and distance < 24^2 then
                facing = math.atan2(dx, -dy) / (2 * math.pi) % 1
            end
        end
    end
    state.position, state.heading = pos, facing
    state.orientation = state.orientation or facing
    local turn = (facing - state.orientation + 0.5) % 1 - 0.5
    state.orientation = (state.orientation + math.max(-0.0125, math.min(0.0125, turn * 0.25))) % 1
    local hover = landed and 0 or math.sin(game.tick * math.pi / 90 + entity.unit_number) * 0.10
    local torso = {pos.x, pos.y - state.altitude + hover}
    state.body[1].target = pos
    for index = 2, 5 do
        state.body[index].target = torso
        state.body[index].animation_offset = index >= 4 and math.floor(state.orientation * 128 + 0.5) % 128 or 0
        if index % 2 == 1 then state.body[index].color = color end
    end
    local pods = utility and manager_pods or main_pods
    -- Same orthographic projection and pixel density as the Blender camera.
    local displayed_heading = math.floor(state.orientation * 128 + 0.5) % 128 / 128
    local angle = math.pi - displayed_heading * math.pi * 2
    local cos, sin = math.cos(angle), math.sin(angle)
    local scale = companion.worker and 0.55 or 1
    local rotor_height = utility and 0.21375 or 0.285
    for index, pod in ipairs(pods) do
        local x, y = pod[1] * cos - pod[2] * sin, pod[1] * sin + pod[2] * cos
        local rotor = state.body[index + 7]
        rotor.target = {torso[1] + x * 320 / 2.6 * 0.25 / 32 * scale,
            torso[2] - (y * 0.82682 + (rotor_height - 0.18) * 0.56246) * 320 / 2.6 * 0.25 / 32 * scale}
        rotor.x_scale = scale * (utility and 0.75 or 1)
        rotor.y_scale = rotor.x_scale
        rotor.render_layer = "arrow" -- Keep rear turbines above their opaque motor wells.
        rotor.animation_speed = landed and 0 or 0.8
    end
    local extension = math.max(0, math.min(1, (2 - state.altitude) / 1.75))
    for index = 6, 7 do
        state.body[index].target = {torso[1], torso[2] + (index == 6 and 0.08 or 0)}
        state.body[index].animation_offset = math.floor(extension * 31 + 0.5)
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
