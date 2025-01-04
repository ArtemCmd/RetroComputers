local logger = require("retro_computers:logger")
local vms_file = require("retro_computers:emulator/file_formats/vms")
local config = require("retro_computers:config")

local vmmanager = {}
local vms = {}
local current_machine = nil

function vmmanager.get_machine_path(id)
    local path = "world:data/retro_computers/machines/".. id

    if file.exists("world:data") then
        if not file.exists(path) then
            file.mkdir(path)
        end
    end

    return path .. "/"
end

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

    if machine.on_machine_delete then
        machine:on_machine_delete()
    end

    vms[id] = nil
end

function vmmanager.get_machine(id)
    return vms[id]
end

function vmmanager.save()
    logger:info("VMManager: Saving machines")

    for id, machine in pairs(vms) do
        machine:save()

        if config.save_virtual_machine_state then
            local path = vmmanager.get_machine_path(id) .. "state.vms"

            if machine.enabled then
                vms_file.create(path, machine)
            elseif file.exists(path) then
                file.remove(path)
            end
        end
    end
end

function vmmanager.save_machine_state(machine, save_path)
    local path = save_path or vmmanager.get_machine_path(machine.id) .. "state.vms"
    vms_file.create(path, machine)
end

function vmmanager.load_machine_state(machine, load_path)
    if config.save_virtual_machine_state then
        local path = load_path or vmmanager.get_machine_path(machine.id) .. "state.vms"

        if file.exists(path) then
            machine:reset()
            local ok, result = pcall(vms_file.load, path, machine.components)

            if ok then
                if machine.on_load_state then
                    machine:on_load_state()
                end

                machine.enabled = true
            else
                logger:error("VMManager: Load Machine State Error: %s", result)
            end
        end
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