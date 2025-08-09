local logger = require("dave_logger:logger")("RetroComputers")

local blocks = {}
local DATA_PATH = "world:data/retro_computers/blocks.json"
local edited = false
local data

local function get_key(x, y, z)
    return string.format("%d:%d:%d", x, y, z)
end

function blocks.registry(x, y, z, type)
    edited = true
    data[get_key(x, y, z)] = {type = type or "unknown", fields = {}}
end

function blocks.unregistry(x, y, z)
    edited = true
    data[get_key(x, y, z)] = nil
end

function blocks.get_field(x, y, z, name)
    local blk = data[get_key(x, y, z)]

    if blk then
        return blk.fields[name]
    end
end

function blocks.set_field(x, y, z, name, value)
    local blk = data[get_key(x, y, z)]

    if blk then
        blk.fields[name] = value
        edited = true
    end
end

function blocks.get(x, y, z)
    return data[get_key(x, y, z)]
end

function blocks.get_blocks()
    return data
end

function blocks.initialize()
    if file.exists(DATA_PATH) then
        local success, result = pcall(json.parse, file.read(DATA_PATH))

        if not success then
            data = {}
            logger:error("Blocks: Failed to load block data: %s", result)
        else
            data = result
        end
    else
        data = {}
    end
end

function blocks.save()
    if edited then
        file.write(DATA_PATH, json.tostring(data, false))
    end
end

return blocks
