---@diagnostic disable: undefined-field
local logger = require("retro_computers:logger")

local config = {}
local global_path = pack.shared_file("retro_computers", "config.json")
local local_path = pack.data_file("retro_computers", "config.json")
local default = {
    enable_screen_3d = true,
    save_state = false,
    post_card = false,
    screen_keyboard_delay = 80,
    screen = {
        renderer_delay = 0.1,
        draw_text_background = false,
        scale = 1.0
    },
    ibm_xt = {
        rom = {{filename = "GLABIOS_0.2.5_8E.ROM", addr = 0xFE000}},
        video = "cga" -- MDA / CGA / Hercules
    }
}

function config.save()
    logger.info("Config: Saving")

    local data = {}

    for key, value in pairs(config) do
        if  type(value) ~= "function" then
            data[key] = value
        end
    end

    if file.exists(local_path) then
        file.write(local_path, json.tostring(data, true))
    else
        file.write(global_path, json.tostring(data, true))
    end
end

function config.load()
    local data = {}

    if file.exists(local_path) then
        logger.info("Config: Local loaded")
        data = json.parse(file.read(local_path))
    elseif file.exists(global_path) then
        logger.info("Config: Global loaded")
        data = json.parse(file.read(global_path))
    else
        logger.info("Config: Creating config")
        file.write(global_path, json.tostring(default, true))
    end

    for key, value in pairs(default) do
        if type(value) == "table" then
            config[key] = {}

            if data[key] ~= nil then
                for key2, value2 in pairs(value) do
                    if data[key][key2] ~= nil then
                        config[key][key2] = data[key][key2]
                    else
                        config[key][key2] = value2
                    end
                end
            else
                for key2, value2 in pairs(value) do
                    config[key][key2] = value2
                end
            end
        else
            if data[key] ~= nil then
                config[key] = data[key]
            else
                config[key] = value
            end
        end
    end

    setmetatable(config, {
        __index = function (t, key)
            if rawget(config, key) ~= nil then
                return rawget(config, key)
            else
                logger.error("Config: Unknown key %s", tostring(key))
            end
        end
    })
end

function config.reset()
    for key, value in pairs(default) do
        if type(value) == "table" then
            config[key] = table.copy(value)
        else
            config[key] = value
        end
    end
end

return config