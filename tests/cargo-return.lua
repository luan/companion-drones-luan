defines = {prototypes = {entity = {}}}
game = {tick = 0}
storage = {companion_update_interval = 5}
local workers = require('script/workers')

local attempts, received, capacity = 0, {}, 0
local trunk = {transfer_from_stack = function() return 0 end}
local companion = {
    get_inventory = function() return trunk end,
    try_to_shove_inventory = function() end,
    insert_to_player_or_vehicle = function(_, stack)
        attempts = attempts + 1
        if capacity == 0 or stack.name == 'blocked' then return 0 end
        local inserted = math.min(stack.count, capacity)
        capacity = capacity - inserted
        received[stack.name] = (received[stack.name] or 0) + inserted
        return inserted
    end,
}
local inventory = {}
for i = 1, 428 do inventory[i] = {name = i == 1 and 'blocked' or tostring(i), count = 10} end
for _, stack in ipairs(inventory) do
    setmetatable(stack, {__index = function(s, key) if key == 'valid_for_read' then return s.count > 0 end end})
end
inventory.is_empty = function()
    for _, stack in ipairs(inventory) do if stack.count > 0 then return false end end
    return true
end
local worker = {inventory = inventory}
for tick = 0, 29 do
    game.tick = tick
    assert(not workers.return_inventory(companion, worker))
end
assert(attempts == 8, 'blocked cargo retries must be bounded, even for large worker inventories')
for _, stack in ipairs(inventory) do assert(stack.count == 10, 'blocked cargo is preserved') end

-- Opening storage lets other items pass a permanently blocked stack.
capacity = 100000
for tick = 30, 300 do
    game.tick = tick
    workers.return_inventory(companion, worker)
end
for i = 2, #inventory do
    assert(inventory[i].count == 0 and received[tostring(i)] == 10, 'all deliverable cargo returns exactly once')
end
assert(inventory[1].count == 10 and not inventory.is_empty(), 'the worker retains blocked cargo')

-- Partial transfers preserve the remainder until another destination becomes available.
companion.insert_to_player_or_vehicle = function(_, stack)
    local inserted = math.min(stack.count, 3)
    received.blocked = (received.blocked or 0) + inserted
    return inserted
end
for tick = 301, 600 do
    game.tick = tick
    if workers.return_inventory(companion, worker) then break end
end
assert(inventory.is_empty() and received.blocked == 10, 'partial returns neither lose nor duplicate items')
print('COMPANION bounded cargo return PASS')
