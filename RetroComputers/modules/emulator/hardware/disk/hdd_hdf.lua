-- |-----------------------|--------|-------|
-- | HDF (Hard Disk File)  | Type   | Value |
-- | Byteorder: Big-Endian |        |       |
-- |-----------------------|--------|-------|
-- | Signature             | ASCII  | "HDF" |
-- | Version = "10" (uint16| uint16 |       |
-- | Reserved              | int8   | 0     |
-- | Sector size           | uint16 |       |
-- | Cylinders             | uint16 |       |
-- | Heads                 | uint16 |       |
-- | Sectors               | uint16 |       |
-- | Disk data             | bytes  |       |
-- |-----------------------|--------|-------|

local filesystem = require("retro_computers:emulator/filesystem")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local hdf = {}

local HDF_SIGNATURE = {0x48, 0x44, 0x46}
local HDF_VERSION = {1, 1}
local HDF_RESERVED = 0

function hdf.new(path, cylinders, heads, sectors, sector_size)
    local stream = filesystem.open(path, "w", true)
    local disk_size = sector_size * cylinders * heads * sectors
    local disk_info = byteutil.pack(">HHHH", sector_size, cylinders, heads, sectors)

    stream:write_bytes(HDF_SIGNATURE)
    stream:write_bytes(HDF_VERSION)
    stream:write_byte(HDF_RESERVED)
    stream:write_bytes(disk_info)

    for _ = 1, disk_size, 1 do
        stream:write_byte(0)
    end

    stream:flush()
end

function hdf.load(path)
    local stream = filesystem.open(path, "r", false)

    if stream then
       local signature = stream:read_bytes(3)

        if (signature[1] == HDF_SIGNATURE[1]) and (signature[2] == HDF_SIGNATURE[2]) and (signature[3] == HDF_SIGNATURE[3]) then
            local version = stream:read_bytes(2)

            if (version[1] == HDF_VERSION[1]) and (version[2] == HDF_VERSION[2]) then
                local reserved = stream:read_byte()

                if reserved == 0 then
                    local sector_size, cylinders, heads, sectors = byteutil.unpack(">HHHH", stream:read_bytes(8))

                    local disk = {
                        sector_size = sector_size,
                        cylinders = cylinders,
                        heads = heads,
                        sectors = sectors,
                        format = function(self, addr, count)
                            stream:set_position(lshift(addr, 9) + 14)

                            for _ = 1, count, 1 do
                                for _ = 1, 512, 1 do
                                    stream:write_byte(0x00)
                                end
                            end
                        end,
                        read_sector = function(self, addr)
                            stream:set_position(lshift(addr, 9) + 14)
                            return stream:read_bytes(sector_size)
                        end,
                        write_sector = function(self, addr, data)
                            stream:set_position(lshift(addr, 9) + 14)
                            stream:write_bytes(data)
                        end,
                        save = function(self)
                            stream:flush()
                        end
                    }

                    return disk
                else
                    error("Invalid HDF file.")
                end
            else
                error("Unsupported HDF version.")
            end
        else
            error(string.format("File \"%s\" is not HDF.", path))
        end
    else
        error("File not found: " .. path)
    end
end

hdf.create = hdf.new

return hdf
