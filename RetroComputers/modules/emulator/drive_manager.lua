---@diagnostic disable: undefined-field
local logger = require("dave_logger:logger")("RetroComputers")

local manager = {}
local disks = {}
local count = 0

local function add_floppy(path, packid, name, readonly, iconid, caption)
    local floppy = {
        path = path,
        name = name,
        readonly = readonly
    }

    disks[name] = floppy
    count = count + 1

    if not file.exists(string.format("%s:items/floppy_%s.json", packid, name)) then
        local item = {
            ["icon-type"] = "sprite",
            ["icon"] = "items:floppy_" .. iconid,
            ["stack-size"] = 1,
            ["caption"] = caption
        }

        file.write(string.format("world:data/retro_computers/items/floppy_%s.json", name), json.tostring(item, true))
    end

    logger:info("DriveManager: Floppy \"%s\" loaded", caption)
end

local function load_floppy(path)
    local packid, _ = parse_path(path)
    local data = json.parse(file.read(path .. "/floppy.json"))
    local icon_id = math.random(0, 15)

    if data.caption then -- Converting
        local new_data = {}

        for i = 1, #data.caption, 1 do
            new_data[i] = {
                caption = data.caption[i],
                name = data.name[i],
                filename = data.filename[i]
            }

            file.write(path, json.tostring(new_data, true))
        end

        return
    end

    for _, floppy in pairs(data) do
        local name = floppy.name
        local caption = floppy.caption or name
        local filename = floppy.filename or "floppy.img"
        local readonly = floppy.readonly or false
        local floppy_path = path .. "/" .. filename

        if file.exists(floppy_path) then
            add_floppy(floppy_path, packid, name, readonly, icon_id, caption)
        end
    end
end

function manager.initialize()
    logger:info("DriveManager: Loading floppy disks...")

    local packs = pack.get_installed()
    local start_time = os.clock()

    for i = 1, #packs, 1 do
        local disks_path = packs[i] .. ":disks"

        if file.exists(disks_path) then
            local floppy_disks = file.list(disks_path)

            for j = 1, #floppy_disks, 1 do
                local floppy_path = floppy_disks[j] .. "/floppy.json"

                if file.exists(floppy_path) then
                    load_floppy(floppy_disks[j])
                end
            end
        end
    end

    logger:info("DriveManager: Loaded %d floppy disks in %d milliseconds", count, (os.clock() - start_time) * 1000)
end

function manager.get_floppy(name)
    return disks[name]
end

return manager
