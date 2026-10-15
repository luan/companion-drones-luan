-- A planet added by another mod participates without companion-specific configuration.
if data.raw.planet and data.raw.planet.nauvis then
    local planet = table.deepcopy(data.raw.planet.nauvis)
    planet.name = "companion-test-planet"
    planet.distance = 25
    planet.orientation = 0.3
    planet.localised_name = "Companion test planet"
    local pack = table.deepcopy(data.raw.item["automation-science-pack"])
    pack.name = "entourage-test-datacell"
    local lab = table.deepcopy(data.raw.lab.lab)
    lab.name = "companion-test-lab"
    lab.inputs = {pack.name}
    lab.minable = nil
    data:extend{planet, pack, lab, {
        type = "technology", name = "companion-test-discovery",
        icon = "__base__/graphics/technology/space-science-pack.png", icon_size = 256,
        effects = {{type = "unlock-space-location", space_location = planet.name}},
        unit = {count = 10, time = 1, ingredients = {{pack.name, 1}}},
    }}
    if APS then
        APS.add_planet{name = planet.name, filename = "__companion-integration-tests__/aps-planet",
            technology = "companion-test-discovery"}
    end
end

-- Long enough to observe independent crafting speed and an in-flight upgrade.
data.raw.recipe["stone-furnace"].energy_required = 4

-- Durable native target makes sustained combat power measurable without a timing fixture.
local target = table.deepcopy(data.raw.car.car)
target.name = "companion-combat-target"
target.max_health = 10000
target.minable = nil
data:extend{target}

-- Use the native flying-character mask to exercise collisions without a takeoff delay.
local flying_character = table.deepcopy(data.raw.character.character)
flying_character.name = "companion-flying-character"
flying_character.collision_mask = table.deepcopy(data.raw["utility-constants"].default.default_collision_masks["character/flying"])
data:extend{flying_character}
