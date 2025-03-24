local logger = require("retro_computers:logger")
local config = require("retro_computers:config")
local filesystem = require("retro_computers:emulator/filesystem")

local vmmanager = {}
local PATH = "world:data/retro_computers/vmmanager.json"
local vms = {}
local machine_list = {}
local machine_indexes = {}
local next_id = 1
local current_machine = nil

function vmmanager.get_machine_path(id)
    local path = "world:data/retro_computers/machines/".. id

    if not file.exists(path) then
        file.mkdir(path)
    end

    return path .. "/"
end

function vmmanager.get_machines()
    return vms
end

function vmmanager.get_next_id()
    return next_id
end

function vmmanager.registry(machine, id)
    if machine then
        local machine_id = id or vmmanager.get_next_id()

        machine.id = machine_id
        vms[machine_id] = machine
        table.insert(machine_list, machine_id)
        machine_indexes[machine_id] = #machine_list

        next_id = next_id + 1

        logger.info("VMManager: Machine registred, ID = %d", machine_id)
    else
        logger.error("VMManager: Error: Machine is nil")
    end
end

function vmmanager.unregistry(id)
    local machine = vms[id]

    if machine then
        local machine_index = machine_indexes[id]

        table.remove(machine_list, machine_index)
        machine_indexes[id] = nil
        vms[id] = nil

        for key, value in pairs(machine_indexes) do
            if key > id then
                machine_indexes[key] = value - 1
            end
        end

        return machine
    end
end

function vmmanager.get_machine(id)
    return vms[id]
end

function vmmanager.delete_machine(id)
    local machine = vms[id]
    local path = vmmanager.get_machine_path(id)

    if file.exists(path) then
        file.remove_tree(path)
    end

    if machine then
        if machine.on_machine_delete then
            machine:on_machine_delete()
        end

        vmmanager.unregistry(id)
    end
end

function vmmanager.update()
    for i = 1, #machine_list do
        local machine_id = machine_list[i]
        local machine = vms[machine_id]

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

function vmmanager.save_machine_state(machine, save_path)
    local path = save_path or vmmanager.get_machine_path(machine.id) .. "state.vms"
    local stream = filesystem.open(path, true)

    if stream then
        stream:write_bytes({86, 77, 83})
        stream:write(1)

        for name, device in pairs(machine.components) do
            if device.save_state ~= nil then
                stream:write_string(name)
                device:save_state(stream)
            end
        end
    end

    stream:flush()
end

function vmmanager.load_machine_state(machine, load_path)
    if config.save_state then
        local path = load_path or vmmanager.get_machine_path(machine.id) .. "state.vms"

        if file.exists(path) then
            machine:reset()

            local stream = filesystem.open(path, true)
            local file_size = file.length(path)
            local components = machine.components

            if stream then
                local signature = stream:read_bytes(3)
                local version = stream:read()

                if (signature[1] == 86) and (signature[2] == 77) and (signature[3] == 83) then
                    if version == 1 then
                        local chunks = {}

                        while stream:get_position() < file_size do
                            local chunk_name = stream:read_string()
                            local length = stream:read_uint32()

                            if components[chunk_name] then
                                chunks[chunk_name] = stream:read_bytes(length)
                            end
                        end

                        for device_name, device in pairs(components) do
                            local chunk = chunks[device_name]

                            if chunk then
                                if device.load_state ~= nil then
                                    device:load_state(chunk)
                                end
                            end
                        end
                    else
                        error("Unsupported VMS version")
                    end
                else
                    error("File is not VMS")
                end
            end

            if machine.on_load_state then
                machine:on_load_state()
            end

            machine.enabled = true
        end
    end
end

function vmmanager.load()
    if file.exists(PATH) then
        local data = json.parse(file.read(PATH))

        next_id = data.next_id
    end
end

function vmmanager.save()
    local data = {
        next_id = next_id
    }

    file.write(PATH, json.tostring(data, false))

    for id, machine in pairs(vms) do
        machine:save()

        if config.save_state then
            local path = vmmanager.get_machine_path(id) .. "state.vms"

            if machine.enabled then
                vmmanager.save_machine_state(machine, path)
            elseif file.exists(path) then
                file.remove(path)
            end
        end
    end
end

return vmmanager