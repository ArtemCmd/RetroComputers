---@diagnostic disable: undefined-field
local logger = require("dave_logger:logger")("RetroComputers")

local config = {}

local global_path = "config:retro_computers/config.toml"
local local_path = "world:retro_computers/config.toml"

local default = [==[
[machine.ibm_xt]
video = "cga"
postcard = false
[[machine.ibm_xt.rom]]
filename = "GLABIOS_0.2.5_8E.ROM"
addr = 0xFE000
]==]

function config.initialize()
    local data = {}
    local default_data = toml.parse(default)

    logger:info("Config: Loading...")

    if file.exists(local_path) then
        data = toml.parse(file.read(local_path))
    elseif file.exists(global_path) then
        data = toml.parse(file.read(global_path))
    else
        local success, reason = pcall(file.write, global_path, default)

        if not success then
            logger:error("Config: Creating error: %s", reason)
        end
    end

    table.merge(data, default_data)
    table.merge(config, data)
end

return config
