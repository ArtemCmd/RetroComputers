local logger = require("dave_logger:logger")("RetroComputers")
local filesystem = require("retro_computers:emulator/filesystem")
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local memory = {}

local function set_memory_map(self, addr, size, read_func, write_func)
end

local function remove_memory_map(self, addr, size)
end


local function read8(self, addr)
    return self.data[band(addr, self.mask)]
end

local function write8(self, addr, val)
    self.data[band(addr, self.mask)] = val
end

local function read16_l(self, addr)
    return bor(self:read8(addr), lshift(self:read8(addr + 1), 8))
end

local function read32_l(self, addr)
    return bor(bor(bor(self:read8(addr), lshift(self:read8(addr + 1), 8)), lshift(self:read8(addr + 2), 16)), lshift(self:read8(addr + 3), 32))
end

local function write16_l(self, addr, val)
    self:write8(addr, band(val, 0xFF))
    self:write8(addr + 1, band(rshift(val, 8), 0xFF))
end

local function write32_l(self, addr, val)
    self:write8(addr, band(val, 0xFF))
    self:write8(addr + 1, band(rshift(val, 8), 0xFF))
    self:write8(addr + 2, band(rshift(val, 16), 0xFF))
    self:write8(addr + 3, band(rshift(val, 24), 0xFF))
end

local function write_bytes(self, addr, bytes)
    for i = 0, #bytes - 1, 1 do
        self:write8(addr + i, bytes[i + 1])
    end
end

local function load_rom(self, addr, path)
    local stream = filesystem.open(path, "r", false)

    if stream then
        local data = stream:read_bytes()
        self:write_bytes(addr, data)
    else
        logger:error("ROM \"%s\" not found", path)
    end
end

local function reset(self)
    for i = 0, self.size - 1, 1 do
        self:write8(i, 0x00)
    end
end

function memory.new(size, mask)
    local self = {
        mask = mask or (size - 1),
        size = size,
        data = {},
        set_memory_map = set_memory_map,
        remove_memory_map = remove_memory_map,
        read8 = read8,
        read16_l = read16_l,
        read32_l = read32_l,
        write8 = write8,
        write16_l = write16_l,
        write32_l = write32_l,
        write_bytes = write_bytes,
        load_rom = load_rom,
        reset = reset
    }

    return self
end

return memory
