-- A planet added by another mod participates without companion-specific configuration.
if data.raw.planet and data.raw.planet.nauvis then
    local planet = table.deepcopy(data.raw.planet.nauvis)
    planet.name = "companion-test-planet"
    planet.distance = 25
    planet.orientation = 0.3
    planet.localised_name = "Companion test planet"
    data:extend{planet, {
        type = "technology", name = "companion-test-discovery",
        icon = "__base__/graphics/technology/space-science-pack.png", icon_size = 256,
        effects = {{type = "unlock-space-location", space_location = planet.name}},
        unit = {count = 10, time = 1, ingredients = {{"automation-science-pack", 1}}},
    }}
end

-- Long enough to observe independent crafting speed and an in-flight upgrade.
data.raw.recipe["stone-furnace"].energy_required = 4

-- Durable native target makes sustained combat power measurable without a timing fixture.
local target = table.deepcopy(data.raw.car.car)
target.name = "companion-combat-target"
target.max_health = 10000
target.minable = nil
data:extend{target}
