local logger = require("retro_computers:logger")
local blocks = {}
local list = {}
local current_block
local PATH = pack.data_file("retro_computers", "blocks.json")
local edited = false

local function get_key(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

function blocks.registry(x, y, z, type)
    edited = true
    list[get_key(x, y, z)] = {pos = {x, y, z}, type = type or "unknown", fields = {}}
end

function blocks.unregistry(x, y, z)
    edited = true
    list[get_key(x, y, z)] = nil
end

function blocks.get(x, y, z)
    return list[get_key(x, y, z)]
end

function blocks.get_current_block()
    return current_block
end

function blocks.set_current_block(x, y, z)
    if list[get_key(x, y, z)] then
        current_block = list[get_key(x, y, z)]
    else
        logger.warning("Blocks: Block not found!")
    end
end

function blocks.unset_current_block()
    current_block = nil
end

function blocks.get_blocks()
    return list
end

function blocks.get_field(x, y, z, name)
    local blk = list[get_key(x, y, z)]

    if blk then
        return blk.fields[name]
    end
end

function blocks.set_field(x, y, z, name, value)
    local blk = list[get_key(x, y, z)]

    if blk then
        blk.fields[name] = value
    end
end

function blocks.load()
    if file.exists(PATH) then
        list = json.parse(file.read(PATH))
    end
end

function blocks.save()
    if edited then
        file.write(PATH, json.tostring(list, false))
    end
end

return blocks