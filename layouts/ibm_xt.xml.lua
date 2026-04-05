local vmmanager = require("retro_computers:vmmanager")
local drive_manager = require("retro_computers:drive_manager")

local machine = nil
local entry_points = {}

local function insert_drive(slot)
    if machine then
        local item_name = item.name(inventory.get(hud.get_block_inventory(), slot))

        if item_name ~= "core:empty" then
            local name = string.gsub(item_name, "floppy_", "", 1)
            local floppy = drive_manager.get_floppy(name)
            local pack_id, filename = parse_path(floppy.path)

            if floppy.readonly or file.is_writeable(floppy.path) then
                machine:insert_floppy(floppy, slot)
                audio.play_sound_2d("computer/floppy_insert", 1.0, 1.0, "regular", false)
            elseif entry_points[pack_id] ~= nil then
                floppy.path = string.format("%s:%s", entry_points[pack_id], filename)
                machine:insert_floppy(floppy, slot)
                audio.play_sound_2d("computer/floppy_insert", 1.0, 1.0, "regular", false)
            else
                pack.request_writeable(pack_id, function(entry_point)
                    entry_points[pack_id] = entry_point
                    floppy.path = string.format("%s:%s", entry_point, filename)
                    machine:insert_floppy(floppy, slot)
                    audio.play_sound_2d("computer/floppy_insert", 1.0, 1.0, "regular", false)
                end)
            end
        else
            machine:eject_floppy(slot)
            audio.play_sound_2d("computer/floppy_eject", 1.0, 1.0, "regular", false)
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
    machine = vmmanager.get_machine_by_id(block.get_field(x, y, z, "vm_id"))
end

function on_close()
    machine = nil
end
