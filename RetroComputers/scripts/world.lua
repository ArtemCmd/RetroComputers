local config = require("retro_computers:config")
local input_manager = require("retro_computers:input_manager")
local drive_manager = require("retro_computers:drive_manager")
local vmmanager = require("retro_computers:vmmanager")
local commands = require("retro_computers:commands")

function on_world_open()
    config.initialize()
    drive_manager.initialize()
    vmmanager.initialize()
    commands.initialize()
end

function on_world_tick()
    input_manager.update()
    vmmanager.update()
end

function on_world_save()
    vmmanager.save()
end
