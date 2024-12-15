local logger = require("retro_computers:logger")

local config = {}
local global_path = pack.shared_file("retro_computers", "config.json")
local local_path = pack.data_file("retro_computers", "config.json")
local default = {
    screen_keyboard_delay = 80,
    auto_search_floppys = true,
    floppy_paths = {"retro_computers:disks"},
    page_width = 200,
    page_height = 300,
    create_page_item = false,
    font_scale = 1.0,
    check_for_updates = false,
    enable_screen_3d = true
}

function config.save()
    logger:info("Config: Saving")
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
    logger:info("Config: Loading")
    local data = {}
    if file.exists(local_path) then
        logger:info("Config: Local loaded")
        data = json.parse(file.read(local_path))
    elseif file.exists(global_path) then
        logger:info("Config: Global loaded")
        data = json.parse(file.read(global_path))
    else
        logger:info("Config: Creating config")
        file.write(global_path, json.tostring(default, true))
    end

    for key, value in pairs(default) do
        if data[key] ~= nil then
            config[key] = data[key]
        else
            config[key] = value
        end
    end

    setmetatable(config, {
        __index = function (t, key)
            if rawget(config, key) ~= nil then
                return rawget(config, key)
            else
                logger:error("Config: Unknown key %s", tostring(key))
            end
        end
    })
end

return config