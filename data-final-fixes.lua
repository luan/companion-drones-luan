-- Generate progression from planet prototypes, so modded planets participate too.
local planet_science = {
    vulcanus = "metallurgic-science-pack", fulgora = "electromagnetic-science-pack",
    gleba = "agricultural-science-pack", aquilo = "cryogenic-science-pack",
}
local core_science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack", "space-science-pack"}
local crafting_science = {}
for _, pack in ipairs(core_science) do
    if data.raw.item[pack] then crafting_science[#crafting_science + 1] = {pack, 1} end
end
data:extend{{type = "technology", name = "companion-crafting-speed-1",
    icon = "__companion-drones-luan__/sprites/drone-icon.png", icon_size = 200,
    localised_name = {"technology-name.companion-crafting-speed"},
    localised_description = {"technology-description.companion-crafting-speed"},
    prerequisites = data.raw.technology["utility-science-pack"] and {"utility-science-pack"} or {},
    effects = {}, max_level = "infinite", upgrade = true,
    unit = {count_formula = "1000*2^(L-1)", time = 60, ingredients = crafting_science},
}}
local planet_count = 0
for name, planet in pairs(data.raw.planet or {}) do
    if name ~= "nauvis" then
        planet_count = planet_count + 1
        local prerequisites, ingredients = {}, {}
        local discoveries = {}
        for tech_name, technology in pairs(data.raw.technology) do
            for _, effect in pairs(technology.effects or {}) do
                if effect.type == "unlock-space-location" and effect.space_location == name then
                    discoveries[#discoveries + 1] = tech_name
                end
            end
        end
        table.sort(discoveries)
        if discoveries[1] then prerequisites[1] = discoveries[1] end
        local packs = {}
        for _, pack in ipairs(core_science) do
            if data.raw.item[pack] then packs[pack] = true end
        end
        -- Modded discovery packs are retained; mods need no companion-specific integration.
        local discovery = discoveries[1] and data.raw.technology[discoveries[1]]
        for _, ingredient in pairs(discovery and discovery.unit and discovery.unit.ingredients or {}) do
            packs[ingredient[1]] = true
        end
        local pack = planet_science[name] or (name .. "-science-pack")
        if data.raw.item[pack] then packs[pack] = true end
        for pack_name in pairs(packs) do ingredients[#ingredients + 1] = {pack_name, 1} end
        table.sort(ingredients, function(a, b) return a[1] < b[1] end)
        data:extend{{type = "technology", name = "companion-planet-" .. name,
            icon = "__companion-drones-luan__/sprites/drone-icon.png", icon_size = 200,
            localised_name = {"technology-name.companion-planet", planet.localised_name or {"space-location-name." .. name}},
            localised_description = {"technology-description.companion-planet"},
            prerequisites = prerequisites, effects = {}, unit = {count = 2000, time = 60, ingredients = ingredients},
        }}
    end
end
if data.raw.item["promethium-science-pack"] then
    local ingredients = {}
    for _, pack in ipairs(core_science) do
        if data.raw.item[pack] then ingredients[#ingredients + 1] = {pack, 1} end
    end
    ingredients[#ingredients + 1] = {"promethium-science-pack", 1}
    data:extend{{type = "technology", name = "companion-promethium-1",
        icon = "__companion-drones-luan__/sprites/drone-icon.png", icon_size = 200,
        localised_name = {"technology-name.companion-promethium"},
        localised_description = {"technology-description.companion-promethium"},
        prerequisites = data.raw.technology["promethium-science-pack"] and {"promethium-science-pack"} or {},
        effects = {}, max_level = "infinite", upgrade = true,
        unit = {count_formula = "2000*2^(L-1)", time = 60, ingredients = ingredients},
    }}
end

for level = 1, planet_count do
    local sticker = table.deepcopy(data.raw.sticker["speed-sticker"])
    sticker.name = "companion-planet-speed-" .. level
    sticker.duration_in_ticks = 120
    sticker.target_movement_modifier_from = 1 + level * 0.1
    sticker.target_movement_modifier_to = 1 + level * 0.1
    sticker.vehicle_speed_modifier_from = 1 + level * 0.1
    sticker.vehicle_speed_modifier_to = 1 + level * 0.1
    data:extend{sticker}
end
