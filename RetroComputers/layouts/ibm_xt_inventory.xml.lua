local logger = require("retro_computers:logger")
local vmmanager = require("retro_computers:emulator/vmmanager")
local drivemanager = require("retro_computers:emulator/drive_manager")

local function insert_drive(slot)
    local machine = vmmanager.get_machine(1)
    if machine then
        local item_name = item.name(inventory.get(hud.get_block_inventory(), slot))
        local name = item_name:sub(17 + 7, -1)
        if item_name ~= "core:empty" then
            local floppy = drivemanager.get_floppy(name)
            if floppy then
                machine.insert_floppy(floppy, slot)
                -- logger:debug("Insert floppy %s", name)
            end
        end
    else
        logger:error("Machine not found")
    end
end

function drive1_action()
    insert_drive(0)
end

function drive2_action()
    insert_drive(1)
end