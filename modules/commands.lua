local config = require("retro_computers:config")
local drive_manager = require("retro_computers:drive_manager")
local vmmanager = require("retro_computers:vmmanager")

local commands = {}

local function print_machine_info(machine)
    console.log("Machine:")
    console.log("   ID = " .. tostring(machine:get_id()))
    console.log("   Enabled = " .. tostring(machine:is_running()))
    console.log("   Focused = " .. tostring(machine.is_focused))
    console.log("Installed devices:")

    for name, _ in pairs(machine:get_devices()) do
        console.log("   " .. name)
    end
end

function commands.initialize()
    -- VMManager
    console.add_command("retro_computers.vmmanager.get_info id:int", "Show machine info", function(args, kwargs)
        local machine = vmmanager.get_machine_by_id(args[1])

        if not machine then
            return "Machine not found"
        end


        print_machine_info(machine)
    end)

    console.add_command("retro_computers.vmmanager.get_info_all", "Show information about all virtual machines", function(args, kwargs)
        for _, machine in pairs(vmmanager.get_machines()) do
            print_machine_info(machine)
        end
    end)

    console.add_command("retro_computers.vmmanager.list", "Shows existing virtual machine IDs", function(args, kwargs)
        local machines = vmmanager.get_machines()

        console.log("Virtual Machines:")

        for id, _ in pairs(machines) do
            console.log("   " .. id)
        end
    end)

    console.add_command("retro_computers.vmmanager.clean", "Removes data from unused virtual machines", function(args, kwargs)
        local dirs = file.list("world:data/retro_computers/machines")
        local count = 0

        for i = 1, #dirs, 1 do
            local dir = dirs[i]
            local machine_id = tonumber(file.name(dir), 10)

            if vmmanager.get_machine_by_id(machine_id) == nil then
                file.remove_tree(dir)
                count = count + 1
            end
        end

        console.log("Removed " .. count .. " machines")
    end)

    -- Config
    console.add_command("retro_computers.config.show", "Show current config", function(args, kwargs)
        local level = 0

        console.log("{")

        local function print_table(t, root)
            local spaces = string.rep(" ", 4 * level)
            local value_spaces = string.rep(" ", 4 * (level + 1))

            for key, val in pairs(t) do
                local value_type = type(val)

                if value_type ~= "function" then
                    if value_type == "table" then
                        level = level + 1
                        console.log(value_spaces .. tostring(key) .. " = {")
                        print_table(val, false)
                        level = level - 1
                    elseif value_type == "string" then
                        console.log(string.format("%s%s = \"%s\",", value_spaces, tostring(key), tostring(val)))
                    else
                        console.log(string.format("%s%s = %s,", value_spaces, tostring(key), tostring(val)))
                    end
                end
            end

            if root then
                console.log("}")
            else
                console.log(spaces .. "},")
            end
        end

        print_table(config, true)
    end)

    -- DriveManager
    console.add_command("retro_computers.drive_manager.create_items", "Create items", function(args, kwargs)
        drive_manager.create_items()
    end)

    console.add_command("retro_computers.drive_manager.list", "Shows loaded disks", function(args, kwargs)
        local drives = drive_manager.get_drives()
        local count = 0

        console.log("Disks:")

        for i = 1, #drives, 1 do
            for _, drive in pairs(drives[i]) do
                local str = drive.name .. ":\n  Type: "

                if i == drive_manager.DRIVE_TYPE_FLOPPY then
                    str = str .. "Floppy"
                elseif i == drive_manager.DRIVE_TYPE_TAPE then
                    str = str .. "Tape"
                else
                    str = str .. "Unknown"
                end

                str = str .. "\n    Path: " .. drive.path
                str = str .. "\n    Write Protected: " .. tostring(drive.readonly) .. "\n"

                console.log(str)
                count = count + 1
            end
        end

        console.log("Count: " .. count)
    end)

    -- Serial
    console.add_command("retro_computers.serial.attach machine_id:int port:int", "Attach handler to port", function(args, kwargs)
        local machine = vmmanager.get_machine_by_id(args[1])

        if not machine then
            return "Machine not found"
        end

        local serial = machine:get_device("serial")

        if not serial then
            return "Serial device not found"
        end

        local buffer = {}

        serial:set_port_handler(args[2], {
            write = function(_, val)
                buffer[#buffer+1] = string.char(val)

                if val == string.byte("\n") then
                    console.chat(table.concat(buffer))
                    buffer = {}
                end

                console.chat(string.char(val))
            end
        })
    end)

    console.add_command("retro_computers.serial.send machine_id:int port:int value:int", "Send integer to serial port", function(args, kwargs)
        local machine = vmmanager.get_machine_by_id(args[1])

        if not machine then
            return "Machine not found"
        end

        local serial = machine:get_device("serial")

        if not serial then
            return "Serial device not found"
        end

        serial:write(args[2], args[3])
    end)
end

return commands
