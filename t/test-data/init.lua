function test_parallel(delay, id)
    box.fiber.sleep(delay)
    return id
end


function test_return(...)
    return { ... }
end
