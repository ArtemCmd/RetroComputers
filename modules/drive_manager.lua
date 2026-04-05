local logger = require("dave_logger:logger")("RetroComputers")

local manager = {
    DRIVE_TYPE_FLOPPY = 1,
    DRIVE_TYPE_TAPE = 2
}

local drives = {
    [manager.DRIVE_TYPE_FLOPPY] = {},
    [manager.DRIVE_TYPE_TAPE] = {}
}

local DRIVE_TYPES = {
    ["floppy"] = manager.DRIVE_TYPE_FLOPPY,
    ["tape"] = manager.DRIVE_TYPE_TAPE
}

local count = 0

local function error_handler(message)
    logger:error("DriveManager: Failed to load disk: %s\n%s", message, debug.traceback())
end

local function add_drive(packid, name, filename, caption, readonly, icon_id, drive_type)
    local disk_type = DRIVE_TYPES[drive_type]

    if disk_type then
        local drive = {
            caption = caption,
            name = string.format("%s:%s", packid, name),
            path = filename,
            readonly = readonly,
            icon_id = icon_id
        }

        drives[disk_type][drive.name] = drive
        count = count + 1

        logger:info("DriveManager: Disk(%s) \"%s\" loaded", drive_type, caption)
    else
        logger:error("DriveManager: Invalid drive type: %s", drive_type)
    end
end

local function load_drive(path)
    local packid = file.prefix(path)
    local data = json.parse(file.read(path .. "/disk.json"))
    local icon_id = math.random(0, 15)

    for i = 1, #data, 1 do
        local drive_data = data[i]
        local name = drive_data.name
        local drive_type = drive_data.type or "floppy"
        local caption = drive_data.caption or name
        local filename = drive_data.filename or string.format("%s.img", drive_type)
        local readonly = drive_data.readonly or false
        local image_path = string.format("%s/%s", path, filename)

        if file.exists(image_path) then
            add_drive(packid, name, image_path, caption, readonly, icon_id, drive_type)
        end
    end
end

function manager.get_floppy(name)
    return drives[manager.DRIVE_TYPE_FLOPPY][name]
end

function manager.get_tape(name)
    return drives[manager.DRIVE_TYPE_TAPE][name]
end

function manager.get_drives()
    return drives
end

function manager.create_items()
    local data = {}

    for drive_type, disks in pairs(drives) do
        for _, drive in pairs(disks) do
            local pack_id, _ = parse_path(drive.name)
            local array = data[pack_id]

            if not array then
                array = {}
                data[pack_id] = array
            end

            drive.type = (drive_type == manager.DRIVE_TYPE_FLOPPY) and "floppy" or "tape"
            array[#array+1] = drive
        end
    end

    local pack_id, disks = next(data)

    if pack_id and disks then
        local function step()
            pack.request_writeable(pack_id, function(entry_point)
                for i = 1, #disks, 1 do
                    local drive = disks[i]
                    local _, name = parse_path(drive.name)
                    local path = string.format("%s:items/%s_%s.json", entry_point, drive.type, name)

                    if not file.exists(path) then
                        local item = {
                            ["caption"] = drive.caption,
                            ["icon-type"] = "sprite",
                            ["icon"] = string.format("items:%s_%s", drive.type, drive.icon_id),
                            ["stack-size"] = 1
                        }

                        file.write(path, json.tostring(item, true))
                    end

                    drive.type = nil
                end

                pack_id, disks = next(data, pack_id)

                if pack_id and disks then
                    step()
                end
            end)
        end

        step()
    end
end

function manager.initialize()
    logger:info("DriveManager: Loading disks...")

    local packs = pack.get_installed()
    local start_time = os.clock()

    for i = 1, #packs, 1 do
        local disks_path = packs[i] .. ":disks"

        if file.exists(disks_path) then
            local disks = file.list(disks_path)

            for j = 1, #disks, 1 do
                local disk_path = disks[j]

                if file.exists(disk_path .. "/disk.json") then
                    xpcall(load_drive, error_handler, disk_path)
                end
            end
        end
    end

    logger:info("DriveManager: Loaded %d disks in %d milliseconds", count, (os.clock() - start_time) * 1000)
end

return manager
