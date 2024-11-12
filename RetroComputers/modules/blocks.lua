local blocks = {}
local list = {}
local current_block
local PATH = pack.data_file("retro_computers", "blocks.json")

local function get_key(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

function blocks.registry(x, y, z, type)
    list[get_key(x, y, z)] = {pos = {x, y, z}, type = type}
end

function blocks.unregistry(x, y, z)
    list[get_key(x, y, z)] = nil
end

function blocks.get(x, y, z)
    return list[get_key(x, y, z)]
end

function blocks.set_current_block(x, y, z)
    if list[get_key(x, y, z)] then
        current_block = list[get_key(x, y, z)]
    end
end

function blocks.get_current_block()
    return current_block
end

function blocks.load()
    if file.exists(PATH) then
        list = json.parse(file.read(PATH))
    end
end

function blocks.save()
    file.write(PATH, json.tostring(list, false))
end

return blocks