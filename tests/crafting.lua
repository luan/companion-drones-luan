local crafting = require("script/crafting")
local recipes = {
    cable = {{name = "cable", amount = 2, energy = 0.5, intermediate = true, ingredients = {{name = "copper", amount = 1}}}},
    circuit = {{name = "circuit", amount = 1, energy = 0.5, intermediate = true,
        ingredients = {{name = "iron", amount = 1}, {name = "cable", amount = 3}}}},
}
for count = 1, 20 do
    local copper = math.ceil(count * 3 / 2)
    local available = {copper = copper, iron = count}
    local plan = assert(crafting.plan(recipes, available, "circuit", count))
    assert(plan.energy == 0.5 * (copper + count), "duration includes intermediate recipe batches")
    assert(plan.count == count and plan.recipe == "circuit")
    assert(plan.ingredients.copper == copper and plan.ingredients.iron == count)
    assert((plan.ingredients.cable or 0) == 0, "generated intermediates must not be requested as raw materials")
    assert(available.copper == copper and available.iron == count, "planning does not mutate stock")
    assert(not crafting.plan(recipes, {copper = copper - 1, iron = count}, "circuit", count))
end
local cyclic = {
    a = {{name = "a", amount = 1, intermediate = true, ingredients = {{name = "b", amount = 1}}}},
    b = {{name = "cycle", amount = 1, intermediate = true, ingredients = {{name = "a", amount = 1}}},
        {name = "from-ore", amount = 1, intermediate = true, ingredients = {{name = "ore", amount = 1}}}},
}
assert(not crafting.plan(cyclic, {}, "a", 1), "cyclic recipes terminate")
assert(crafting.plan(cyclic, {ore = 1}, "a", 1).ingredients.ore == 1, "a failed alternative does not consume stock")
local queued = assert(crafting.plan(recipes, {copper = 3, iron = 2}, "circuit", 2))
assert(#queued.queue == 2 and queued.queue[1].item == "cable" and queued.queue[1].count == 6)
assert(queued.queue[2].item == "circuit" and queued.queue[2].count == 2, "queue records intermediate runs before final recipe")
assert(queued.queue[1].energy + queued.queue[2].energy == queued.energy, "queue duration matches reserved work")
print("COMPANION crafting planner PASS")
