local vmmanager = require("retro_computers:vmmanager")

function on_interact(x, y, z, pid)
    local machine_id = block.get_field(x, y, z, "vm_id") or vmmanager.get_next_id()
    local machine = vmmanager.get_machine_by_id(machine_id)

    if not machine then
        machine = require("retro_computers:machine/ibm_xt").new(machine_id)
        block.set_field(x, y, z, "vm_id", machine:get_id())
        vmmanager.registry(machine, machine:get_id())
    end

    hud.show_overlay("retro_computers:screen", false, {0, x, y, z})

    return true
end

function on_breaking(x, y, z, pid)
    local machine_id = block.get_field(x, y, z, "vm_id")

    if machine_id then
        vmmanager.delete_machine(machine_id)
    end
end
