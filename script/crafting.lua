local crafting = {}

-- Plan only deterministic item recipes. Fluid or probabilistic recipes need machine crafting.
function crafting.plan(recipes, available, name, count)
    local stock, used, visiting, duration, steps = {}, {}, {}, 0, {}
    for item, amount in pairs(available) do stock[item] = amount end
    local function need(item, amount, intermediate)
        local take = math.min(stock[item] or 0, amount)
        stock[item] = (stock[item] or 0) - take
        used[item] = (used[item] or 0) + math.min(take, (available[item] or 0) - (used[item] or 0))
        amount = amount - take
        if amount == 0 then return true end
        if visiting[item] then return false end
        visiting[item] = true
        for _, recipe in ipairs(recipes[item] or {}) do
            if not intermediate or recipe.intermediate then
                local before_stock, before_used, before_duration, before_steps = {}, {}, duration, #steps
                for key, value in pairs(stock) do before_stock[key] = value end
                for key, value in pairs(used) do before_used[key] = value end
                local runs = math.ceil(amount / recipe.amount)
                local possible = true
                for _, ingredient in ipairs(recipe.ingredients) do
                    if not need(ingredient.name, ingredient.amount * runs, true) then possible = false; break end
                end
                if possible then
                    stock[item] = (stock[item] or 0) + runs * recipe.amount - amount
                    duration = duration + (recipe.energy or 0) * runs
                    steps[#steps + 1] = recipe.name
                    visiting[item] = nil
                    return true, recipe.name, runs
                end
                stock, used, duration = before_stock, before_used, before_duration
                while #steps > before_steps do steps[#steps] = nil end
            end
        end
        visiting[item] = nil
        return false
    end
    local possible, recipe, runs = need(name, count, false)
    if possible and recipe then
        local outputs = {[name] = count}
        for item, amount in pairs(stock) do
            local surplus = amount - ((available[item] or 0) - (used[item] or 0))
            if surplus > 0 then outputs[item] = (outputs[item] or 0) + surplus end
        end
        return {recipe = recipe, count = runs, ingredients = used, outputs = outputs, energy = duration, steps = steps}
    end
end

local candidates = {}

-- Cache prototype membership only; unlocks, handcraft permissions and surfaces remain live.
function crafting.recipe(player, name)
    local recipe = player.force.recipes[name]
    if not recipe or not player.character or not recipe.enabled or recipe.hidden
        or recipe.prototype.hidden_from_player_crafting
        or player.force.get_hand_crafting_disabled_for_recipe(name) then return end
    local categories = player.character.prototype.crafting_categories
    local supported = false
    for _, category in pairs(recipe.categories) do
        if categories[category] then supported = true end
    end
    if not supported then return end
    for _, condition in pairs(recipe.prototype.surface_conditions or {}) do
        local value = player.physical_surface.get_property(condition.property)
        if condition.min and value < condition.min or condition.max and value > condition.max then return end
    end
    for _, ingredient in pairs(recipe.ingredients) do if ingredient.type ~= "item" then return end end
    if #recipe.products ~= 1 then return end
    local product = recipe.products[1]
    if product.type ~= "item" or not product.amount or (product.probability or 1) ~= 1 then return end
    return {name = name, amount = product.amount, ingredients = recipe.ingredients, energy = recipe.energy,
        intermediate = recipe.prototype.allow_as_intermediate}
end

function crafting.recipes(player, item, result)
    result = result or {}
    if result[item] then return result end
    if not candidates[item] then
        local names = {}
        for name in pairs(prototypes.get_recipe_filtered{
            {filter = "has-product-item", elem_filters = {{filter = "name", name = item}}},
            {filter = "hidden", invert = true, mode = "and"},
            {filter = "hidden-from-player-crafting", invert = true, mode = "and"},
        }) do names[#names + 1] = name end
        candidates[item] = names
    end
    local recipes = {}
    result[item] = recipes -- Mark visited before collecting cyclic ingredient recipes.
    for _, name in ipairs(candidates[item]) do
        local recipe = crafting.recipe(player, name)
        if recipe then
            recipes[#recipes + 1] = recipe
            for _, ingredient in ipairs(recipe.ingredients) do crafting.recipes(player, ingredient.name, result) end
        end
    end
    table.sort(recipes, function(a, b)
        if (a.name == item) ~= (b.name == item) then return a.name == item end
        return a.name < b.name
    end)
    return result
end

return crafting
