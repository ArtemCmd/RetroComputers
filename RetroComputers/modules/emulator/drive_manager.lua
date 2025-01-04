---@diagnostic disable: undefined-field
local logger = require("retro_computers:logger")
local config = require("retro_computers:config")
local filesystem = require("retro_computers:emulator/filesystem")
local hdf = require("retro_computers:emulator/file_formats/hdf")

local manager = {}
local searcher_paths = {}
local floppys = {}
local last_id = 1

local function add_floppy(path, packid, name, readonly, filename, iconid)
    local path_to_item = packid[1] .. ":items/floppy_" .. name .. ".json"

    if not file.exists(path_to_item) then
        local item = {
            ["icon-type"] = "sprite",
            ["icon"] = "items:floppy_" .. iconid,
            ["stack-size"] = 1
        }

        file.write(path_to_item, json.tostring(item, true))
    end

    local floppy = {
        name = name,
        filename = path .. "/" .. filename,
        readonly = readonly
    }

    floppys[name] = floppy
    last_id = last_id  + 1

    logger:info("DriveManager: Floppy \"%s\" added", name)
end

local function load_floppy(path)
    local packid = string.split(path, ":")
    local settings = json.parse(file.read(path .. "/floppy.json"))
    local name = settings.name or ("FLoppy " .. last_id)
    local filename = settings.filename or "Disk1.img"
    local readonly = settings.readonly or false

    if (type(name) == "table") and (type(filename) == "table") then
        if #name == #filename then
            local icon_id = math.random(1, 6)

            for key, value in pairs(name) do
                if file.exists(path .. "/" .. filename[key]) then
                    add_floppy(path, packid, value, readonly, filename[key], icon_id)
                end
            end
        end
    else
        if file.exists(path .. "/" .. filename) then
            add_floppy(path, packid, name, readonly, filename, math.random(1, 6))
        end
    end
end

function manager.load_floppys()
    logger:info("DriveManager: Loading floppy disks...")

    if config.auto_search_floppys then
        local packs = pack.get_installed()

        for _, content in pairs(packs) do
            local path = content .. ":disks"

            if file.exists(path) then
                searcher_paths[#searcher_paths + 1] = path
            end
        end
    else
        searcher_paths = config.floppy_paths
    end

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

function manager.create_hard_disk(path, cylinders, headers, sectors, sector_size, format)
    logger:debug("DriveManager: Creating hard disk, CHS = %d, %d, %d, sector size = %d, format = %s", cylinders, headers, sectors, sector_size, format)

    if format == "hdf" then
        hdf.new(path, cylinders, headers, sectors, sector_size)
    elseif format == "raw" then
        local handler = filesystem.open(path)
        local disk_size = sector_size * cylinders * headers * sectors

        for _ = 1, disk_size, 1 do
            handler:write(0)
        end

        handler:flush()
    else
        logger:error("DriveManager: Creating hard disk error: Unknown file format")
        return false
    end

    return true
end

function manager.load_drive(path)
    local extension = string.lower(path:sub(-3, -1))

    if extension == "hdf" then
        return hdf.load(path)
    elseif (extension == "img") or (extension == "ima") then
        local drive = {
            handler = filesystem.open(path)
        }
        return drive
    else
        logger:error("DriveManager: Loading drive error: Unknown file format")
    end
end

function manager.get_floppy(name)
    return floppys[name]
end

return manager