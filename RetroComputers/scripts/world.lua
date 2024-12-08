local logger = require("retro_computers:logger")
local config = require("retro_computers:config")
local vmmanager = require("retro_computers:emulator/vmmanager")
local ibm_xt =  require("retro_computers:emulator/machine/ibm_xt")
local blocks = require("retro_computers:blocks")
local drive_manager = require("retro_computers:emulator/drive_manager")
local input_manager = require("retro_computers:emulator/input_manager")

function on_world_open()
    if not file.exists("world:") then
        file.mkdir("world:")
    end

    if not file.exists("world:data") then
        file.mkdir("world:data")
    end

    if not file.exists("world:data/retro_computers") then
        file.mkdir("world:data/retro_computers")
    end

    if not file.exists("world:data/retro_computers/machines") then
        file.mkdir("world:data/retro_computers/machines")
    end

    config.load()
    blocks.load()
    drive_manager.load_floppys()

    local machine = ibm_xt.new(vmmanager.get_next_id())
    vmmanager.registry(machine)

    -- Setup commands

    -- VMManager
    console.add_command("retro_computers.vmmanager.get_machine_info id:int", "Show machine info", function (args, kwargs)
        local machine = vmmanager.get_machine(args[1])
        if machine then
            console.log("Machine state:")
            console.log("   Enebled=" .. tostring(machine.enebled))
            console.log("   Focused=" .. tostring(machine.is_focused))
            console.log("Installed components:")
            for key, value in pairs(machine.components) do
                if type(value) == "table" then
                    console.log("   " .. key)
                end
            end
        else
            console.log("Machine not found")
        end
    end)

    console.add_command("retro_computers.vmmanager.list", "Shows existing virtual machine ids", function (args, kwargs)
        local machines = vmmanager.get_machines()
        console.log("Virtual Machines:")
        for i, _ in pairs(machines) do
            console.log(i)
        end
    end)

    -- Config
    console.add_command("retro_computers.config.list", "Show available configuration", function (args, kwargs)
        console.log("Current config:")
        local function recursive_print(t)
            for key, value in pairs(t) do
                if type(value) ~= "function" then
                    if type(value) == "table" then
                        console.log("   " .. key .. ":")
                        recursive_print(value)
                    else
                        console.log("   " .. key .. "=" .. tostring(value))
                    end
                end
            end
        end
        recursive_print(config)
    end)

    console.add_command("retro_computers.config.set name:str value:int", "Set configuration", function (args, kwargs)
        local name = args[1]
        local val = args[2]
        if config[name] ~= nil then
            if type(config[name]) == "number" then
                config[name] = val
                console.log("Key " .. name .. " set to " .. val)
            elseif type(config[name]) == "boolean" then
                config[name] = (val == 1)
                console.log("Key " .. name .. " set to " .. tostring(val == 1))
            else
                console.log("Failed set " .. name)
            end
        else
            console.log("Key " .. name .. " not found")
        end
    end)

    console.add_command("retro_computers.config.save", "Save current configuration", function (args, kwargs)
        config.save()
        console.log("Config saved")
    end)

    -- DriveManager
    console.add_command("retro_computers.drive_manager.create_hard_disk path:str fileformat:str sector_size:int cylinders:int heads:int sectors:int", "Creates a hard disk image.\nSupported file formats: RAW, HDF", function (args, kwargs)
        if drive_manager.create_hard_disk(args[1], args[4], args[5], args[6], args[3], args[2]) then
            console.log("Creation successful")
        else
            console.log("Creation failed")
        end
    end)

    -- Checking update
    if config.check_for_updates then
        network.get("https://raw.githubusercontent.com/ArtemCmd/RetroComputers/main/RetroComputers/package.json", function (str)
            local data = json.parse(str)
            local package = json.parse(file.read("retro_computers:package.json"))
            if data.version ~= package.version then
                logger:info("Found a new version on https://github.com/ArtemCmd/RetroComputers/tree/main")
                console.log("Found a new version on https://github.com/ArtemCmd/RetroComputers/tree/main")
            end
        end)
    end
end

function on_world_tick()
    input_manager.update()
    vmmanager.update()
end

function on_world_save()
    logger.save()
    blocks.save()
    vmmanager.save()
end