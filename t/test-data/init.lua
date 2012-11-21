function test_parallel(delay, id)
    box.fiber.sleep(delay)
    return id
end

function test_parallel_big_tuple(delay, id, ...)
    local args = { ... }

    local size = 0
    for i, v in pairs(args) do
        size = size + string.len(v)
    end
    box.fiber.sleep(delay)
    return { id, tostring(size) }
end


function test_return_one()
    return { 'one' }
end

function test_return(...)
    return { ... }
end

