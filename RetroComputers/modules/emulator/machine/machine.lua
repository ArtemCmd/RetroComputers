local machine = {}
machine.__index = machine

function machine:get_id()
    return self.id
end

function machine:is_running()
    return self.enabled
end

function machine:get_device(name)
    return self.devices[name]
end

function machine:set_device(name, device)
    self.devices[name] = device
end

function machine:start() end
function machine:stop() end
function machine:reset() end
function machine:update() end
function machine:save() end

return machine
