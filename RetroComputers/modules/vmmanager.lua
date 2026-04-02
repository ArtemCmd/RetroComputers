local logger = require("dave_logger:logger")("RetroComputers")

local vmmanager = {}

local FILENAME = "vmmanager.json"
local DATA_PATH = string.format("world:data/retro_computers/%s", FILENAME)

local machines = {}
local machines_list = {}
local next_id = 0

function vmmanager.get_next_id()
    next_id = next_id + 1
    return next_id
end

function vmmanager.registry(machine, id)
    local machine_id = id or vmmanager.get_next_id()

    if machines[machine_id] then
        error("machine arleady exists")
    end

    machine.id = machine_id
    machines[id] = machine
    table.insert(machines_list, machine)

    logger:info("VMManager: Machine added, ID = %d", machine_id)
end

function vmmanager.unregistry(id)
    local machine = machines[id]

    if machine then
        machines[id] = nil

        logger:info("VMManager: Machine removed, ID = %d", id)

        for i = 1, #machines_list, 1 do
            if machines_list[i] == machine then
                return table.remove(machines_list)
            end
        end
    end
end

function vmmanager.get_machines()
    return machines
end

function vmmanager.get_machine_by_id(id)
    return machines[id]
end

function vmmanager.get_machine_by_pos(x, y, z)
    local machine_id = block.get_field(x, y, z, "vm_id")

    if machine_id then
        return machines[machine_id]
    end
end

function vmmanager.get_machine_path(id, p)
    local path = string.format("world:data/retro_computers/machines/%d/", id)
    file.mkdirs(path)

    return path .. (p or "")
end

function vmmanager.delete_machine(id)
    local machine = machines[id]
    local path = vmmanager.get_machine_path(id)

    if machine then
        if machine.on_delete then
            machine:on_delete()
        end

        vmmanager.unregistry(id)
    end

    if file.exists(path) then
        file.remove_tree(path)
    end
end

function vmmanager.update()
    for i = 1, #machines_list, 1 do
        machines_list[i]:update()
    end
end

function vmmanager.initialize()
    logger:info("VMManager: initialization...")

    if file.exists(DATA_PATH) then
        xpcall(function()
            local data = json.parse(file.read(DATA_PATH))
            next_id = data.next_id
        end, function(msg)
            logger:error("VMManager: Failed to load data: %s\n%s", msg, debug.traceback())
        end)
    end
end

function vmmanager.save()
    if next_id ~= 0 then
        local data = {
            next_id = next_id
        }

        xpcall(function()
            file.write(pack.data_file("retro_computers", FILENAME), json.tostring(data, false))
        end, function(msg)
            logger:error("VMManager: Failed to save data: %s\n%s", msg, debug.traceback())
        end)
    end

    for _, machine in pairs(machines) do
        xpcall(machine.save, function(msg)
            logger:error("VMManager: Failed to save machine data: %s\n%s", msg, debug.traceback())
        end, machine)
    end
end

return vmmanager
