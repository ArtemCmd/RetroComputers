---@diagnostic disable: undefined-field
local logger = require("dave_logger:logger")("RetroComputers")

local manager = {}
local disks = {}
local count = 0

local function error_handler(message)
    logger:error("DriveManager: Failed to load floppy disk: %s", message)
    print(debug.traceback())
end

local function add_floppy(path, packid, name, readonly, iconid, caption)
    local floppy = {
        path = path,
        name = name,
        readonly = readonly
    }

    disks[name] = floppy
    count = count + 1

    -- if not file.exists(string.format("%s:items/floppy_%s.json", packid, name)) then -- Item generator
    --     local item = {
    --         ["icon-type"] = "sprite",
    --         ["icon"] = "items:floppy_" .. iconid,
    --         ["stack-size"] = 1,
    --         ["caption"] = caption
    --     }

    --     file.write(string.format("world:data/retro_computers/items/floppy_%s.json", name), json.tostring(item, true))
    -- end

    logger:info("DriveManager: Floppy \"%s\" loaded", caption)
end

local function load_floppy(path)
    local packid = file.prefix(path)
    local data = json.parse(file.read(path .. "/floppy.json"))
    local icon_id = math.random(0, 15)

    for i = 1, #data, 1 do
        local floppy_data = data[i]
        local name = floppy_data.name
        local caption = floppy_data.caption or name
        local filename = floppy_data.filename or "floppy.img"
        local readonly = floppy_data.readonly or false
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
                    xpcall(load_floppy, error_handler, floppy_disks[j])
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
