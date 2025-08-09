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
filename = "GLABIOS_0.2.6_8E.ROM"
addr = 0xFE000
]==]

local function error_handler(message)
    logger:error("Config: Failed to load config file: %s", message)
    print(debug.traceback())
end

local function merge(table1, table2)
    for key, val in pairs(table2) do
        if type(val) == "table" then
            if table1[key] == nil then
                table1[key] = {}
            end

            merge(table1[key], val)
        elseif table1[key] == nil then
            table1[key] = val
        end
    end
end

function config.initialize()
    local data = {}
    local default_data = toml.parse(default)

    logger:info("Config: Loading...")

    xpcall(function()
        if file.exists(local_path) then
            data = toml.parse(file.read(local_path))
        elseif file.exists(global_path) then
            data = toml.parse(file.read(global_path))
        else
            file.write(global_path, default)
        end
    end, error_handler)

    merge(data, default_data)
    table.merge(config, data)
end

return config
