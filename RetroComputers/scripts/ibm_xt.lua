local config = require("retro_computers:config")
local blocks = require("retro_computers:blocks")
local vmmanager = require("retro_computers:emulator/vmmanager")
local ibm_xt =  require("retro_computers:emulator/machine/ibm_xt")
local screen3d = require("retro_computers:screen3d")

local speakers = {}
local screen3d_offsets = {
    [0] = {0.49, 0.79, 0.652},
    [1] = {0.66, 0.79, 0.500},
    [2] = {0.498, 0.79, 0.34},
    [3] = {0.348, 0.79, 0.51},
}

function on_interact(x, y, z, pid)
    local machine_id = blocks.get_field(x, y, z, "vm_id") or vmmanager.get_next_id()
    local machine = vmmanager.get_machine(machine_id)

    if not machine then
        machine = ibm_xt.new(machine_id)

        if machine then
            local speaker = machine:get_component("pc_speaker")
            local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)

            speakers[key] = {0, 0}

            speaker:set_handler(function(freq)

                if not audio.is_playing(speakers[key][1]) then
                    speakers[key][1] = audio.play_sound("computer/beep", x, y, z, 0.5, 1.0 / freq * 150, "regular", false)
                end
            end)

            machine:set_event_handler(function(_, event_id)
                if (event_id == ibm_xt.EVENTS.START) or (event_id == ibm_xt.EVENTS.LOAD_STATE)  then
                    speakers[key][2] = audio.play_sound("computer/running", x, y, z, 1.0, 1.0, "regular", true)
                elseif (event_id == ibm_xt.EVENTS.STOP) or (event_id == ibm_xt.EVENTS.DELETE) then
                    audio.stop(speakers[key][2])
                end
            end)

            blocks.set_field(x, y, z, "vm_id", machine.id)
            vmmanager.registry(machine, machine.id)
            vmmanager.load_machine_state(machine)
        end
    end

    if config.enable_screen_3d then
        local screen = machine:get_component("screen3d")

        if not screen then
            machine:set_component("screen3d", screen3d.new(x, y, z, block.get_rotation(x, y, z), 0.0006, screen3d_offsets, {80, 80, 80}, machine:get_component("screen")))
        end
    end

    blocks.set_current_block(x, y, z)
    vmmanager.set_current_machine(machine_id)
    hud.show_overlay("retro_computers:ibm_xt")

    return true
end

function on_placed(x, y, z, pid)
    blocks.registry(x, y, z, "machine")
end

function on_broken(x, y, z, pid)
    local machine_id = blocks.get_field(x, y, z, "vm_id")
    local machine = vmmanager.get_machine(machine_id)

    if machine then
        local screen = machine:get_component("screen3d")

        if screen then
            screen:delete()
        end
    end

    vmmanager.delete_machine(machine_id)
    blocks.unregistry(x, y, z)
end