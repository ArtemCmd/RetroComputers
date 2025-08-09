local blocks = require("retro_computers:blocks")
local vmmanager = require("retro_computers:emulator/vmmanager")
local drive_manager = require("retro_computers:emulator/drive_manager")

local machine = nil

local function insert_drive(slot)
    if machine then
        local item_name = item.name(inventory.get(hud.get_block_inventory(), slot))

        if item_name ~= "core:empty" then
            local name = string.sub(file.path(item_name), 8, -1)
            local floppy = drive_manager.get_floppy(name)

            if floppy then
                machine:insert_floppy(floppy, slot)
            end
        else
            machine:eject_floppy(slot)
        end
    end
end

function drive1_action()
    insert_drive(0)
end

function drive2_action()
    insert_drive(1)
end

function on_open(inv_id, x, y, z)
    local machine_id = blocks.get_field(x, y, z, "vm_id")

    machine = vmmanager.get_machine(machine_id)
end

function on_close()
    machine = nil
end
