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

function crafting.recipes(player)
    local result = {}
    local categories = player.character.prototype.crafting_categories
    for name, recipe in pairs(player.force.recipes) do
        local supported = false
        for _, category in pairs(recipe.categories) do
            if categories[category] then supported = true end
        end
        if recipe.enabled and supported and not recipe.hidden and not recipe.prototype.hidden_from_player_crafting
            and not player.force.get_hand_crafting_disabled_for_recipe(name) then
            local valid = true
            for _, condition in pairs(recipe.prototype.surface_conditions or {}) do
                local value = player.physical_surface.get_property(condition.property)
                if condition.min and value < condition.min or condition.max and value > condition.max then valid = false end
            end
            for _, ingredient in pairs(recipe.ingredients) do if ingredient.type ~= "item" then valid = false end end
            if valid and #recipe.products == 1 then
                for _, product in pairs(recipe.products) do
                    if product.type == "item" and product.amount and (product.probability or 1) == 1 then
                        result[product.name] = result[product.name] or {}
                        result[product.name][#result[product.name] + 1] = {name = name,
                            amount = product.amount, ingredients = recipe.ingredients, energy = recipe.energy,
                            intermediate = recipe.prototype.allow_as_intermediate}
                    end
                end
            end
        end
    end
    for item, recipes in pairs(result) do
        table.sort(recipes, function(a, b)
            if (a.name == item) ~= (b.name == item) then return a.name == item end
            return a.name < b.name
        end)
    end
    return result
end

return crafting
