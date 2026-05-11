local machine = {}
machine.__index = machine

function machine:get_id()
    return self.id
end

function machine:is_running()
    return self.enabled
end

function machine:is_paused()
    return self.paused
end

function machine:get_device(name)
    return self.devices[name]
end

function machine:get_devices()
    return self.devices
end

function machine:set_device(name, device)
    self.devices[name] = device
end

function machine:reset()
    for _, device in pairs(self.devices) do
        if device.reset then
            device:reset()
        end
    end
end

function machine:pause()
    self.enabled = false
    self.paused = true
end

function machine:resume()
    if self.paused then
        self.enabled = true
        self.paused = false
    end
end

function machine:start() end
function machine:stop() end
function machine:update() end
function machine:save() end

return machine
