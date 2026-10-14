local tasks = require("script/tasks")
local crafting = require("script/crafting")
local workers = require("script/workers")
local visuals = require("script/visuals")
local supply = require("script/supply")
local mode = settings.startup["set-mode"].value
-- Preserve old saves that selected the former challenge-mode switch.
if settings.startup["set-challenge-mode"].value and mode % 2 == 0 then mode = mode + 1 end
local abandon_job_distance = 24 -- Hard owner leash, independent of research.
local follow_range = 12  -- how close we stick to the player
local task_timeout = 120 -- Two seconds without work, or outside the normal owner leash.
local def_speed = 5.0    -- non challenge mode companion speed
local ensure_player_companions
local recall_fighting_robots
local lib = {}           -- predeclaration
local debug_mode = false -- enables debugging functionality (no gameplay difference)

--------------------------- Challenge Mode Stat Control ---------------------------

local function set_defaults()
    if not storage then storage = storage or {} end
    storage.companion_update_interval = settings.startup["set-update-interval"].value or 5
    storage.companion_speed_factor = storage.companion_speed_factor or 1.0
    storage.player_speed_factor = storage.player_speed_factor or {} 
    if mode == 1 or mode == 3 then -- shitty values to start with in challenge mode
        storage.base_speed                   = 0.5
        storage.attack_count                 = 0
        storage.max_distance                 = 24
        storage.max_companions               = 1
    else -- moderately good (but not best) values for non challenge mode players
        storage.base_speed                   = def_speed
        storage.attack_count                 = 8
        storage.max_distance                 = 100
        storage.max_companions               = 1
    end
end

local function ensure_companion_upgrades()
    if not storage then storage = {} end
    if not storage.companion_upgrades then storage.companion_upgrades = {} end
    if mode ~= 1 and mode ~= 3 then return end -- only use this table in challenge or combined mode
    if not storage.companion_upgrades or not next(storage.companion_upgrades) then
        storage.companion_upgrades = { -- if you change any of these, remember to change the defaults up there ^ too
            ["electronics"]             = {{stat="base_speed",     value=1,    phrase="I can move a little easier now."}},
            ["automobilism"]            = {{stat="base_speed",     value=1.75, phrase="Engine boost activated."}},
            ["robotics"]                = {{stat="base_speed",     value=2.5,  phrase="Now I can fly like those robots!"}},
            ["rocket-fuel"]             = {{stat="base_speed",     value=10,   phrase="Rocket fuel: max speed!"}},
            --Recommended do not touch; these values do not behave predictably and were dialed in with pure trial and error. 
            
            ["military"]                = {{stat="attack_count",   value=1,    phrase="Rudimentary weapons systems online."}},
            ["laser"]                   = {{stat="attack_count",   value=3,    phrase="Laser system repaired."}},
            ["stronger-explosives-2"]   = {{stat="attack_count",   value=7,    phrase="Weapons systems powered up."}},
            ["laser-weapons-damage-3"]  = {{stat="attack_count",   value=12,   phrase="Energy weapons at max."}},
            --How many laser particles it spawns with each attack; each particle always does the same damage
            
            ["logistics"]               = {{stat="max_distance",   value=48,   phrase="This will let me plan ahead better."}},
            ["lamp"]                    = {{stat="max_distance",   value=80,   phrase="I can see more clearly now."}},
            ["radar"]                   = {{stat="max_distance",   value=128,  phrase="Radar has extended my range to max."}},
            -- Legacy challenge research remains available; the owner leash limits task searches.
            
            -- Companion Shield upgrade tree
            ["energy-shield-equipment"] = {{
                stat="companion-shield-mk0", 
                value="companion-shield-mk1", 
                phrase="Shield partially repaired."
            }},
            ["energy-shield-mk2-equipment"] = {{
                stat="companion-shield-mk1", 
                value="companion-shield-mk2", 
                phrase="Additional shields online."
            }},
            ["fusion-reactor-equipment"] = {{
                stat="companion-shield-mk2", 
                value="companion-shield-mk3", 
                phrase="Shields fully operational."
            }},

            -- Companion Roboport upgrade tree
            ["logistic-science-pack"] = {{
                stat="companion-roboport-mk0", 
                value="companion-roboport-mk1", 
                phrase="Roboport partially repaired."
            }},
            ["construction-robotics"] = {{
                stat="companion-roboport-mk1", 
                value="companion-roboport-mk2", 
                phrase="Roboport upgrade online."
            }},
            ["logistic-robotics"] = {{
                stat="companion-roboport-mk2", 
                value="companion-roboport-mk3", 
                phrase="Roboport fully operational."
            }},
        }
    end
end

--------------------------- Initialization ---------------------------

local script_data =
{
    companions = {},
    active_companions = {},
    player_data = {},

}

local function bind_storage()
    if not storage.companion then
        storage.companion = script_data
    else
        script_data = storage.companion
    end
end

lib.on_init = function()
    set_defaults()
    ensure_companion_upgrades()
    storage.companion = storage.companion or script_data
    storage.companion_update_interval = settings.startup["set-update-interval"].value or 5
    local force = game.forces.player
    if force.max_failed_attempts_per_tick_per_construction_queue == 1 then
        force.max_failed_attempts_per_tick_per_construction_queue = 4
    end
    if force.max_successful_attempts_per_tick_per_construction_queue == 3 then
        force.max_successful_attempts_per_tick_per_construction_queue = 8
    end
    bind_storage()
end

local function crafting_capacity(player, planets)
    local technology = player.force.technologies["companion-crafting-speed-1"]
    return 6 + planets + (technology and technology.level - 1 or 0)
end

local function crafting_speed(player, planets)
    local technology = player.force.technologies["companion-crafting-speed-1"]
    local levels = technology and technology.level - 1 or 0
    return settings.startup["companion-crafting-speed"].value * (1 + 0.5 * levels + 0.25 * planets)
end

local function set_companion_stats(player)
    ensure_companion_upgrades()
    local challenge = mode == 1 or mode == 3
    local stats = {base_speed = challenge and 0.5 or def_speed,
        attack_count = challenge and 0 or 8, max_distance = challenge and 24 or 100,
        max_companions = 1}
    for tech, upgrades in pairs(storage.companion_upgrades) do
        if player.force.technologies[tech] and player.force.technologies[tech].researched then
            for _, upgrade in pairs(upgrades) do
                if type(upgrade.value) == "number" then
                    local stat = upgrade.stat == "number_drones" and "max_companions" or upgrade.stat
                    stats[stat] = math.max(stats[stat] or 0, upgrade.value)
                end
            end
        end
    end
    local planets = 0
    for name, tech in pairs(player.force.technologies) do
        if name:sub(1, #"companion-planet-") == "companion-planet-" and tech.researched then planets = planets + 1 end
    end
    local promethium = player.force.technologies["companion-promethium-1"]
    stats.max_companions = 1 + math.floor(planets / 2) + (promethium and promethium.level - 1 or 0)
    stats.planet_upgrades = planets
    stats.base_speed = stats.base_speed * (1 + planets * 0.1)
    for name, bonus in pairs{["military-2"] = 4, ["military-3"] = 4, ["military-4"] = 8} do
        local technology = player.force.technologies[name]
        if technology and technology.researched then stats.attack_count = stats.attack_count + bonus end
    end
    stats.attack_count = stats.attack_count + planets
    local pd = script_data.player_data[player.index]
    if pd then pd.stats = stats end
    return stats
end

local get_companion = function(unit_number)

    local companion = unit_number and script_data.companions[unit_number]
    if not companion then return end

    if not companion.entity.valid then
        companion:on_destroyed()
        return
    end

    return companion
end

local rotate_vector = function(vector,    orientation)
    local x = vector[1] or vector.x
    local y = vector[2] or vector.y
    local angle = (orientation) * math.pi * 2
    return
    {
        x = (math.cos(angle) * x) - (math.sin(angle) * y),
        y = (math.sin(angle) * x) + (math.cos(angle) * y)
    }
end

local get_player_speed = function(player, boost)
    local boost = boost or 10.0 
    if player.vehicle then
        return math.abs(player.vehicle.speed) * boost
    end

    if player.character then
        return player.character_running_speed * boost
    end

    return 0.3

end

local Companion = {}
Companion.metatable = {__index = Companion}

Companion.new = function(entity, player)
    local player_data = script_data.player_data[player.index]
    if not player_data then
        player_data = {
            companions = {},
            last_job_search_offset = 0,
            last_attack_search_offset = 0
        }
        script_data.player_data[player.index] = player_data
        player.set_shortcut_available("companion-construction-toggle", true)
        player.set_shortcut_available("companion-attack-toggle", true)
        if mode == 1 or mode == 3 then
            player.set_shortcut_toggled("companion-attack-toggle", false)
        end
    end

    local count = 0
    for _ in pairs(player_data.companions) do count = count + 1 end
    local stats = set_companion_stats(player)
    if count >= stats.max_companions then
        if count == 1 then
			player.print("Your in-suit controller can't handle another friend just now.")
		else
			player.print("Your in-suit controller can't handle more than " .. stats.max_companions .. " companions for now.")
		end
        if entity and entity.valid then
			local inserted = player.insert{name = entity.name, count = 1}
			if inserted == 0 then
				-- NEEDS FIX: If player inventory is full, just drop it on the ground
				entity.surface.spill_item_stack{position = entity.position, stack = {name = entity.name, count = 1}, enable_looted = true, force = player.force, allow_belts = false}
			end
			entity.destroy()
		end
        return
    end

    player.request_translation({"idle-line.0"})
    player_data.companions[entity.unit_number] = true

    local companion = {
        entity = entity,
        player = player,
        unit_number = entity.unit_number,
        robots = {},
        flagged_for_equipment_changed = true,
        last_attack_tick = 0,
        job_done_pending = false,
        speed = 0,
        last_idle_line_tick = 0,
        next_forced_idle_tick = 18000,
		last_robot_count = 0
    }

    set_companion_stats(player)
    setmetatable(companion, Companion.metatable)
    script_data.companions[entity.unit_number] = companion
    script.register_on_object_destroyed(entity)

    companion:charge()
    entity.minable_flag = false
    entity.destructible = false
    companion:set_active()
end

--------------------------- Utilities ---------------------------

local adjust_follow_behavior = function(player)
    if not player.character or player.physical_surface.platform then return end
    local player_data = script_data.player_data[player.index]
    if not player_data then return end
    local count = 0
    local guys = {}

    local surface = player.physical_surface

    for unit_number, bool in pairs (player_data.companions) do
        local companion = get_companion(unit_number)
        if companion then
            if not companion.active and (companion.entity.surface == surface) then
                count = count + 1
                guys[count] = companion
            end
        end
    end

    if count == 0 then return end
    local reach = player.reach_distance - 2
    local length = math.min(5 + (count * 0.33), reach)
    if count == 1 then length = 2 end
    local dong = 0.75 + (0.5 / count)
    local speed = get_player_speed(player, 1.0)
    if player.vehicle then dong = dong + player.vehicle.orientation end
    table.sort(guys, function(a, b) return a.entity.unit_number < b.entity.unit_number end)

    local offset = {length, 0}
    local position = player.physical_position
    for k, companion in pairs (guys) do
        local angle = (k / count) + dong
        local follow_offset = rotate_vector(offset, angle)
        -- Scripted flight is the sole movement controller, including between ticks.
        companion.entity.follow_target = nil
        companion.entity.autopilot_destination = nil
        companion.entity.follow_offset = follow_offset
        companion:set_speed(speed)
        companion:charge()
    end
end

local function eff_base(player)
    local pd = script_data.player_data[player.index]
    return (pd and pd.stats or set_companion_stats(player)).base_speed
end

function Companion:clear_robot_stack()
    local inventory = self:get_inventory()
    local stack = inventory[21]
    if stack.valid_for_read and stack.name ~= "companion-construction-robot" then
        local inserted = self.player.insert(stack)
        if inserted == stack.count then stack.clear()
        else
            stack.count = stack.count - inserted
            self.entity.surface.spill_item_stack{position = self.entity.position, stack = stack,
                enable_looted = true, force = self.entity.force, allow_belts = false}
            stack.clear()
        end
    end
    stack.clear()
    inventory.set_filter(21, "companion-construction-robot")
end

function Companion:set_robot_stack()
    self:clear_robot_stack()
    if self.can_construct and self:player_wants_construction() and self.job then
        self:get_inventory()[21].set_stack{name = "companion-construction-robot", count = 100}
    end
    self.entity.allow_dispatching_robots = self.job ~= nil and self:player_wants_construction()
end

function Companion:set_active()
    self:set_robot_stack()
    self.flagged_for_equipment_changed = true
    local mod = self.unit_number % math.min(storage.companion_update_interval, 5)
    local list = script_data.active_companions[mod]
    if not list then
        list = {}
        script_data.active_companions[mod] = list
    end
    list[self.unit_number] = true
    self.active = true
    self:set_speed(eff_base(self.player) * 1.2)
    adjust_follow_behavior(self.player)
end

function Companion:clear_speed_sticker()
    if not self.speed_sticker then return end
    if self.speed_sticker.valid then self.speed_sticker.destroy() end
    self.speed_sticker = nil
end

function Companion:get_distance_boost(position)
    local distance = self:distance(position)
    return (distance / 10)
end

function Companion:clear_speed_fx()
    local fx = self.speed_fx
    if fx and fx.valid then
        fx.destroy()
    end
    self.speed_fx = nil
end

function Companion:set_speed(speed)
    self.speed = speed
    -- Retire the fixed-direction booster and vehicle sticker from older saves.
    self:clear_speed_sticker()
    self:clear_speed_fx()
end

function Companion:update_flight()
    local player, entity = self.player, self.entity
    if not player.connected or not player.character or player.physical_surface.platform
        or entity.surface ~= player.physical_surface then return end
    local offset = entity.follow_offset or {x = 2, y = 0}
    local ox, oy = offset.x or offset[1], offset.y or offset[2]
    local length = math.sqrt(ox^2 + oy^2)
    local scale = length > 6 and 6 / length or 1
    local owner, pos = player.physical_position, entity.position
    local dx, dy = owner.x + ox * scale - pos.x, owner.y + oy * scale - pos.y
    local distance = math.sqrt(dx^2 + dy^2)
    -- Flight bypasses spider leg pathing, which can stall despite a valid follow target.
    entity.follow_target, entity.autopilot_destination = nil, nil
    local velocity = self.flight_velocity or {x = 0, y = 0}
    -- Overdamped following settles without overshoot; acceleration is bounded on direction changes.
    local ax, ay = dx * 0.015 - velocity.x * 0.3, dy * 0.015 - velocity.y * 0.3
    local acceleration = math.sqrt(ax^2 + ay^2)
    local gain = acceleration > 0.035 and 0.035 / acceleration or 1
    local vx, vy = velocity.x + ax * gain, velocity.y + ay * gain
    local speed = math.sqrt(vx^2 + vy^2)
    local limit = math.max(eff_base(player) * 0.05, get_player_speed(player, 1) * 1.4)
        * (storage.companion_speed_factor or 1)
    if speed > limit then vx, vy = vx * limit / speed, vy * limit / speed end
    if distance < 0.02 and speed < 0.003 then vx, vy = 0, 0 end
    self.flight_velocity = {x = vx, y = vy}
    if vx ~= 0 or vy ~= 0 then entity.teleport({pos.x + vx, pos.y + vy}) end
end

function Companion:get_speed()
    return self.speed
end

function Companion:get_grid()
    return self.entity.grid
end

function Companion:clear_passengers()

    if self.driver and self.driver.valid then
        self.driver.destroy()
        self.driver = nil
    end

    if self.passenger and self.passenger.valid then
        self.passenger.destroy()
        self.passenger = nil
    end

end

function Companion:check_equipment()
    self.flagged_for_equipment_changed = nil

    local grid = self:get_grid()

    self.can_construct = false
    for k, equipment in pairs (grid.equipment) do
        if equipment.type == "roboport-equipment" then
			if equipment.name:find("^companion%-roboport") then
				self.can_construct = true
				break
			elseif equipment.name:find("^personal%-roboport") then
				self:say("I can't use this, this roboport is for you!")
				break
			end
		end
    end

    if self.can_construct then
        local network = self.entity.logistic_network
        local max_robots = (network and network.robot_limit) or 100
        if max_robots > 0 then
            self:set_robot_stack()
        else
            self.can_construct = false
        end
    else
        self:clear_robots()
		self:return_to_player()
    end

    self.can_attack = false
    for k, equipment in pairs (grid.equipment) do
        if equipment.name == "companion-defense-equipment" then
            self.can_attack = true
            break
        end
    end
end

function Companion:robot_spawned(robot)
    if not (robot and robot.valid) then return end
    local id = robot.unit_number
    self:set_active()
    self.robots[id] = robot
    robot.energy = robot.prototype.get_max_energy(robot.quality)
    if robot.valid then
        robot.destructible = false
        robot.minable_flag = false -- 2.1: LuaEntity.minable is read-only, use minable_flag
    end
    if self.entity and self.entity.valid and robot.valid then
        self.entity.surface.create_entity{
            name = "inserter-beam",
            position = self.entity.position,
            target = robot,
            source = self.entity,
            force = self.entity.force,
            source_offset = {0, 0}
        }
    end
    self:move_to_robot_average()
end

function Companion:clear_robots()
    for id, robot in pairs(self.robots) do
        if robot.valid then
            -- Recover cargo first; a full trunk must never make recall delete items.
            for _, inventory_id in ipairs{defines.inventory.robot_cargo, defines.inventory.robot_repair} do
                local inventory = robot.get_inventory(inventory_id)
                if inventory then
                    for i = 1, #inventory do
                        local stack = inventory[i]
                        if stack.valid_for_read then
                            local inserted = self.entity.valid and self.entity.insert(stack) or 0
                            stack.count = stack.count - inserted
                            if stack.valid_for_read then
                                robot.surface.spill_item_stack{position = robot.position, stack = stack,
                                    enable_looted = true, force = robot.force, allow_belts = false}
                                stack.clear()
                            end
                        end
                    end
                end
            end
            robot.destroy()
        end
        self.robots[id] = nil
    end
    if self.entity.valid then self:clear_robot_stack() end
end

function Companion:move_to_robot_average()
    -- Robots may work nearby, but must never steer the companion away from its owner.
    for id, robot in pairs(self.robots) do
        if not robot.valid then self.robots[id] = nil end
    end
    return next(self.robots) ~= nil
end

function Companion:charge()
    local pd = script_data.player_data[self.player.index]
    local level = pd and pd.stats and pd.stats.planet_upgrades or 0
    if self.planet_speed_level ~= level then
        if self.planet_speed_sticker and self.planet_speed_sticker.valid then self.planet_speed_sticker.destroy() end
        self.planet_speed_level, self.planet_speed_sticker = level, nil
    end
    if level > 0 then
        if not (self.planet_speed_sticker and self.planet_speed_sticker.valid) then
            self.planet_speed_sticker = self.entity.surface.create_entity{
                name = "companion-planet-speed-" .. level, position = self.entity.position, target = self.entity}
        end
        self.planet_speed_sticker.time_to_live = 120
    end
    for _, equipment in pairs(self:get_grid().equipment) do
        equipment.energy = equipment.max_energy
    end
    for id, robot in pairs(self.robots) do
        if robot.valid then robot.energy = robot.prototype.get_max_energy(robot.quality)
        else self.robots[id] = nil end
    end
end

function Companion:search_for_nearby_work()
    if self:player_wants_construction() and self.can_construct and not self.job and not self.is_in_combat then
        self:try_to_find_work()
    end
end

function Companion:search_for_nearby_targets()
    return self:try_to_find_targets()
end

function Companion:is_busy()
    -- are we doing ANYthing at all?
    return self.is_in_combat or self.is_busy_for_construction or self.moving_to_destination or self.job ~= nil
        or #(self.crafters or {}) > 0 or #(self.managers or {}) > 0
end

function Companion:say(text)
	if not settings.startup["companion-voice-lines"].value then return end
    local tick_value = 0
    local live_value = 0
    if debug_mode then -- when debugging, text is short lived and rapid firing
        tick_value = 1 
        live_value = 30 
    else -- otherwise text lasts 4 seconds and can only fire twice per second
        tick_value = 30 
        live_value = 240 
    end
    if (game.tick - (self.last_spoken_tick or 0)) <= tick_value then return end 
    self.last_spoken_tick = game.tick
    self.player.create_local_flying_text{
        position = {x = self.entity.position.x, y = self.entity.position.y - 2.5},
        text = text or "Error",
        color = {r = 0.4, g = 0.8, b = 1},
		time_to_live = live_value,
		speed = 0.5
    }
end

function Companion:on_destroyed()
    if not script_data.companions[self.unit_number] then
        --On destroyed has already been called.
        return
    end

    visuals.clear(self)
    workers.destroy(self)
    self:clear_robots()
    if self.craft then
        for i = 1, #self.craft.inventory do
            local stack = self.craft.inventory[i]
            if stack.valid_for_read then
                self.player.physical_surface.spill_item_stack{position = self.player.physical_position,
                    stack = stack, enable_looted = true, force = self.player.force, allow_belts = false}
            end
        end
        self.craft.inventory.destroy()
        self.craft = nil
    end

    script_data.companions[self.unit_number] = nil
    local player_data = script_data.player_data[self.player.index]

    player_data.companions[self.unit_number] = nil

    if not next(player_data.companions) then
        script_data.player_data[self.player.index] = nil
        self.player.set_shortcut_available("companion-attack-toggle", false)
        self.player.set_shortcut_available("companion-construction-toggle", false)
    end

    adjust_follow_behavior(self.player)
end

function Companion:distance(position)
    local source = self.entity.position
    local x2 = position[1] or position.x
    local y2 = position[2] or position.y
    return (((source.x - x2) ^ 2) + ((source.y - y2) ^ 2)) ^ 0.5
end

function Companion:get_inventory()
    local inventory = self.entity.get_inventory(defines.inventory.spider_trunk)
    return inventory
end

function Companion:insert_to_player_or_vehicle(stack)

    local inserted = self.player.insert(stack)
    if inserted > 0 then return inserted end

    if self.player.vehicle then
        inserted = self.player.vehicle.insert(stack)
        if inserted > 0 then return inserted end
        if self.player.vehicle.train then
            inserted = self.player.vehicle.train.insert(stack)
            if inserted > 0 then return inserted end
        end
    end

    return 0

end

function Companion:try_to_shove_inventory()
    local inventory = self:get_inventory()
    inventory.sort_and_merge()
    local total_inserted = 0
    local storage_chests
    local reserved = {}
    for key, task in pairs(self.crafted_tasks or {}) do
        if tasks.pending(task, self.player.force) and task.entity.surface == self.entity.surface
            and tasks.distance(task.entity.position, self.player.physical_position) <= settings.startup["companion-work-radius"].value then
            if task.item then reserved[task.item.name .. ":" .. task.item.quality] = true end
        else self.crafted_tasks[key] = nil end
    end
    for key, deadline in pairs(self.crafted_outputs or {}) do
        if deadline > game.tick then reserved[key] = true else self.crafted_outputs[key] = nil end
    end
    for k = 1, 20 do
        local stack = inventory[k]
        if stack.valid_for_read and not reserved[stack.name .. ":" .. stack.quality.name] then
            if stack.name == "companion-construction-robot" then
                stack.clear() -- Native returning workers are bookkeeping, never player cargo.
            else
                local inserted = self:insert_to_player_or_vehicle(stack)
                if inserted > 0 then stack.count = stack.count - inserted end
                total_inserted = total_inserted + inserted
                if stack.valid_for_read then
                    storage_chests = storage_chests or self:supply_chests()
                    for _, chest in ipairs(storage_chests) do
                        if chest.type == "logistic-container" and chest.prototype.logistic_mode == "storage"
                            and not chest.to_be_deconstructed(self.player.force) then
                            local filter = chest.storage_filter
                            if not filter or (filter.name == stack.name and filter.quality == stack.quality.name) then
                                total_inserted = total_inserted + chest.get_inventory(defines.inventory.chest).transfer_from_stack(stack)
                                if not stack.valid_for_read then break end
                            end
                        end
                    end
                end
                if stack.valid_for_read then self:set_status({"companion-status.cargo-full"}) end
            end
        end
    end

    if total_inserted > 0 then
        self.entity.surface.create_entity
        {
            name = "inserter-beam",
            source = self.entity,
            target = self.player.character,
            target_position = self.player.physical_position,
            force = self.entity.force,
            position = self.entity.position,
            duration = math.min(math.max(math.ceil(total_inserted / 5), 10), 60),
            max_length = follow_range + 4
        }
    end

end

function Companion:set_status(label)
    self.entity.custom_status = {diode = defines.entity_status_diode.green, label = label}
end

function Companion:cancel_job(defer)
    if self.job and defer then
        self.deferred = self.deferred or {}
        for _, task in ipairs(self.job.tasks) do self.deferred[task.key] = game.tick + task_timeout end
    end
    self.job = nil
    self.current_job_target = nil
    self.moving_to_destination = nil
    self.is_busy_for_construction = false
    self.entity.autopilot_destination = nil
    self.entity.allow_dispatching_robots = false
    self:clear_robots()
end

function Companion:return_to_player()
    self.moving_to_destination = nil
    self.entity.autopilot_destination = nil
    if self:distance(self.player.physical_position) <= follow_range and not self.job then
        self:try_to_shove_inventory()
    end
    self:set_speed(math.max(eff_base(self.player) * 0.8, get_player_speed(self.player, 1)))
    self.entity.follow_target = nil
    self.entity.autopilot_destination = nil
end

function Companion:take_item(item, target)
    local inventory = get_inventory(target)
    if not inventory then return false end
    while item.count > 0 do
        local stack = inventory.find_item_stack{name = item.name, quality = item.quality or "normal"}
        if not stack then break end
        -- Temporarily bound the source stack so insertion preserves durability and other metadata.
        local original = stack.count
        stack.count = math.min(original, item.count)
        local inserted = self.entity.insert(stack)
        if original == inserted then stack.clear() else stack.count = original - inserted end
        item.count = item.count - inserted
        if inserted == 0 then break end
    end
    return item.count == 0
end

function Companion:take_item_from_train(item, train)
    for _, wagon in pairs(train.cargo_wagons) do
        if self:take_item(item, wagon) then return true end
    end
    return false
end

function Companion:set_job_destination(position)
    local cell = self.entity.logistic_cell
    local reach = cell and cell.construction_radius or 0
    if self:distance(position) <= reach then
        self.moving_to_destination = nil
        self.entity.autopilot_destination = nil
        return
    end
    self.entity.follow_target = nil
    self.entity.autopilot_destination = position
    self.moving_to_destination = true
    self:set_active()
end

function Companion:player_wants_attack()
    return self.player.is_shortcut_toggled("companion-attack-toggle")
end

function Companion:player_wants_construction()
    return self.player.is_shortcut_toggled("companion-construction-toggle")
end

function Companion:attack(entity, projectile_count)
    if entity.valid and tasks.distance(entity.position, self.player.physical_position) <= abandon_job_distance then
        self:deploy_combat_robots()
    end
end

function Companion:deploy_combat_robots()
    if not self:player_wants_attack() or not self.can_attack or not self.player.character then return end
    if self.player.physical_surface.platform or self.entity.surface ~= self.player.physical_surface then return end
    local pd = script_data.player_data[self.player.index]
    pd.combat_robots = pd.combat_robots or {}
    pd.combat_sources = pd.combat_sources or {}
    pd.combat_slots = pd.combat_slots or {}
    for id, robot in pairs(pd.combat_robots) do
        if not robot.valid then pd.combat_robots[id] = nil; pd.combat_sources[id] = nil; pd.combat_slots[id] = nil
        elseif robot.surface ~= self.player.physical_surface then
            robot.destroy()
            pd.combat_robots[id] = nil
            pd.combat_sources[id] = nil
            pd.combat_slots[id] = nil
        end
    end
    local stats = pd.stats or set_companion_stats(self.player)
    local banks = 0
    for _, equipment in pairs(self.entity.grid.equipment) do
        if equipment.name == "companion-defense-equipment" then banks = banks + 1 end
    end
    local limit = math.min(4, math.ceil(stats.attack_count * banks / 4))
    if limit == 0 or game.tick < (self.next_combat_deployment or 0) then return end
    local count = 0
    for id in pairs(pd.combat_robots) do
        if pd.combat_sources[id] == self.unit_number then count = count + 1 end
    end
    for i = count + 1, limit do
        local robot = self.entity.surface.create_entity{
            name = "companion-combat-robot",
            position = {self.entity.position.x, self.entity.position.y - (self.visuals and self.visuals.altitude or 2)},
            force = self.player.force, target = self.player.character}
        if robot then
            robot.combat_robot_owner = self.player.character
            pd.combat_robots[robot.unit_number] = robot
            pd.combat_sources[robot.unit_number] = self.unit_number
            pd.combat_slots[robot.unit_number] = {index = i, count = limit}
        end
    end
    self.next_combat_deployment = game.tick + 120
end

function Companion:try_to_find_targets()
    if not self:player_wants_attack() or not self.can_attack or self.player.physical_surface.platform then return false end
    local player = self.player
    if self.entity.surface ~= player.physical_surface then return false end
    local target, best
    local pos = player.physical_position
    for _, entity in pairs(player.physical_surface.find_entities_filtered{
        position = pos, radius = abandon_job_distance, is_military_target = true}) do
        local force = entity.force
        if entity.destructible and entity.type ~= "unit-spawner" and force ~= player.force and force.name ~= "neutral"
            and not player.force.get_friend(force) and not player.force.get_cease_fire(force) then
            local mobile = entity.type == "unit" or entity.type == "spider-unit" or entity.type == "combat-robot"
            -- Mobile threats and attacking units outrank stationary nests.
            local score = (mobile and 0 or 100) + tasks.distance(entity.position, pos)
            if not best or score < best then target, best = entity, score end
        end
    end
    if not target then return false end
    self:deploy_combat_robots()
    if not self.job then self:set_status({"companion-status.defending"}) end
    return true
end

function get_inventory(entity)
    if entity.is_player() then
        if not entity.controller_type or entity.controller_type ~= defines.controllers.character then return end
        return entity.get_main_inventory() or entity.get_output_inventory()
    end

    if entity.type == "spider-vehicle" then
        return entity.get_inventory(defines.inventory.spider_trunk)
    elseif entity.type == "car" then
        return entity.get_inventory(defines.inventory.car_trunk)
    elseif entity.type == "logistic-container" or entity.type == "container"
        or entity.type == "infinity-container" or entity.type == "linked-container" then
        return entity.get_inventory(defines.inventory.chest)
    elseif entity.type == "cargo-wagon" then
        return entity.get_inventory(defines.inventory.cargo_wagon)
    else
		return entity.get_main_inventory() or entity.get_output_inventory()
	end
end

function Companion:supply_network()
    local surface = self.player.physical_surface
    if surface.platform or self.entity.surface ~= surface then return nil end
    local network = surface.find_logistic_network_by_position(self.player.physical_position, self.player.force)
    if network and network == surface.find_logistic_network_by_position(self.entity.position, self.player.force) then
        return network
    end
end

function Companion:supply_chests()
    local surface = self.player.physical_surface
    if surface.platform or self.entity.surface ~= surface then return {} end
    local pd = script_data.player_data[self.player.index]
    if pd.chest_surface ~= surface or pd.chest_force ~= self.player.force or game.tick >= (pd.next_chest_scan or 0) then
        pd.chest_surface, pd.chest_force, pd.next_chest_scan = surface, self.player.force, game.tick + 60
        pd.chests = supply.chests(self.player)
        local network = self:supply_network()
        if network then
            for _, chest in ipairs(surface.find_entities_filtered{force = self.player.force,
                type = {"container", "logistic-container", "infinity-container", "linked-container"}}) do
                if surface.find_logistic_network_by_position(chest.position, chest.force) == network then
                    pd.chests[#pd.chests + 1] = chest
                end
            end
        end
        table.sort(pd.chests, function(a, b) return a.unit_number < b.unit_number end)
    end
    local chests, inventories = {}, {}
    for _, chest in ipairs(pd.chests) do
        if chest.valid and chest.force == self.player.force and not chest.to_be_deconstructed(self.player.force) then
            local inventory = chest.get_inventory(defines.inventory.chest)
            if inventory and not inventories[inventory] then
                inventories[inventory] = true
                chests[#chests + 1] = chest
            end
        end
    end
    return chests
end

function Companion:nearby_inventories()
    local companions, result = {}, {}
    local radius = settings.startup["companion-work-radius"].value
    for _, companion in pairs(script_data.companions) do
        if companion.entity.valid and companion.entity.force == self.player.force then companions[#companions + 1] = companion end
    end
    table.sort(companions, function(a, b) return a.unit_number < b.unit_number end)
    for _, companion in ipairs(companions) do
        if companion.entity.surface == self.entity.surface and tasks.distance(companion.entity.position, self.player.physical_position) <= radius then
            result[#result + 1] = companion:get_inventory()
        end
        for _, worker in ipairs(companion.crafters or {}) do
            if worker.craft.produced and worker.entity.valid and worker.entity.surface == self.entity.surface
                and tasks.distance(worker.entity.position, self.player.physical_position) <= radius then
                result[#result + 1] = worker.inventory
            end
        end
    end
    return result
end

function Companion:available_items(item)
    local query = {name = item.name, quality = item.quality or "normal"}
    local count = 0
    for _, inventory in ipairs(self:nearby_inventories()) do count = count + inventory.get_item_count(query) end
    for _, chest in ipairs(self:supply_chests()) do count = count + chest.get_inventory(defines.inventory.chest).get_item_count(query) end
    if self:distance(self.player.physical_position) <= follow_range then
        local inventory = self.player.get_main_inventory()
        if inventory then count = count + inventory.get_item_count(query) end
        local vehicle = self.player.vehicle
        if vehicle then
            if vehicle.train then
                for _, wagon in pairs(vehicle.train.cargo_wagons) do
                    count = count + wagon.get_inventory(defines.inventory.cargo_wagon).get_item_count(query)
                end
            else
                local trunk = get_inventory(vehicle)
                if trunk then count = count + trunk.get_item_count(query) end
            end
        end
    end
    return count
end

function Companion:incoming_items()
    local result = {}
    for _, companion in pairs(script_data.companions) do
        if companion.entity.valid and companion.entity.force == self.player.force then
            for _, worker in ipairs(companion.crafters or {}) do
                local craft = worker.craft
                if not craft.finished and worker.entity.valid and worker.entity.surface == self.entity.surface
                    and tasks.distance(worker.entity.position, self.player.physical_position) <= settings.startup["companion-work-radius"].value then
                    for name, amount in pairs(craft.plan.outputs) do
                        local spare = amount - (craft.item == name and (craft.count or 1) or 0)
                        local key = name .. ":normal"
                        result[key] = (result[key] or 0) + math.max(0, spare)
                    end
                end
            end
        end
    end
    return result
end

local function transfer_item(item, source, destination)
    local remaining = item.count
    while remaining > 0 do
        local stack = source.find_item_stack{name = item.name, quality = item.quality or "normal"}
        if not stack then break end
        local original = stack.count
        stack.count = math.min(original, remaining)
        local inserted = destination.insert(stack)
        if original == inserted then stack.clear() else stack.count = original - inserted end
        remaining = remaining - inserted
        if inserted == 0 then break end
    end
    return item.count - remaining
end

function Companion:find_and_take_from_player(item)
    for _, inventory in ipairs(self:nearby_inventories()) do
        if inventory ~= self:get_inventory() then
            item.count = item.count - transfer_item(item, inventory, self:get_inventory())
            if item.count == 0 then return true end
        end
    end
    for _, chest in ipairs(self:supply_chests()) do
        if self:take_item(item, chest) then return true end
    end
    if self:distance(self.player.physical_position) > follow_range then return false end
    if self:take_item(item, self.player) then return true end
    local vehicle = self.player.vehicle
    if not vehicle then return false end
    if vehicle.train then return self:take_item_from_train(item, vehicle.train) end
    return self:take_item(item, vehicle)
end


function Companion:try_to_craft(item, keys, recipes, targets)
    self.crafters = self.crafters or {}
    local stats = script_data.player_data[self.player.index].stats or set_companion_stats(self.player)
    local capacity = crafting_capacity(self.player, stats.planet_upgrades)
    if #self.crafters >= capacity or item.quality ~= "normal" or not self.player.character then return false end
    local available, sources = {}, {}
    for _, inventory in ipairs(self:nearby_inventories()) do sources[#sources + 1] = inventory end
    for _, chest in ipairs(self:supply_chests()) do sources[#sources + 1] = chest.get_inventory(defines.inventory.chest) end
    sources[#sources + 1] = self.player.get_main_inventory()
    for _, inventory in ipairs(sources) do
        for _, stack in pairs(inventory.get_contents()) do
            if stack.quality == "normal" then available[stack.name] = (available[stack.name] or 0) + stack.count end
        end
    end
    local stock = {}
    for name, count in pairs(available) do stock[name] = count end
    for key, count in pairs(self:incoming_items()) do
        local name = key:match("^(.*):normal$")
        stock[name] = (stock[name] or 0) + count
    end
    local plan = crafting.plan(crafting.recipes(self.player, item.name, recipes), stock, item.name, item.count)
    if not plan then return false end
    -- Wait for promised intermediates instead of making the same surplus in another worker.
    for name, count in pairs(plan.ingredients) do if count > (available[name] or 0) then return false end end
    local function slots(items)
        local count = 0
        for name, amount in pairs(items) do count = count + math.ceil(amount / prototypes.item[name].stack_size) end
        return count
    end
    local inventory = game.create_inventory(math.max(1, slots(plan.ingredients), slots(plan.outputs)))
    local transfers = {}
    for name, count in pairs(plan.ingredients) do
        local remaining = count
        for _, source in ipairs(sources) do
            local moved = transfer_item({name = name, count = remaining}, source, inventory)
            transfers[#transfers + 1] = {source = source, name = name, count = moved}
            remaining = remaining - moved
            if remaining == 0 then break end
        end
        if remaining > 0 then
            for _, transfer in ipairs(transfers) do
                transfer_item({name = transfer.name, count = transfer.count}, inventory, transfer.source)
            end
            for i = 1, #inventory do
                if inventory[i].valid_for_read then
                    self.entity.surface.spill_item_stack{position = self.entity.position, stack = inventory[i],
                        enable_looted = true, force = self.entity.force, allow_belts = false}
                end
            end
            inventory.destroy()
            return false
        end
    end
    local worker = workers.spawn(self, "companion-crafter", inventory)
    local slots = {}
    for _, other in ipairs(self.crafters) do slots[other.slot or 1] = true end
    worker.slot = 1
    while slots[worker.slot] do worker.slot = worker.slot + 1 end
    worker.craft = {inventory = inventory, plan = plan, remaining = math.ceil(plan.energy * 60),
        last_tick = game.tick, item = item.name, task_keys = keys, count = item.count, targets = targets}
    self.crafters[#self.crafters + 1] = worker
    self:return_to_player()
    self:set_status({"companion-status.crafting", prototypes.item[item.name].localised_name})
    return true
end

function Companion:update_crafting()
    self.crafters = self.crafters or {}
    -- Preserve ingredients and progress in saves made before worker crafting.
    if self.craft then
        local worker = workers.spawn(self, "companion-crafter", self.craft.inventory)
        worker.craft = self.craft
        self.crafters[#self.crafters + 1], self.craft = worker, nil
    end
    local stats = script_data.player_data[self.player.index].stats or set_companion_stats(self.player)
    workers.update_crafters(self, crafting_speed(self.player, stats.planet_upgrades))
end

function Companion:ensure_items(item)
    local query = {name = item.name, quality = item.quality}
    local supplied = self:get_inventory().get_item_count(query)
    for _, robot in pairs(self.robots) do
        if robot.valid then
            for _, inventory_id in ipairs{defines.inventory.robot_cargo, defines.inventory.robot_repair} do
                local inventory = robot.get_inventory(inventory_id)
                if inventory then supplied = supplied + inventory.get_item_count(query) end
            end
        end
    end
    local missing = item.count - supplied
    if missing <= 0 then return true end
    return self:find_and_take_from_player{name = item.name, quality = item.quality, count = missing}
end

function Companion:on_player_placed_equipment(event)
    self:set_active()
    --self:say("Equipment added")
end

function Companion:on_player_removed_equipment(event)
    self:set_active()
    --self:say("Equipment removed")
end

function Companion:teleport(position, surface)
    self:cancel_job(false)
    self:clear_speed_sticker()
    self:clear_speed_fx()  
    self.flight_velocity = nil
    self.entity.teleport(position, surface)
    self:set_active()
end

function Companion:change_force(force)

    self.entity.force = force
    workers.park(self)
    for _, group in ipairs{self.crafters or {}, self.managers or {}} do
        for _, worker in ipairs(group) do
            if worker.entity.valid then worker.entity.force = force end
            if worker.craft then worker.craft.finished = true end
        end
    end
    for k, robot in pairs (self.robots) do
        if robot.valid then
            robot.force = force
        end
    end

    self:check_equipment()

end

local on_built_entity = function(event)
    local entity = event.entity
    if not (entity and entity.valid) then return end

    if entity.name ~= "companion" then
        return
    end

    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end

    Companion.new(entity, player)

end

local on_entity_destroyed = function(event)
    local companion = get_companion(event.useful_id)
    if not companion then return end
    companion:on_destroyed()
end

function Companion:escape_danger(threat_pos)
    self:cancel_job(false)
    self:return_to_player()
end

function Companion:update()
    if not self.player.connected or not self.player.character or self.player.physical_surface.platform then
        if self.craft then self.craft.last_tick = game.tick end
        workers.park(self)
        if self.job or next(self.robots) then self:cancel_job(false) end
        self.entity.follow_target = nil
        self.entity.autopilot_destination = nil
        self:set_status({"companion-status.parked"})
        return
    end
    self.entity.minable_flag = false
    self.entity.destructible = false
    if self.flagged_for_equipment_changed then self:check_equipment() end
    if self.entity.surface ~= self.player.physical_surface then
        self:cancel_job(false)
        self:teleport(self.player.physical_position, self.player.physical_surface)
    end
    local distance = self:distance(self.player.physical_position)
    if distance > follow_range then self.away_since = self.away_since or game.tick
    else self.away_since = nil end
    if distance > abandon_job_distance or (self.away_since and game.tick - self.away_since >= task_timeout) then
        self:cancel_job(true)
        self:set_status({"companion-status.following"})
        self:return_to_player()
        -- A blocked path must not strand the companion; owner proximity wins after the lease expires.
        if distance > abandon_job_distance or game.tick - self.away_since >= task_timeout then
            self:teleport(self.player.physical_position, self.player.physical_surface)
            self.away_since = nil
        end
        return
    end
    local defending = self:try_to_find_targets()
    self.is_in_combat = false
    -- Native jobs from older saves return their cargo before explicit workers take over.
    if self.job or next(self.robots) then self:cancel_job(false) end
    if game.tick >= (self.next_search_tick or 0) then
        self.next_search_tick = game.tick + math.max(15, storage.companion_update_interval)
        self:search_for_nearby_work()
    end
    if not self.job then
        if defending then self:set_status({"companion-status.defending"}) end
        self:return_to_player()
    end
end

function Companion:try_to_find_work()
    if self.player.physical_surface.platform or not self.player.character then return end
    if self.job or self.is_in_combat or not self.can_construct or not self:player_wants_construction() then return end
    if self:distance(self.player.physical_position) > follow_range then return end
    local pd = script_data.player_data[self.player.index]
    local candidates
    candidates, self.tile_scan_cursor, self.repair_scan_cursor, self.job_scan_cursor = tasks.collect(
        self.player, self.entity, pd.recent_area, pd.recent_tick, self.tile_scan_cursor, self.repair_scan_cursor, self.job_scan_cursor)
    self.seen = self.seen or {}
    self.deferred = self.deferred or {}
    local seen = {}
    local eligible, missing, craftable, supplies = {}, nil, {}, {}
    local incoming, claims = self:incoming_items(), {}
    for _, companion in pairs(script_data.companions) do
        if companion.entity.valid and companion.entity.force == self.player.force then workers.claims(companion, claims) end
    end
    local function available(item)
        local key = item.name .. ":" .. item.quality
        if supplies[key] == nil then supplies[key] = self:available_items(item) end
        return supplies[key]
    end
    for _, task in ipairs(candidates) do
        seen[task.key] = self.seen[task.key] or game.tick
        task.age = math.min(30, (game.tick - seen[task.key]) / 60)
        if not claims[task.key] and game.tick >= (self.deferred[task.key] or 0) then
            for _, item in ipairs(task.alternatives or {}) do
                if available(item) >= item.count then task.item = item; break end
            end
            if not task.item or available(task.item) >= task.item.count then
                task.onboard = not task.item or self:get_inventory().get_item_count(task.item) >= task.item.count
                eligible[#eligible + 1] = task
            else
                missing = missing or task.item
                if task.kind == "build" or task.kind == "upgrade" then
                    local key = task.item.name .. ":" .. task.item.quality
                    if (incoming[key] or 0) >= task.item.count then incoming[key] = incoming[key] - task.item.count
                    else craftable[#craftable + 1] = task end
                end
            end
        end
    end
    self.seen = seen
    for key, deadline in pairs(self.deferred) do
        if not seen[key] or deadline <= game.tick then self.deferred[key] = nil end
    end
    table.sort(eligible, tasks.less)
    self.managers = self.managers or {}
    local assigned_operations = {}
    for _, first in ipairs(eligible) do
        if #self.managers >= 6 then break end
        if not assigned_operations[first.key] and (not first.item or available(first.item) >= first.item.count) then
            local batch, required = {}, {}
            for _, task in ipairs(eligible) do
                if not assigned_operations[task.key] and task.priority == first.priority and #batch < 32
                    and tasks.distance(first.entity.position, task.entity.position) <= 12 then
                    local item = task.item
                    local key = item and (item.name .. ":" .. item.quality)
                    local count = item and ((required[key] and required[key].count or 0) + item.count)
                    if not item or available(item) >= count then
                        batch[#batch + 1] = task
                        if item then required[key] = {name = item.name, quality = item.quality, count = count} end
                    end
                end
            end
            if #batch > 0 then
                local slots = #batch
                for _, item in pairs(required) do slots = slots + math.ceil(item.count / prototypes.item[item.name].stack_size) end
                local inventory = game.create_inventory(slots)
                local supplied = true
                for _, item in pairs(required) do
                    if self:ensure_items(item) then transfer_item(item, self:get_inventory(), inventory) end
                    if inventory.get_item_count(item) ~= item.count then supplied = false end
                end
                if supplied then
                    local worker = workers.spawn(self, "companion-task-manager", inventory)
                    worker.tasks, worker.started = batch, game.tick
                    self.managers[#self.managers + 1] = worker
                    for key, item in pairs(required) do supplies[key] = available(item) - item.count end
                    for _, task in ipairs(batch) do assigned_operations[task.key] = true end
                elseif workers.return_inventory(self, inventory) then inventory.destroy()
                else self.managers[#self.managers + 1] = workers.spawn(self, "companion-task-manager", inventory) end
            end
        end
    end
    for _, task in ipairs(craftable) do task.onboard = false end
    table.sort(craftable, tasks.less)
    local assigned, failed_crafts = {}, {}
    local recipes = {}
    local capacity = crafting_capacity(self.player, pd.stats.planet_upgrades)
    for _, task in ipairs(craftable) do
        if #(self.crafters or {}) >= capacity then break end
        -- A failed single-item plan also rules out every larger batch of that item.
        if not assigned[task.key] and not failed_crafts[task.item.name .. ":" .. task.item.quality .. ":1"] then
            local incoming_key = task.item.name .. ":" .. task.item.quality
            if (incoming[incoming_key] or 0) >= task.item.count then
                incoming[incoming_key] = incoming[incoming_key] - task.item.count
                assigned[task.key] = true
            else
                local batch, count = {task}, task.item.count
                for _, other in ipairs(craftable) do
                    if other ~= task and not assigned[other.key] and other.priority == task.priority
                        and other.item.name == task.item.name and other.item.quality == task.item.quality
                        and count + other.item.count <= 8 and tasks.distance(other.entity.position, task.entity.position) <= 8 then
                        batch[#batch + 1], count = other, count + other.item.count
                    end
                end
                while #batch > 0 do
                    local keys = {}
                    for _, target in ipairs(batch) do keys[target.key] = true end
                    local attempt = task.item.name .. ":" .. task.item.quality .. ":" .. count
                    if not failed_crafts[attempt] and self:try_to_craft({name = task.item.name, quality = task.item.quality, count = count}, keys, recipes, batch) then
                        for key in pairs(keys) do assigned[key] = true end
                        local craft = self.crafters[#self.crafters].craft
                        for name, amount in pairs(craft.plan.outputs) do
                            local key = name .. ":normal"
                            incoming[key] = (incoming[key] or 0) + math.max(0, amount - (name == craft.item and count or 0))
                        end
                        break
                    end
                    failed_crafts[attempt] = true
                    count = count - batch[#batch].item.count
                    batch[#batch] = nil
                end
            end
        end
    end
    if #self.managers > 0 or #(self.crafters or {}) > 0 then self:set_active()
    else self:set_status(missing and {"companion-status.missing", prototypes.item[missing.name].localised_name}
        or {"companion-status.following"}) end

end

local check_job_search = function(event)
    local interval = math.min(storage.companion_update_interval, 5)
    -- Inactive companions still check owner threats before considering construction.
    for _, pd in pairs(script_data.player_data) do
        for unit in pairs(pd.companions) do
            local companion = get_companion(unit)
            if companion and not companion.active and unit % interval == event.tick % interval then companion:update() end
        end
    end
end

local update_active_companions = function(event)
    local mod = event.tick % math.min(storage.companion_update_interval, 5)
    local list = script_data.active_companions[mod]
    if not list then return end
    for unit_number, bool in pairs (list) do
        local companion = get_companion(unit_number)
        if companion then
            companion:update()
        end
    end
end

local check_follow_update = function(event)
    if not next(script_data.player_data) then return end
    local players = game.players
    for player_index, player_data in pairs(script_data.player_data) do
        local player = players[player_index]
        if player.connected then
            adjust_follow_behavior(player)
        end
    end
end

local function check_and_restore_construction_bots()
    for _, companion in pairs(script_data.companions) do
        if companion.entity.valid then companion:set_robot_stack() end
    end
end

local function check_inactive_idle_chatter(event)
    if not next(script_data.companions) then return end
    for unit_number, comp in pairs(script_data.companions) do
        if comp and comp.entity and comp.entity.valid and not comp.active then
            if not (comp.is_in_combat or comp.is_busy_for_construction) then
                local delay = settings.get_player_settings(comp.player)["companion-idle-chatter-delay"].value
                local minimum = math.max(1, math.floor(delay * 0.1))
                local maximum = math.ceil(delay)

                if not comp.next_idle_line_tick then
                    comp.next_idle_line_tick = event.tick + 60 * math.random(minimum, maximum)
                elseif event.tick >= comp.next_idle_line_tick then
                    comp:say_random("idle-line")
                    comp.next_idle_line_tick = event.tick + 60 * math.random(minimum, maximum)
                end
            else
                comp.next_idle_line_tick = nil
            end
        end
    end
end

local function update_combat_robots()
    for player_index, pd in pairs(script_data.player_data) do
        local player = game.get_player(player_index)
        for id, robot in pairs(pd.combat_robots or {}) do
            if not robot.valid or not player.connected or not player.character
                or player.physical_surface.platform or robot.surface ~= player.physical_surface
                or not player.is_shortcut_toggled("companion-attack-toggle") then
                if robot.valid then robot.destroy() end
                pd.combat_robots[id] = nil
                if pd.combat_sources then pd.combat_sources[id] = nil end
                if pd.combat_slots then pd.combat_slots[id] = nil end
            else
                local slot = pd.combat_slots and pd.combat_slots[id]
                if not slot then robot.destroy() -- Retire the previous orbiting swarm in development saves.
                else
                    -- Stable, balanced guard positions. No native steering or five-tick jumps.
                    local angle = (slot.index - 1) * math.pi * 2 / slot.count - math.pi / 2
                    local owner, pos = player.physical_position, robot.position
                    local dx, dy = owner.x + math.cos(angle) * 3 - pos.x,
                        owner.y - 1.5 + math.sin(angle) * 2 - pos.y
                    local distance = math.sqrt(dx * dx + dy * dy)
                    if distance > 0.01 then
                        local heading = math.atan2(dx, -dy) / (2 * math.pi) % 1
                        local turn = (heading - robot.orientation + 0.5) % 1 - 0.5
                        robot.orientation = (robot.orientation + math.max(-0.02, math.min(0.02, turn * 0.25))) % 1
                        local step = math.min(1, math.min(0.09, 0.09 / distance)
                            * settings.global["companion-mini-drone-speed"].value)
                        robot.teleport({pos.x + dx * step, pos.y + dy * step})
                    end
                    local source = get_companion(pd.combat_sources[id])
                    visuals.update_combat(robot, source and source.entity.color or player.color, slot)
                end
            end
        end
    end
end

local on_tick = function(event)
    if event.tick % 60 == 0 then
        for _, player in pairs(game.connected_players) do
            ensure_player_companions(player)
            local old_queue = player.gui.screen.companion_crafting_queue
            if old_queue then old_queue.destroy() end
        end
    end
    for _, companion in pairs(script_data.companions) do
        if companion.entity.valid then companion:charge() end
    end
    update_combat_robots()
    update_active_companions(event) -- must run every tick
    check_job_search(event)
    for _, companion in pairs(script_data.companions) do
        if companion.entity.valid then
            if companion.player.connected and companion.player.character and not companion.player.physical_surface.platform then
                companion:update_crafting()
                workers.update_managers(companion)
            end
            companion:update_flight()
            visuals.update(companion)
            workers.visuals(companion)
        end
    end
	if event.tick % math.min(storage.companion_update_interval, 5) == 0 then
    -- Safety checks stay bounded even when expensive work searches are slowed down.
        check_follow_update(event)
        check_and_restore_construction_bots()
        check_inactive_idle_chatter(event)
    end
end

--------------------------- Secondary Utilities ---------------------------

local on_spider_command_completed = function(event)
    local spider = event.vehicle
    local companion = get_companion(spider.unit_number)
    if not companion then return end
    companion:on_spider_command_completed()
end

function Companion:on_spider_command_completed()
    self.moving_to_destination = nil
    -- The update loop revalidates the entity and supplies, rather than retrying a stale position.
end

local companion_attack_trigger = function(event)

    local source_entity = event.source_entity
    if not (source_entity and source_entity.valid) then
        return
    end

    local target_entity = event.target_entity
    if not (target_entity and target_entity.valid) then
        return
    end

    local companion = get_companion(source_entity.unit_number)
    if companion then
        companion:attack(target_entity, set_companion_stats(companion.player).attack_count)
    end
end

local companion_robot_spawned_trigger = function(event)
    local robot = event.target_entity or event.source_entity
    if not (robot and robot.valid) then return end
    if robot.type ~= "construction-robot" and robot.type ~= "logistic-robot" then return end

    local network = robot.logistic_network
    if not network or not network.cells or not network.cells[1] then return end
    local owner = network.cells[1].owner
    if not (owner and owner.valid and owner.name == "companion") then return end

    local companion = get_companion(owner.unit_number)
    if companion then
        companion:robot_spawned(robot)
    end
end

--[[effect_id :: string: The effect_id specified in the trigger effect.
surface_index :: uint: The surface the effect happened on.
source_position :: Position (optional)
source_entity :: LuaEntity (optional)
target_position :: Position (optional)
target_entity :: LuaEntity (optional)]]

local function escort_attack(event)
    local robot, target = event.source_entity, event.target_entity
    if not robot or not robot.valid or not target or not target.valid then return end
    local owner = robot.combat_robot_owner
    local player = owner and owner.valid and owner.player
    local pd = player and script_data.player_data[player.index]
    local source = pd and pd.combat_sources and get_companion(pd.combat_sources[robot.unit_number])
    if not source or not source.entity.valid then return end
    local banks = 0
    for _, equipment in pairs(source.entity.grid.equipment) do
        if equipment.name == "companion-defense-equipment" then banks = banks + 1 end
    end
    local power = (pd.stats or set_companion_stats(player)).attack_count * banks
    local squad = math.min(4, math.ceil(power / 4))
    if squad == 0 then return end
    robot.surface.create_entity{name = "companion-combat-beam", position = robot.position,
        source = robot, target = target, force = robot.force, duration = 12}
    target.damage(5 * power / squad * (1 + robot.force.get_ammo_damage_modifier("laser")), robot.force, "laser", robot)
end

local on_script_trigger_effect = function(event)
    local id = event.effect_id
    if id == "companion-escort-attack" then escort_attack(event); return end
    if id == "companion-attack" then
        companion_attack_trigger(event)
        return
    end

    if id == "companion-robot-spawned" then
        companion_robot_spawned_trigger(event)
    end
end

local on_player_placed_equipment = function(event)

    local player = game.get_player(event.player_index)
    --if player.opened_gui_type ~= defines.gui_type.entity then return end

    local opened = player.opened
    if not (opened and opened.valid and opened.prototype.name == "companion") then return end

    local companion = get_companion(opened.unit_number)
    if not companion then return end

    companion:on_player_placed_equipment(event)

end

local on_player_removed_equipment = function(event)
    local player = game.get_player(event.player_index)
    if player.opened_gui_type ~= defines.gui_type.entity then return end

    local opened = player.opened
    if not (opened and opened.valid and opened.prototype.name == "companion") then return end

    local companion = get_companion(opened.unit_number)
    if not companion then return end

    companion:on_player_removed_equipment(event)

end

local on_entity_settings_pasted = function(event)

    local entity = event.destination
    if not (entity and entity.valid) then return end

    local companion = get_companion(entity.unit_number)
    if not companion then return end

    companion:set_active()

end

local on_player_changed_surface = function(event)
    local player_data = script_data.player_data[event.player_index]
    if not player_data then return end

    local player = game.get_player(event.player_index)
    if not player.character then
        --For the space exploration satellite viewer thing...
        --If there is no character, lets just not go with the player.
        return
    end
    local surface = player.physical_surface
    local position = player.physical_position
    player_data.next_combat_deployment = nil
    recall_fighting_robots(player)

    for unit_number, bool in pairs (player_data.companions) do
        local companion = get_companion(unit_number)
        if companion then
            companion:cancel_job(false)
            if surface.platform then
                companion.entity.follow_target = nil
                companion.entity.autopilot_destination = nil
                companion:set_status({"companion-status.parked"})
            else companion:teleport(position, surface) end
        end
    end

end

local on_player_left_game = function(event)
    local pd = script_data.player_data[event.player_index]
    if not pd then return end
    for unit in pairs(pd.companions) do
        local companion = get_companion(unit)
        if companion then
            companion:cancel_job(false)
            companion.entity.follow_target = nil
            companion.entity.autopilot_destination = nil
        end
    end
end

function reschedule_companions(allow_prototype_access)
    script_data.active_companions = {}
    for k, companion in pairs(script_data.companions) do
        if companion.entity and companion.entity.valid then
            companion.moving_to_destination = nil
            companion.current_job_target = nil
            if allow_prototype_access then
                companion:set_active()
            else
                companion.active = false
            end
        else
            script_data.companions[k] = nil
        end
    end
end

local on_player_joined_game = function(event)
    local player_data = script_data.player_data[event.player_index]
    if not player_data then return end

    local player = game.get_player(event.player_index)
    local surface = player.physical_surface
    local position = player.physical_position
    player_data.next_combat_deployment = nil
    recall_fighting_robots(player)

    for unit_number, bool in pairs (player_data.companions) do
        local companion = get_companion(unit_number)
        if companion then
            if surface.platform or not player.character then
                companion:cancel_job(false)
                companion.entity.follow_target = nil
                companion.entity.autopilot_destination = nil
                companion:set_status({"companion-status.parked"})
            else companion:teleport(position, surface) end
        end
    end
	set_companion_stats(player)
    reschedule_companions(true)
    adjust_follow_behavior(player)
end

local on_player_changed_force = function(event)
    local player_data = script_data.player_data[event.player_index]
    if not player_data then return end

    local player = game.get_player(event.player_index)
    local force = player.force
    recall_fighting_robots(player)
    for unit_number, bool in pairs (player_data.companions) do
        local companion = get_companion(unit_number)
        if companion then
            companion:change_force(force)
        end
    end
end

local on_player_driving_changed_state = function(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    if not player.vehicle then return end

    if player.vehicle.name == "companion" then
        player.driving = false
    end

    adjust_follow_behavior(player)

end

local rebukes =
-- picks one at random if you try to use a spidertron remote on the drone
{
    "You're not the boss of me",
    "Get lost",
    "Not me pal",
    "Maybe later, I mean never.",
    "Go bother someone else",
    "I do my own thing",
    "lol as if...",
    "What are you, nuts?",
    "I ain't goin' in there!",
    "lol. lmao, even",
    "Who do you think you are?",
    "Do I look like a friggin spider to you?",
    "What do I look like, a spidertron?",
    "That's really not necessary.",
    "Oh don't worry, I can take care of myself.",
    "You don't need to do that.",
    "Don't do that.",
    "No.",
    "Nope.",
    "Nuh uh.",
    "Not happening.",
    "In your dreams"
}

local on_player_used_spider_remote = function(event)
    local vehicle = event.vehicle
    if not (vehicle and vehicle.valid) then return end
    local companion = get_companion(vehicle.unit_number)
    if not companion then return end

    companion:say(rebukes[math.random(#rebukes)])
    companion.entity.follow_target = nil
    companion.entity.autopilot_destination = nil

end

local on_player_mined_entity = function(event)
    if event.entity and event.entity.valid and event.entity.name == "companion" then
        local player = game.get_player(event.player_index)
        player.remove_item{name = "companion-construction-robot", count = 1000}
    end
end

recall_fighting_robots = function(player)
    local player_data = script_data.player_data[player.index]
    if not player_data then return end
    player_data.next_combat_deployment = nil
    for id, robot in pairs(player_data.combat_robots or {}) do
        if robot.valid then robot.destroy() end
        player_data.combat_robots[id] = nil
    end
    player_data.combat_sources, player_data.combat_slots = {}, {}
end

local recall_constructing_robots = function(player)
    local pd = script_data.player_data[player.index]
    if not pd then return end
    for unit in pairs(pd.companions) do
        local companion = get_companion(unit)
        if companion then companion:cancel_job(false); companion:return_to_player() end
    end
end

local clear_recent_area = function(player)
    local pd = script_data.player_data[player.index]
    if pd then pd.recent_area, pd.recent_tick = nil, nil end
end

local on_lua_shortcut = function(event)
    local player = game.get_player(event.player_index)
    local name = event.prototype_name
    if name == "companion-attack-toggle" then
        player.set_shortcut_toggled(name, not player.is_shortcut_toggled(name))
        recall_fighting_robots(player)
    end
	if name == "companion-construction-toggle" then
		player.set_shortcut_toggled(name, not player.is_shortcut_toggled(name))
		recall_constructing_robots(player)
		clear_recent_area(player)
		local player_data = script_data.player_data[player.index]
		if player_data then
			for unit_number in pairs(player_data.companions) do
				local companion = script_data.companions[unit_number]
				if companion then
					companion:set_robot_stack()
				end
			end
		end
	end
end

script.on_event("companion-attack-hotkey", function(event)
    local player = game.get_player(event.player_index)
    if player then
        player.set_shortcut_toggled("companion-attack-toggle", not player.is_shortcut_toggled("companion-attack-toggle"))
        recall_fighting_robots(player)
    end
end)

script.on_event("companion-construction-hotkey", function(event)
    local player = game.get_player(event.player_index)
    if player then
        player.set_shortcut_toggled("companion-construction-toggle", not player.is_shortcut_toggled("companion-construction-toggle"))
        recall_constructing_robots(player)
        clear_recent_area(player)
        local player_data = script_data.player_data[player.index]
        if player_data then
            for unit_number in pairs(player_data.companions) do
                local companion = script_data.companions[unit_number]
                if companion then
                    companion:set_robot_stack()
                end
            end
        end
    end
end)

script.on_event("companion-force-search", function(event)
    local player = game.get_player(event.player_index)
    if not player or not player.connected then return end

    local pd = script_data.player_data[player.index]
    if not pd then return end

    for unit_number in pairs(pd.companions) do
        local c = script_data.companions[unit_number]
        if c and c.can_construct and c:player_wants_construction() then
            c:search_for_nearby_work()
            c:search_for_nearby_targets()
            if c.debug_report_state then
                c:debug_report_state("force-search")
            end
        end
    end
end)

local remember_recent_area = function(player_index, player_pos, area)
    local pd = script_data.player_data[player_index]
    if pd then pd.recent_area, pd.recent_tick = area, game.tick end
end

local on_player_deconstructed_area = function(event)
    local player = game.get_player(event.player_index)
    if not player.is_shortcut_toggled("companion-construction-toggle") then return end
    remember_recent_area(event.player_index, player.physical_position, event.area)
end

local get_blueprint_area = function(player, offset)
    local record = player.cursor_record
    if record and record.type == "blueprint-book" then record = record.get_selected_record(player) end
    local radius = 24
    if record and record.type == "blueprint" then
        for _, entity in pairs(record.get_blueprint_entities() or {}) do
            radius = math.max(radius, math.abs(entity.position.x), math.abs(entity.position.y))
        end
    end
    -- A symmetric square covers rotations and flips without copying the blueprint geometry.
    return {left_top = {x = offset.x - radius, y = offset.y - radius},
        right_bottom = {x = offset.x + radius, y = offset.y + radius}}
end

local on_pre_build = function(event)
    local player = game.get_player(event.player_index)

    if not (player.is_cursor_blueprint()) then return end

    if not player.is_shortcut_toggled("companion-construction-toggle") then
        return
    end

    local area = get_blueprint_area(player, event.position)
    remember_recent_area(event.player_index, player.physical_position, area)

end

-- Spawns a fresh, fully-equipped companion drone for the given player.
-- Extracted so it can be triggered both on player creation and via the
-- /companion command (useful when the mod is added to a server mid-game and
-- an already-existing player never fired on_player_created).
local function spawn_companion_for_player(player)
    if not (player and player.valid) then return end

    local surface = player.physical_surface.platform and game.surfaces.nauvis or player.physical_surface
    local position = player.physical_surface.platform and player.force.get_spawn_position(surface) or player.physical_position
    local stats = set_companion_stats(player)
    local pd = script_data.player_data[player.index]
    local first = not pd or not next(pd.companions)
	local entity = surface.create_entity
	{
	    name = "companion",
	    position = {position.x + 2, position.y},
	    force = player.force
	}
	entity.color = player.color
	local grid = entity.grid
	grid.put{name = "companion-reactor-equipment"}
	if mode ~= 1 and mode ~= 3 then
		grid.put{name = "companion-defense-equipment"}
		grid.put{name = "companion-defense-equipment"}
		grid.put{name = "companion-roboport-mk" .. math.min(3, 2 + stats.planet_upgrades)}
		grid.put{name = "companion-shield-mk" .. math.min(3, 2 + stats.planet_upgrades)}
        player.set_shortcut_available("companion-attack-toggle", true)
        if first then player.set_shortcut_toggled("companion-attack-toggle", true) end
	else
		grid.put{name = "companion-defense-equipment"}
		grid.put{name = "companion-roboport-mk0"}
		grid.put{name = "companion-shield-mk0"}
        player.set_shortcut_available("companion-attack-toggle", true)
        if first then player.set_shortcut_toggled("companion-attack-toggle", false) end
	end
	player.set_shortcut_available("companion-construction-toggle", true)
	if first then player.set_shortcut_toggled("companion-construction-toggle", true) end
	return Companion.new(entity, player)
end

ensure_player_companions = function(player)
    if not player.valid then return end
    local pd = script_data.player_data[player.index]
    local count = pd and table_size(pd.companions) or 0
    local stats = set_companion_stats(player)
    for i = count + 1, stats.max_companions do spawn_companion_for_player(player) end
end

local on_player_created = function(event)
    ensure_player_companions(game.get_player(event.player_index))
end

local function purge_illegal_companion_bots(player)
    if not (player and player.valid) then return end
    local cs = player.cursor_stack
    if cs and cs.valid_for_read and cs.name == "companion-construction-robot" then
        cs.clear()
    end
    local removed = player.remove_item{name = "companion-construction-robot", count = 1000000}
    if removed > 0 then
        local opened = player.opened
        if opened and opened.valid and opened.name == "companion" then
            local c = get_companion(opened.unit_number)
            if c then c:set_robot_stack() end
        end
    end
end

local on_player_main_inventory_changed = function(event)
    local player = game.get_player(event.player_index)
    purge_illegal_companion_bots(player)
end

local on_player_fast_transferred = function(event)
    local player = game.get_player(event.player_index)
    purge_illegal_companion_bots(player)
end

local on_player_cursor_stack_changed = function(event)
    local player = game.get_player(event.player_index)
    purge_illegal_companion_bots(player)
end

local function swap_equipment(grid, input, output) -- equipment literal names as strings, matches any arbitrary names. 
	if not grid or type(input) ~= "string" or type(output) ~= "string" then return nil end
	local target_positions = {} -- where on the grid each matching equipment is located
	for _, equipment in pairs(grid.equipment) do -- find the position of each equipment
		if equipment.name == input then 
			table.insert(target_positions, equipment.position)
		end 
	end
	for i = 1, #target_positions do -- remove "input" and replace with "output" equipment
		grid.take{position = target_positions[i]}
		grid.put{name = output, position = target_positions[i]}
	end
end

local function apply_researched_equipment_upgrades(player, grid)
    if not (player and grid) then return end
    ensure_companion_upgrades()
    local techs = player.force.technologies
    for _ = 1, 3 do
        for tech, entries in pairs(storage.companion_upgrades) do
            local up = entries and entries[1]
            if up and type(up.value) == "string" then
                local t = techs[tech]
                if t and t.researched then
                    swap_equipment(grid, up.stat, up.value)
                end
            end
        end
    end
end

function Companion:get_random_localised(key)
    -- Looks in __root__/locale/en/locale.cfg and reads the first line in KEY, then uses that value as it's upper bounds for randomly picking between 1 and KEY. 
	-- In the locale file, the first line should always be the exact number of lines in that section
	-- too low (i.e. lines were added) won't do anything except not show the added lines but too high will just return the key itself
    local count = storage.dialogue_counts and storage.dialogue_counts[key]
    if not count then
        local translated = self.player.request_translation({key .. ".0"})
        count = tonumber(translated) or 1
        storage.dialogue_counts = storage.dialogue_counts or {}
        storage.dialogue_counts[key] = count
    end
    local index = math.random(1, count)
    return {key .. "." .. index}
end

function Companion:say_random(key) 
    -- this function used to do more than simply call that ^ function, just haven't bothered removing it from where it's spread
    self:say(self:get_random_localised(key))
end

local function reseed_defaults()
    storage.companion_upgrades = nil
    ensure_companion_upgrades()
    for _, p in pairs(game.players) do
        set_companion_stats(p)
    end
    if reschedule_companions then reschedule_companions(true) end
    game.print("Companion defaults and upgrade table re-seeded.")
end

local function converge_equipment_to_researched(player, grid)
    if not (player and grid) then return end
    ensure_companion_upgrades()
    local techs = player.force.technologies

    for _ = 1, 3 do 
        local changed = false
        for tech, entries in pairs(storage.companion_upgrades or {}) do
            local t = techs[tech]
            local up = entries and entries[1]
            if t and t.researched and up and type(up.value) == "string" then
                if swap_equipment(grid, up.stat, up.value) then
                    changed = true
                end
            end
        end
        if not changed then break end
    end
end

local function reset_companions_for_player(player)
    local player_data = script_data.player_data and script_data.player_data[player.index]
    if not player_data or not next(player_data.companions) then
        player.print("No companion data found for this player.")
        return
    end

    local count = 0
    for unit_number in pairs(player_data.companions) do
        local companion = script_data.companions[unit_number]
        if companion then
            -- reset state
            companion:cancel_job(false)
            companion.is_busy_for_construction = false
            companion.is_in_combat = false
            companion.job_done_tick = nil
            companion.job_done_announced = false
            companion.out_of_energy = nil
            companion.moving_to_destination = nil
            companion.next_idle_line_tick = nil
            companion.test_idle_tick = nil
            companion.test_idle_fired = nil
            companion:clear_speed_sticker()
            companion:check_equipment()
            companion:charge()
            companion:set_active()
            set_companion_stats(player)
            adjust_follow_behavior(player)
            companion:debug_report_state("RESET")

            local grid = companion.entity.grid
            apply_researched_equipment_upgrades(player, grid)
            converge_equipment_to_researched(player, grid)

            count = count + 1
        end
    end

    game.print({"", "Reset ", count, " companions for ", player.name, "."})
end

local function on_entity_damaged(event)
    local ent = event.entity
    if not (ent and ent.valid) then return end
    if ent.name ~= "companion" then return end

    local c = get_companion(ent.unit_number)
    if not c then return end                                     -- uses your helper
    if c:player_wants_attack() then return end                    -- respect attack toggle
    if c.entity.surface ~= c.player.physical_surface then return end

    if c._last_escape_tick and (game.tick - c._last_escape_tick) < 30 then return end
    c._last_escape_tick = game.tick

    local src = (event.cause and event.cause.valid) and event.cause.position or nil
    c:escape_danger(src)                                          -- flee from cause, or to player if nil
end

local function on_research_finished(event)
    if not event.research then return end
    local up = storage.companion_upgrades and storage.companion_upgrades[event.research.name]
    for _, player in pairs(game.players) do
        if player.force == event.research.force then
            local stats = set_companion_stats(player)
            local pd = script_data.player_data[player.index]
            for unit in pairs(pd and pd.companions or {}) do
                local companion = get_companion(unit)
                if companion then
                    if up and type(up[1].value) == "string" then
                        swap_equipment(companion:get_grid(), up[1].stat, up[1].value)
                    end
                    -- Planet upgrades improve worker capacity and reach, within the owner leash.
                    local base_tier = (mode == 1 or mode == 3) and 0 or 2
                    local tier = math.min(3, base_tier + stats.planet_upgrades)
                    for old = 0, tier - 1 do
                        swap_equipment(companion:get_grid(), "companion-roboport-mk" .. old, "companion-roboport-mk" .. tier)
                        swap_equipment(companion:get_grid(), "companion-shield-mk" .. old, "companion-shield-mk" .. tier)
                    end
                    companion.flagged_for_equipment_changed = true
                end
            end
        end
    end
end

lib.events =
{
    [defines.events.on_built_entity]                  = on_built_entity,
    [defines.events.on_object_destroyed]              = on_entity_destroyed,
    [defines.events.on_tick]                          = on_tick,
    [defines.events.on_spider_command_completed]      = on_spider_command_completed,
    [defines.events.on_script_trigger_effect]         = on_script_trigger_effect,
    [defines.events.on_entity_settings_pasted]        = on_entity_settings_pasted,

    [defines.events.on_player_placed_equipment]       = on_player_placed_equipment,
    [defines.events.on_player_removed_equipment]      = on_player_removed_equipment,
    [defines.events.on_player_main_inventory_changed] = on_player_main_inventory_changed,
    [defines.events.on_player_fast_transferred]       = on_player_fast_transferred,
    [defines.events.on_player_cursor_stack_changed]   = on_player_cursor_stack_changed,

    [defines.events.on_player_changed_surface]        = on_player_changed_surface,
    [defines.events.on_player_left_game]              = on_player_left_game,
    [defines.events.on_player_joined_game]            = on_player_joined_game,
    [defines.events.on_player_created]                = on_player_created,
    [defines.events.on_player_changed_force]          = on_player_changed_force,
    [defines.events.on_player_driving_changed_state]  = on_player_driving_changed_state,
    [defines.events.on_player_used_spidertron_remote] = on_player_used_spider_remote,

    [defines.events.on_player_mined_entity]           = on_player_mined_entity,
    [defines.events.on_pre_player_mined_item]         = on_pre_player_mined_item,
    [defines.events.on_lua_shortcut]                  = on_lua_shortcut,
    [defines.events.on_player_deconstructed_area]     = on_player_deconstructed_area,
    [defines.events.on_pre_build]                     = on_pre_build,
	[defines.events.on_research_finished]             = on_research_finished,
    [defines.events.on_entity_damaged]                = on_entity_damaged,
}

---------------------------- Migrations ----------------------------------

local function migrate_companions()
    for unit_number, companion in pairs(script_data.companions) do
        companion.last_idle_line_tick = companion.last_idle_line_tick or game.tick
        companion.next_forced_idle_tick = companion.next_forced_idle_tick or (game.tick + 1800)
        companion.job_done_tick = companion.job_done_tick or nil
        companion.job_done_announced = companion.job_done_announced or false
    end
end

local string = string
local table = table

local version_pattern = "%d+"
local version_format = "%02d"

function format_version(version, format)
-- from FLIB
  if version then
    format = format or version_format
    local tbl = {}
    for v in string.gmatch(version, version_pattern) do
      tbl[#tbl + 1] = string.format(format, v)
    end
    if next(tbl) then
      return table.concat(tbl, ".")
    end
  end
  return nil
end

function is_newer_version(old_version, current_version, format)
-- from FLIB
  local v1 = format_version(old_version, format)
  local v2 = format_version(current_version, format)
  if v1 and v2 then
    if v2 > v1 then
      return true
    end
    return false
  end
  return nil
end

function run(old_version, migrations, format, ...)
-- from FLIB
  local migrate = false
  for version, func in pairs(migrations) do
    if migrate or is_newer_version(old_version, version, format) then
      migrate = true
      func(...)
    end
  end
end

function on_config_changed(e, migrations, mod_name, ...) 
-- from FLIB
-- only runs if THIS mod is what changed, rather than if ANY mod changed like vanilla on_configuration_changed()
  local changes = e.mod_changes[mod_name or script.mod_name]
  local old_version = changes and changes.old_version
  if old_version then
    if migrations then
      run(old_version, migrations, nil, ...)
    end
    return true
  end
  return false
end

local function create_popup(player, message)
  if player.gui.center.companion_popup then
    player.gui.center.companion_popup.destroy()
  end
  local frame = player.gui.center.add{
    type = "frame",
    name = "companion_popup",
    caption = "Entourage — Companion Crew",
    direction = "vertical"
  }
  local textbox = frame.add{
    type = "text-box",
    text = message,
    read_only = true,
    word_wrap = true,
  }
  textbox.style.width = 280
  textbox.style.height = 220
  textbox.style.top_padding = 3
  textbox.style.bottom_padding = 3
  textbox.style.left_padding = 1
  textbox.style.right_padding = 5
  textbox.style.font = "default-bold"
  local ok_button = frame.add{
    type = "button",
    name = "companion_popup_ok",
    caption = "OK"
  }
  ok_button.style.width = 280
  ok_button.style.top_margin = 10
end

local function on_gui_click(event)
  local player = game.players[event.player_index]
  if event.element and event.element.name == "companion_popup_ok" then
    if player.gui.center.companion_popup then
      player.gui.center.companion_popup.destroy()
    end
  end
end

local function show_update_popup()
    for _, player in pairs(game.players) do
        set_companion_stats(player)
        create_popup(player, [[
            MAJOR MOD UPDATE DETECTED!

            Please check the changelog and/or
            the mod description to see all the 
            new changes, or at least check 
            the settings to see what's new.

            This popup will never show again
            (once you save at least)
        ]])
    end
end

local migrations = {
    ["3.0.0"] = function()
        for _, player in pairs(game.players) do
            reset_companions_for_player(player)
        end
        show_update_popup()
    end,
}

script.on_event(defines.events.on_gui_click, on_gui_click)

script.on_configuration_changed(function(e)
    bind_storage()
    storage.companion_update_interval = settings.startup["set-update-interval"].value or 5
    reseed_defaults()
    for player_index, player_data in pairs (script_data.player_data) do

        if player_data.last_search_offset then
            player_data.last_job_search_offset = player_data.last_search_offset
            player_data.last_attack_search_offset = player_data.last_search_offset
            player_data.last_search_offset = nil
        end

        local player = game.get_player(player_index)
        if player then
            local gui = player.gui.relative
            if gui.companion_gui then
                gui.companion_gui.destroy()
            end

            if not player.is_shortcut_available("companion-attack-toggle") then
                player.set_shortcut_available("companion-attack-toggle", true)
                if mode == 1 or mode == 3 then
                    player.set_shortcut_toggled("companion-attack-toggle", false)
                else
                    player.set_shortcut_toggled("companion-attack-toggle", true)
                end
            end

            if not player.is_shortcut_available("companion-construction-toggle") then
                player.set_shortcut_available("companion-construction-toggle", true)
                player.set_shortcut_toggled("companion-construction-toggle", true)
            end
        else
            script_data.player_data[player_index] = nil
        end

    end

    for k, companion in pairs (script_data.companions) do
        if companion.entity.valid and companion.player and companion.player.valid then
            companion.speed = companion.speed or 0
            companion:clear_passengers()
            companion.entity.minable_flag = false
            companion.entity.destructible = false
        elseif companion.player and companion.player.valid then
            companion:on_destroyed()
        else
            if companion.entity.valid then companion.entity.destroy() end
            script_data.companions[k] = nil
        end
    end
    for _, player in pairs(game.players) do ensure_player_companions(player) end

    if script_data.tick_updates then
        script_data.tick_updates = nil
    end

    script_data.specific_job_search_queue = nil
    script_data.search_schedule = nil

    reschedule_companions()
	migrate_companions()
	on_config_changed(e, migrations)
end)

lib.on_load = function()
    script_data = storage.companion or script_data
    for unit_number, companion in pairs(script_data.companions) do
        setmetatable(companion, Companion.metatable)
    end
end

----------------------------------- Commands and Remotes ------------------------------------

local jetpack_remote =
{
    on_character_swapped = function(event)
        local new_character = event.new_character
        if not (new_character and new_character.valid) then return end
        if new_character.player then
            adjust_follow_behavior(new_character.player)
        end
    end
}

script.on_event(defines.events.on_string_translated, function(event)
	local key = event.localised_string[1]
	if key and event.translated and key:match("^.+%.0$") then
		local base_key = key:match("^(.-)%.0$")
		storage.dialogue_counts = storage.dialogue_counts or {}
		storage.dialogue_counts[base_key] = tonumber(event.result) or 1
	end
end)

function Companion:debug_stats_state(prefix)
    local msg = string.format(
        "[%s] tick=%d unit=%s | speed=%s damage=%s range=%s count=%s",
        prefix or "",
        game.tick,
        tostring(storage.unit_number),
        tostring(storage.base_speed),
        tostring(storage.attack_count),
        tostring(storage.max_distance),
        tostring(storage.max_companions)
    )
    log(msg)
    self.player.print(msg)
end

function Companion:debug_report_state(prefix)
    local msg = string.format(
        "[%s] tick=%d unit=%s | wants=%s can_construct=%s surface_ok=%s cell=%s is_busy=%s robots=%d pos=(%.1f,%.1f) actv=%s itick=%s",
        prefix or "",
        game.tick,
        tostring(self.unit_number),
        tostring(self:player_wants_construction()),
        tostring(self.can_construct),
        tostring(self.entity.surface == self.player.physical_surface),
        tostring(self.entity.logistic_cell ~= nil),
        tostring(self:is_busy()),
        table_size(self.robots or {}),
        self.entity.position.x, self.entity.position.y,
        tostring(self.active),
        tostring(self.next_idle_line_tick)
    )
    log(msg)
    self.player.print(msg)
end

remote.add_interface("companion_speed", {
    set_factor = function(v)
        if type(v) == "number" and v > 0 then
            storage.companion_speed_factor = v
            for _, comp in pairs(script_data.companions) do
                if comp and comp.entity and comp.entity.valid then
                    comp._last_speed_factor = nil
                end
            end
        end
    end,
    get_factor = function() return storage.companion_speed_factor or 1.0 end,
})

remote.add_interface("companion_remote_for_jetpack", jetpack_remote)

commands.add_command("reschedule_companions", "If they get stuck or something", reschedule_companions)

commands.add_command("companion",
"Restore missing members of your researched permanent companion fleet.",
function(cmd)
    local player = cmd.player_index and game.get_player(cmd.player_index)
    if not player then return end

    local player_data = script_data.player_data and script_data.player_data[player.index]
    local current = player_data and table_size(player_data.companions) or 0
    local cap = set_companion_stats(player).max_companions
    if current >= cap then
        player.print({"", "You already have ", current, "/", cap,
            " companion(s). Research planet development or promethium to expand your fleet."})
        return
    end

    local companion = spawn_companion_for_player(player)
    if companion then
        player.print({"", "A companion drone has been assigned to you (", current + 1, "/", cap, ")."})
    end
end)

commands.add_command("reset_companions",
"Recall and reschedule your existing companions, preserving their identities and cargo.",
function(cmd)
    local player = game.get_player(cmd.player_index)
    if player then reset_companions_for_player(player) end
end)

--Various debug commands:
commands.add_command("debug_companion", 
"Debug companion state", 
function(cmd)
    if not debug_mode then game.print("You cannot use this command while Debug mode is disabled") return end 
    local player = game.get_player(cmd.player_index)
    if not player then return end
    local player_data = script_data.player_data[player.index]
    if not player_data then player.print("No player_data") return end
    for unit_number in pairs(player_data.companions) do
        local companion = script_data.companions[unit_number]
        if companion then
            companion:debug_report_state("console")
            companion:debug_stats_state("stats")
        end
    end
end)

commands.add_command("swap_equipment", 
"Takes any input equipment name and replaces it with output name. Takes two arguments.", 
function(cmd)
    if not debug_mode then game.print("You cannot use this command while Debug mode is disabled") return end
	local errmsg = "Usage: /swap_equipment <old-equipment-literal-name> <new-equipment-literal-name>"
    local player = game.get_player(cmd.player_index)
    local companion = script_data.companions[next(script_data.player_data[player.index].companions)]
    local grid = companion:get_grid()
	if not cmd.parameter then
		game.print(errmsg)
		return
	end
	local input, output = cmd.parameter:match("^(%S+)%s+(%S+)$") 
	-- splits the combined string of "old_equipment_name new_equipment_name" and separates them where the whitespace is
	-- then assigns them to input and output respectively.
	if not input or not output or type(input) ~= "string" or type(output) ~= "string" then
		game.print(errmsg)
		return
	end
	swap_equipment(grid, input, output)
end)

commands.add_command("companion_reseed_defaults",
"Refreshes companion stats in storage table.",
function(cmd)
    if not debug_mode then game.print("You cannot use this command while Debug mode is disabled") return end
    local player = game.get_player(cmd.player_index)
    if player then reseed_defaults(player) end
end)

commands.add_command("companion_check_mode",
"",
function(cmd)
    game.print(tostring(mode == 1 or mode == 3))
    game.print(tostring(mode))
end)

commands.add_command("companion_speed_factor",
"Set companion speed multiplier (>0). Decimals between 0 and 1 will slow the drone.",
function(cmd)
    if not debug_mode then game.print("You cannot use this command while Debug mode is disabled") return end
    local v = tonumber(cmd.parameter)
    if v and v > 0 then
        remote.call("companion_speed", "set_factor", v)
        game.print({"", "[Companion] speed factor set to ", v})
    else
        local cur = remote.call("companion_speed", "get_factor")
        game.print({"", "[Companion] current speed factor = ", cur, " (usage: /companion_speed_factor <number>)"})
    end
end)

return lib