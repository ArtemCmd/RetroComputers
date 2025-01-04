local logger = require("retro_computers:logger")
local config = require("retro_computers:config")
local vmmanager = require("retro_computers:emulator/vmmanager")
local blocks = require("retro_computers:blocks")
local drive_manager = require("retro_computers:emulator/drive_manager")
local input_manager = require("retro_computers:emulator/input_manager")
local ibm_xt =  require("retro_computers:emulator/machine/ibm_xt")

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
    drive_manager.load_floppys()

    local machine = ibm_xt.new(vmmanager.get_next_id())
    vmmanager.load_machine_state(machine)
    vmmanager.registry(machine)

    -- Checking update
    if config.check_for_updates then
        network.get("https://raw.githubusercontent.com/ArtemCmd/RetroComputers/main/RetroComputers/package.json", function (str)
            local data = json.parse(str)
            local package = json.parse(file.read("retro_computers:package.json"))
            if data.version ~= package.version then
                logger:info("Found a new version on https://github.com/ArtemCmd/RetroComputers/tree/main")
                console.log("Found a new version on https://github.com/ArtemCmd/RetroComputers/tree/main")
            end
        end)
    end
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