local vmmanager = require("retro_computers:emulator/vmmanager")
local blocks = require("retro_computers:blocks")
local display3d = require("retro_computers:emulator/display3d")
local config = require("retro_computers:config")

function on_interact(x, y, z, pid)
    blocks.set_current_block(x, y, z)
    vmmanager.set_current_machine(1)
    hud.show_overlay("retro_computers:ibm_xt")

    if config.enable_screen_3d then
        local machine = vmmanager.get_machine(1)
        if machine then
            if not machine.components.display3d then
                machine.components.display3d = display3d.new(x, y, z, block.get_rotation(x, y, z), machine.components.display)
            else
                machine.components.display3d:reset(x, y, z, block.get_rotation(x, y, z))
            end
        end
    end

    return true
end

function on_blocks_tick()
    if config.enable_screen_3d then
        local machine = vmmanager.get_machine(1)

        if machine then
            if machine.components.display3d then
                machine.components.display3d:update()
            end
        end
    end
end

function on_placed(x, y, z, pid)
    blocks.registry(x, y, z, "machine")
end

function on_broken(x, y, z, pid)
    blocks.unregistry(x, y, z)

    local machine = vmmanager.get_machine(1)

    if machine then
        if config.enable_screen_3d then
            if machine.components.display3d then
                machine.components.display3d:delete()
            end
        end

        machine:shutdown()
    end
end