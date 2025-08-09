local blocks = require("retro_computers:blocks")
local vmmanager = require("retro_computers:emulator/vmmanager")

function on_interact(x, y, z, pid)
    local machine_id = blocks.get_field(x, y, z, "vm_id") or vmmanager.get_next_id()
    local machine = vmmanager.get_machine(machine_id)

    if not machine then
        machine = require("retro_computers:emulator/machine/ibm_xt").new(machine_id)

        local speaker = machine:get_device("pc_speaker")
        local speaker_id = 0

        speaker:set_handler(function(channel_count, enabled)
            audio.stop(speaker_id)

            if enabled then
               speaker_id = audio.play_sound("computer/beep", x, y, z, 1.0, 1.0 / (1193182 / channel_count) * 250.0, "regular", false)
            end
        end)

        blocks.set_field(x, y, z, "vm_id", machine:get_id())
        vmmanager.registry(machine, machine:get_id())
    end

    hud.show_overlay("retro_computers:screen", false, {0, x, y, z})

    return true
end

function on_placed(x, y, z, pid)
    blocks.registry(x, y, z, "machine")
end

function on_broken(x, y, z, pid)
    local machine_id = blocks.get_field(x, y, z, "vm_id")

    if machine_id then
        vmmanager.delete_machine(machine_id)
    end

    blocks.unregistry(x, y, z)
end
