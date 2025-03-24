---@diagnostic disable: undefined-field
local vmmanager = require("retro_computers:emulator/vmmanager")
local config = require("retro_computers:config")

function on_hud_open()
    -- Setup commands
    -- VMmanager
    console.add_command("retro_computers.vmmanager.get_info id:int", "Show machine info", function(args, kwargs)
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

    console.add_command("retro_computers.vmmanager.list", "Shows existing virtual machine IDs", function(args, kwargs)
        local machines = vmmanager.get_machines()

        console.log("Virtual Machines:")

        for i, _ in pairs(machines) do
            console.log("   " .. i)
        end
    end)

    console.add_command("retro_computers.vmmanager.save_state machine_id:int path:str", "Saves virtual machine state", function(args, kwargs)
        local machine = vmmanager.get_machine(args[1])

        if machine then
            vmmanager.save_machine_state(machine, args[2])
        else
            console.log("Machine not found")
        end
    end)

    console.add_command("retro_computers.vmmanager.load_state machine_id:int path:str", "Loads the virtual machine state", function(args, kwargs)
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

    console.add_command("retro_computers.vmmanager.clean", "Clear unused virtual machines", function(args, kwargs)
        local dirs = file.list("world:data/retro_computers/machines")
        local count = 0

        for i = 1, #dirs, 1 do
            local dir = dirs[i]
            local splitted_str = string.split(dir, "/")
            local dir_name = splitted_str[#splitted_str]
            local machine_id = tonumber(dir_name)

            if not vmmanager.get_machine(machine_id) then
                file.remove_tree(dir)
                count = count + 1
            end
        end

        console.log("Clear " .. count .. " machines")
    end)

    -- Config
    console.add_command("retro_computers.config.list", "Show available configuration", function(args, kwargs)
        console.log("Current config:")

        local level = 0

        local function print_table(t, noroot)
            local spaces = string.rep(" ", 4 * level)
            local value_spaces = string.rep(" ", 4 * (level + 1))

            console.log(spaces .. "{")

            for key, value in pairs(t) do
                if type(value) ~= "function" then
                    if type(value) == "table" then
                        level = level + 1
                        console.log(value_spaces .. tostring(key) .. " =")
                        print_table(value, true)
                        level = level - 1
                    else
                        console.log(value_spaces .. key .. " = " .. tostring(value) .. ",")
                    end
                end
            end

            if noroot then
                console.log(spaces .. "},")
            else
                console.log(spaces .. "}")
            end
        end

        print_table(config, false)
    end)

    console.add_command("retro_computers.config.set name:str value:str", "Sets value in config\nExample: retro_computers.config.set \"screen.renderer_delay\" \"0.15\"", function(args, kwargs)
        local keys = string.split(args[1], ".")
        local new_val = args[2]
        local key_index = 1

        local function recursive_set(t, val)
            local key = keys[key_index]
            local value = t[key]

            if value then
                if key_index == #keys then
                    if type(value) == "string" then
                        t[key] = val
                    elseif type(value) == "number" then
                        t[key] = tonumber(val)
                    elseif type(value) == "boolean" then
                        t[key] = val == "true"
                    end

                    console.log(string.format("Key \"%s\" set to \"%s\"", args[1], new_val))
                else
                    if type(value) == "table" then
                        key_index = key_index + 1
                        recursive_set(value, val)
                    end
                end
            end
        end

        recursive_set(config, new_val)
    end)

    console.add_command("retro_computers.config.reset", "Reset config", function(args, kwargs)
        config.reset()
    end)

    console.add_command("retro_computers.config.save", "Save config changes", function(args, kwargs)
        config.save()
    end)
end