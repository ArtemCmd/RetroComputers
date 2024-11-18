---@diagnostic disable: undefined-field
local logger = require("retro_computers:logger")
local config = require("retro_computers:config")

local manager = {}
local searcher_paths = {}
local lastid = 1
local floppys = {}
local items_path = "retro_computers:items/"

local function load_floppy(path)
    local packid = string.split(path, ":")
    local settings = json.parse(file.read(path .. "/floppy.json"))
    local name = settings.name or ("FLoppy " .. lastid)
    local filename = settings.filename or "disk1.img"
    local readonly = settings.readonly or false
    if file.exists(path .. "/" .. filename) then
        if not file.exists(items_path .. "floppy_" .. name .. ".json") then
            -- logger:debug("DriveManager: Creating item")
            local item = {
                ["icon-type"] = "sprite",
                ["icon"] = "items:floppy"
            }
            file.write("retro_computers:items/floppy_" .. name .. ".json", json.tostring(item, true))
        end
        local floppy = {
            name = name,
            filename = path .. "/" .. filename,
            readonly = readonly
        }
        floppys[name] = floppy
        lastid = lastid  + 1
        logger:info("DriveManager: DriveManager: Floppy \"%s\" added", name)
    end
end

function manager.load_floppys()
    logger:info("DriveManager: Loading floppy disks...")
    searcher_paths = config.floppy_paths
    for _, path in pairs(searcher_paths) do
        if file.exists(path) then
            local dirs = file.list(path)
            if #dirs > 0 then
                for _, dir in pairs(dirs) do
                    if file.isdir(dir) then
                        -- logger:debug("DriveManager: Search floppy disks in %s", dir)
                        if file.exists(dir .. "/floppy.json") then
                            -- logger:debug("DriveManager: Found floppy disk in %s", dir)
                            load_floppy(dir)
                        end
                    end
                end
            end
        end
    end
end

function manager.get_floppy(name)
    return floppys[name]
end

return manager