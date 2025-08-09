local vmmanager = require("retro_computers:emulator/vmmanager")
local config = require("retro_computers:config")

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

function on_hud_open()
    -- Setup commands
    -- VMmanager
    console.add_command("retro_computers.vmmanager.get_info id:int", "Show machine info", function(args, kwargs)
        local machine = vmmanager.get_machine(args[1])

        if machine then
            print_machine_info(machine)
        else
            console.log("Machine not found")
        end
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

            if vmmanager.get_machine(machine_id) == nil then
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
end
