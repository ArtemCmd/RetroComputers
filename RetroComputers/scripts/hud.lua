local vmmanager = require("retro_computers:emulator/vmmanager")
local config = require("retro_computers:config")
local drive_manager = require("retro_computers:emulator/drive_manager")

function on_hud_open()
    -- Setup commands
    -- VMmanager
    console.add_command("retro_computers.vmmanager.get_machine_info id:int", "Show machine info", function(args, kwargs)
        local machine = vmmanager.get_machine(args[1])

        if machine then
            console.log("Machine state:")
            console.log("   Enabled = " .. tostring(machine.enabled))
            console.log("   Focused = " .. tostring(machine.is_focused))
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

    console.add_command("retro_computers.vmmanager.list", "Shows existing virtual machine ids", function(args, kwargs)
        local machines = vmmanager.get_machines()

        console.log("Virtual Machines:")
        for i, _ in pairs(machines) do
            console.log(i)
        end
    end)

    console.add_command("retro_computers.vmmanager.save_virtual_machine_state id:int path:str", "Saves virtual machine state", function(args, kwargs)
        local machine = vmmanager.get_machine(args[1])

        if machine then
            vmmanager.save_machine_state(machine, args[2])
        else
            console.log("Machine not found")
        end
    end)

    console.add_command("retro_computers.vmmanager.load_virtual_machine_state id:int path:str", "Loads the virtual machine state", function(args, kwargs)
        if file.exists(args[2]) then
            local machine = vmmanager.get_machine(args[1])

            if machine then
                vmmanager.load_machine_state(machine, args[2])
            else
                console.log("Machine not found")
            end
        else
            console.log("File not found")
        end
    end)

    -- Config
    console.add_command("retro_computers.config.list", "Show available configuration", function(args, kwargs)
        console.log("Current config:")

        local function print_table(t)
            for key, value in pairs(t) do
                if type(value) ~= "function" then
                    if type(value) == "table" then
                        console.log("   " .. key .. ":")
                        print_table(value)
                    else
                        console.log("       " .. key .. " = " .. tostring(value))
                    end
                end
            end
        end

        for key, value in pairs(config) do
            if type(value) ~= "function" then
                if type(value) == "table" then
                    console.log("   " .. key .. ":")
                    print_table(value)
                else
                    console.log("   " .. key .. " = " .. tostring(value))
                end
            end
        end
    end)

    console.add_command("retro_computers.config.set name:str value:num", "Set configuration", function(args, kwargs)
        local name = args[1]
        local val = args[2]
        if config[name] ~= nil then
            if type(config[name]) == "number" then
                config[name] = val
                console.log("Key \"" .. name .. "\" set to " .. tostring(val))
            elseif type(config[name]) == "boolean" then
                config[name] = (val == 1)
                console.log("Key \"" .. name .. "\" set to " .. tostring(val == 1))
            else
                console.log("Failed set " .. name)
            end
        else
            console.log("Key " .. name .. " not found")
        end
    end)

    console.add_command("retro_computers.config.reset", "Reset config", function(args, kwargs)
        config.reset()
    end)

    console.add_command("retro_computers.config.save", "Save current configuration", function(args, kwargs)
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

    -- Serial
    console.add_command("retro_computers.serial.send machineid:int port:int message:str", "Send string to serial port", function(args, kwargs)
        local machine = vmmanager.get_machine(args[1])

        if machine then
            local serial = machine.components.serial

            if serial then
                local ports = {0x3F8, 0x2F8, 0x3E8, 0x2E8, 0x5F8, 0x4F8, 0x5E8, 0x4E8}
                local port_num = ports[args[2]]

                if port_num then
                    local str = args[3]

                    for i = 1, #str, 1 do
                        serial:write_port(port_num, string.byte(str:sub(i, i)))
                    end
                end
            else
                console.log("Serial port is not available")
            end
        else
            console.log("Machine not found")
        end
    end)

    console.add_command("retro_computers.check_update", "Checking for updates", function(args, kwargs)
        console.log("Checking for updates...")

        network.get("https://raw.githubusercontent.com/ArtemCmd/RetroComputers/main/RetroComputers/package.json", function(str)
            local data = json.parse(str)
            local package = json.parse(file.read("retro_computers:package.json"))

            if data.version ~= package.version then
                console.log("Found a new version on https://github.com/ArtemCmd/RetroComputers/tree/main")
            else
                console.log("No updates found")
            end
        end)
    end)
end