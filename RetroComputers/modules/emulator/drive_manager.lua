---@diagnostic disable: undefined-field
local logger = require("retro_computers:logger")

local manager = {}
local disks = {}

local function pwrite(path, data)
    local ok, result = pcall(file.write, path, data)

    if not ok then
        logger.error("DriveManager: Item creation failed, %s", path)
    end
end

local function add_floppy(path, packid, name, readonly, iconid, caption)
    local item_path = packid .. ":items/floppy_" .. name .. ".json"

    if not file.exists(item_path) then
        local item = {
            ["icon-type"] = "sprite",
            ["icon"] = "items:floppy_" .. iconid,
            ["stack-size"] = 1,
            ["caption"] = caption,
        }

        if not file.is_writeable(item_path) then
            -- :(
            -- pack.request_writeable(packid, function(entry_point)
            --     item_path = string.replace(item_path, packid, entry_point)
            --     pwrite(item_path, json.tostring(item, true))
            -- end)
        else
            pwrite(item_path, json.tostring(item, true))
        end
    end

    local floppy = {
        path = path,
        name = name,
        readonly = readonly
    }

    disks[name] = floppy

    logger.info("DriveManager: Floppy \"%s\" added", caption)
end

local function load_floppy(path)
    local packid = string.split(path, ":")[1]
    local data = json.parse(file.read(path .. "/floppy.json"))

    for _, floppy in pairs(data) do
        local name = floppy.name
        local caption = floppy.caption or name
        local filename = floppy.filename or "floppy.img"
        local readonly = floppy.readonly or false
        local floppy_path = path .. "/" .. filename

        if file.exists(floppy_path) then
            add_floppy(floppy_path, packid, name, readonly, math.random(1, 6), caption)
        end
    end
end

function manager.load()
    logger.info("DriveManager: Loading floppy disks...")

    local packs = pack.get_installed()

    for i = 1, #packs, 1 do
        local disks_path = packs[i] .. ":disks"

        if file.exists(disks_path) then
            local floppy_disks = file.list(disks_path)

            for i = 1, #floppy_disks, 1 do
                local floppy_path = floppy_disks[i] .. "/floppy.json"

                if file.exists(floppy_path) then
                    load_floppy(floppy_disks[i])
                end
            end
        end
    end
end

function manager.get_floppy(name)
    return disks[name]
end

return manager