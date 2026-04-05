local logger = require("dave_logger:logger")("RetroComputers")

local config = {}

local global_path = "config:retro_computers/config.toml"
local local_path = "world:retro_computers/config.toml"

local function error_handler(message)
    logger:error("Config: Failed to load config file: %s\n%s", message, debug.traceback())
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
    local default = file.read("retro_computers:default.toml")
    local default_data = toml.parse(default)

    logger:info("Config: Loading...")

    local start = os.clock()

    xpcall(function()
        if file.exists(local_path) then
            data = toml.parse(file.read(local_path))
        elseif file.exists(global_path) then
            data = toml.parse(file.read(global_path))
        else
            file.write(global_path, default)
        end
    end, error_handler)

    logger:info("Config: Loaded in %d milliseconds", (os.clock() - start) * 1000)

    merge(data, default_data)
    table.merge(config, data)
end

return config
