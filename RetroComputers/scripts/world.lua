local logger = require("retro_computers:logger")
local config = require("retro_computers:config")
local vmmanager = require("retro_computers:emulator/vmmanager")
local ibm_xt =  require("retro_computers:emulator/machine/ibm_xt")
local blocks = require("retro_computers:blocks")
local drive_manager = require("retro_computers:emulator/drive_manager")
-- local font_manager = require("customfont:font_manager")

function on_world_open()
    config.load()
    blocks.load()
    drive_manager.load_floppys()

    local machine = ibm_xt.new(vmmanager.get_next_id())
    vmmanager.registry(machine)
end

function on_world_tick()
    vmmanager.update()
end

function on_world_save()
    vmmanager.save()
    logger.save()
    blocks.save()
end