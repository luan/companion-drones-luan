data:extend{{type = "fuel-category", name = "test-other"}}
local fuel = table.deepcopy(data.raw.item.coal)
fuel.name = "test-multi-fuel"
fuel.fuel_categories = {"test-other", "chemical"}
data:extend{fuel}
