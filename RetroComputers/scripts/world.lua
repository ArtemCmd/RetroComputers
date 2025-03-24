local logger = require("retro_computers:logger")
local config = require("retro_computers:config")
local blocks = require("retro_computers:blocks")
local input_manager = require("retro_computers:emulator/input_manager")
local drive_manager = require("retro_computers:emulator/drive_manager")
local vmmanager = require("retro_computers:emulator/vmmanager")

function on_world_open()
    if not file.exists("world:") then
        file.mkdir("world:")
    end

    if not file.exists("world:data") then
        file.mkdir("world:data")
    end

    if not file.exists("world:data/retro_computers") then
        file.mkdir("world:data/retro_computers")
    end

    if not file.exists("world:data/retro_computers/machines") then
        file.mkdir("world:data/retro_computers/machines")
    end

    config.load()
    blocks.load()
    drive_manager.load()
    vmmanager.load()
end

function on_world_tick()
    input_manager.update()
    vmmanager.update()
end

function on_world_save()
    logger.save()
    blocks.save()
    vmmanager.save()
end