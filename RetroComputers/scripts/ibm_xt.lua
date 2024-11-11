local vmmanager = require("retro_computers:emulator/vmmanager")
local blocks = require("retro_computers:blocks")

function on_interact(x, y, z, pid)
    vmmanager.set_current_machine(1)
    blocks.set_current_block(x, y, z)
    hud.show_overlay("retro_computers:ibm_xt")
    return true
end

function on_placed(x, y, z, pid)
    blocks.registry(x, y, z, "machine")
end

function on_broken(x, y, z, pid)
    blocks.unregistry(x, y, z)
end