---@diagnostic disable: undefined-field
local logger = require("retro_computers:logger")

local manager = {}
local disks = {}
local last_id = 1

local function add_floppy(path, packid, name, readonly, iconid, caption)
    local item_path = packid .. ":items/floppy_" .. name .. ".json"

    if not file.exists(item_path) then
        local item = {
            ["icon-type"] = "sprite",
            ["icon"] = "items:floppy_" .. iconid,
            ["stack-size"] = 1,
            ["caption"] = caption,
        }

        local ok, result = pcall(file.write, item_path, json.tostring(item, true))

        if not ok then
            local new_item_path = "world:data/retro_computers/items/floppy_" .. name .. ".json"
            logger.error("DriveManager: Item creation failed, saved in \"world:data/retro_computers/items/floppy_%s\"", name)

            if not file.exists(new_item_path) then
                file.write(new_item_path, json.tostring(item, true))
            end
        end
    end

    local floppy = {
        path = path,
        name = name,
        readonly = readonly
    }

    disks[name] = floppy
    last_id = last_id  + 1

    logger.info("DriveManager: Floppy \"%s\" added", caption)
end

local function load_floppy(path)
    local packid = string.split(path, ":")[1]
    local data = json.parse(file.read(path .. "/floppy.json"))

    if data.name then
        local name = data.name or ("FLoppy " .. last_id)
        local filename = data.filename or "Disk1.img"
        local readonly = data.readonly or false
        local caption = data.caption or name

        if (type(name) == "table") and (type(filename) == "table") then
            if #name == #filename then
                local icon_id = math.random(1, 6)

                for i = 1, #name, 1 do
                    local floppy_path = path .. "/" .. filename[i]

                    if file.exists(floppy_path) then
                        add_floppy(floppy_path, packid, name[i], readonly, icon_id, caption[i])
                    end
                end
            end
        else
            local floppy_path = path .. "/" .. filename

            if file.exists(floppy_path) then
                add_floppy(floppy_path, packid, name, readonly, math.random(1, 6), caption)
            end
        end
    else
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