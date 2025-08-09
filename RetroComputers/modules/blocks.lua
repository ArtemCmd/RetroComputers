local blocks = {}
local list
local PATH = "world:data/retro_computers/blocks.json"
local edited = false

local function get_key(x, y, z)
    return string.format("%d:%d:%d", x, y, z)
end

function blocks.registry(x, y, z, type)
    edited = true
    list[get_key(x, y, z)] = {type = type or "unknown", fields = {}}
end

function blocks.unregistry(x, y, z)
    edited = true
    list[get_key(x, y, z)] = nil
end

function blocks.get(x, y, z)
    return list[get_key(x, y, z)]
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
        edited = true
    end
end

function blocks.initialize()
    if file.exists(PATH) then
        list = json.parse(file.read(PATH))
    else
        list = {}
    end
end

function blocks.save()
    if edited then
        file.write(PATH, json.tostring(list, false))
    end
end

return blocks
