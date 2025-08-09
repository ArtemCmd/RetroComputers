local config = require("retro_computers:config")
local blocks = require("retro_computers:blocks")
local input_manager = require("retro_computers:emulator/input_manager")
local drive_manager = require("retro_computers:emulator/drive_manager")
local vmmanager = require("retro_computers:emulator/vmmanager")

function on_world_open()
    file.mkdirs("world:data/retro_computers/machines")

    config.initialize()
    blocks.initialize()
    drive_manager.initialize()
    vmmanager.initialize()
end

function on_world_tick()
    input_manager.update()
    vmmanager.update()
end

function on_world_save()
    blocks.save()
    vmmanager.save()
end
