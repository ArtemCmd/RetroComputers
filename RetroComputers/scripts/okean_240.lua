local blocks = require("retro_computers:blocks")
local vmmanager = require("retro_computers:emulator/vmmanager")

function on_interact(x, y, z, pid)
    local machine_id = blocks.get_field(x, y, z, "vm_id") or vmmanager.get_next_id()
    local machine = vmmanager.get_machine(machine_id)

    if not machine then
        machine = require("retro_computers:emulator/machine/okean_240").new(machine_id)
        blocks.set_field(x, y, z, "vm_id", machine.id)
        vmmanager.registry(machine, machine.id)
    end

    hud.show_overlay("retro_computers:screen", false, {0, x, y, z})

    return true
end

function on_placed(x, y, z, pid)
    blocks.registry(x, y, z, "machine")
end

function on_broken(x, y, z, pid)
    local machine_id = blocks.get_field(x, y, z, "vm_id")
    local machine = vmmanager.get_machine(machine_id)

    if machine then
        vmmanager.delete_machine(machine_id)
    end

    blocks.unregistry(x, y, z)
end
