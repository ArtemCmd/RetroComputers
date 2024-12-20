local logger = require("retro_computers:logger")

local vmmanager = {}
local vms = {}
local current_machine = nil

function vmmanager.get_machines()
    return vms
end

function vmmanager.get_next_id()
    return #vms + 1
end

function vmmanager.registry(machine)
    if machine then
        local id = vmmanager.get_next_id()
        machine.id = id
        vms[id] = machine
        logger:info("VMManager: Machine %s registred", id)
    else
        logger:error("VMManager: Registration Error: Machine is nil")
    end
end

function vmmanager.unregistry(id)
    local machine = vms[id]
    machine:shutdown()
    vms[id] = nil
end

function vmmanager.get_machine(id)
    return vms[id]
end

function vmmanager.save()
    logger:info("VMmanager: Saving machines")
    for _, machine in pairs(vms) do
        machine:save()
    end
end

function vmmanager.update()
    for i = 1, #vms do
        local machine = vms[i]
        machine:update()
    end
end

function vmmanager.get_current_machine()
    return current_machine
end

function vmmanager.set_current_machine(id)
    local machine = vms[id]
    current_machine = machine
end

return vmmanager