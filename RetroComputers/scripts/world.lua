local logger = require("retro_computers:logger")
local config = require("retro_computers:config")
local vmmanager = require("retro_computers:emulator/vmmanager")
local ibm_xt =  require("retro_computers:emulator/machine/ibm_xt")
local blocks = require("retro_computers:blocks")
local drive_manager = require("retro_computers:emulator/drive_manager")

function on_world_open()
    local path =  "world:data/retro_computers/"
    if not file.exists(path) then
        file.mkdir(path)
    end
    if not file.exists(path .. "machines") then
        file.mkdir(path .. "machines")
    end

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
    logger.save()
    blocks.save()
    vmmanager.save()
end