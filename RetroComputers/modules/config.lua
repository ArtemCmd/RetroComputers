local logger = require("retro_computers:logger")

local config = {}
local global_path = pack.data_file("retro_computers", "config.json")
local local_path = pack.shared_file("retro_computers", "config.json")
local default = {
    screen_keyboard_delay = 80,
    -- ibm_xt_use_ega = true
    -- bios_tests_enable = false
}

function config.save()
    logger:info("Config: Saving")
    local data = {}
    for key, value in pairs(config) do
        if  type(config[value]) ~= "function" then
            data[key] = value
        end
    end
    file.write(global_path, data)
end

function config.load()
    logger:info("Config: Loading")

    local data
    if file.exists(local_path) then
        -- logger:debug("Config: Local loaded")
        data = json.parse(file.read(local_path))
    elseif file.exists(global_path) then
        -- logger:debug("Config: Global loaded")
        data = json.parse(file.read(global_path))
    else
        logger:info("Config: Creating config")
        file.write(global_path, json.tostring(default, true))
    end

    setmetatable(config, {
        __index = function (t, key)
            if data[key] then
                return data[key]
            elseif default[key] then
                return default[key]
            else
                logger:error("Config: Unknown key %s", tostring(key))
            end
        end,
    })
end

return config