local logger = require("dave_logger:logger")("RetroComputers")

local vmmanager = {}

local DATA_PATH = "world:data/retro_computers/vmmanager.json"
local vms = {}
local machine_list = {}
local machine_indexes = {}
local next_id = 1

function vmmanager.get_next_id()
    return next_id
end

function vmmanager.initialize()
    if file.exists(DATA_PATH) then
        local success, result = pcall(function()
            local data = json.parse(file.read(DATA_PATH))
            next_id = data.next_id
        end)

        if not success then
            logger:error("VMManager: Failed to load data: %s", result)
        end
    end
end

function vmmanager.registry(machine, id)
    if machine then
        local machine_id = id or vmmanager.get_next_id()

        machine.id = machine_id
        vms[machine_id] = machine
        table.insert(machine_list, machine_id)
        machine_indexes[machine_id] = #machine_list

        next_id = next_id + 1

        logger:info("VMManager: Machine registred, ID = %d", machine_id)
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

function vmmanager.get_machines()
    return vms
end

function vmmanager.get_machine(id)
    return vms[id]
end

function vmmanager.get_machine_path(id, p)
    local path = string.format("world:data/retro_computers/machines/%d/", id)
    file.mkdirs(path)

    return path .. (p or "")
end

function vmmanager.delete_machine(id)
    local machine = vms[id]
    local path = vmmanager.get_machine_path(id)

    if machine then
        if machine.on_machine_delete then
            machine:on_machine_delete()
        end

        vmmanager.unregistry(id)
    end

    if file.exists(path) then
        file.remove_tree(path)
    end
end

function vmmanager.update()
    for i = 1, #machine_list do
        local machine_id = machine_list[i]
        local machine = vms[machine_id]

        machine:update()
    end
end

function vmmanager.save()
    local data = {
        next_id = next_id
    }

    file.write(DATA_PATH, json.tostring(data, false))

    for _, machine in pairs(vms) do
        machine:save()
    end
end

return vmmanager
