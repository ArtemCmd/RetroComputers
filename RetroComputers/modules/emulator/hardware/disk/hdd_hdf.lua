-- HDF (Hard Disk File)
-- Byteorder: Big-Endian
-- Signature = "HDF" (ASCII, 3 bytes)
-- Version = "10" (uint16)
-- Reserved (1 byte)
-- Sector size (uint16)
-- Cylinders (uint16)
-- Heads (uint16)
-- Sectors (uint16)
-- RAW DISK DATA

local filesystem = require("retro_computers:emulator/filesystem")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local hdf = {}

function hdf.new(path, cylinders, heads, sectors, sector_size)
    local stream = filesystem.open(path, true)
    local disk_size = sector_size * cylinders * heads * sectors
    local disk_info = byteutil.pack(">HHHH", sector_size, cylinders, heads, sectors)

    stream:write_bytes({72, 68, 70}) -- Signature
    stream:write_bytes({1, 1}) -- Version
    stream:write(0) -- Reserved
    stream:write_bytes(disk_info)

    for _ = 1, disk_size, 1 do
        stream:write(0)
    end

    stream:flush()
end

function hdf.load(path)
    local stream = filesystem.open(path, false)
    local signature = stream:read_bytes(3)

    if (signature[1] == 72) and (signature[2] == 68) and (signature[3] == 70) then
        local version = stream:read_bytes(2)

        if (version[1] == 1) and (version[2] == 1) then
            local type = stream:read()

            if type == 0 then
                local sector_size, cylinders, heads, sectors = byteutil.unpack(">HHHH", stream:read_bytes(8))

                local disk = {
                    sector_size = sector_size,
                    cylinders = cylinders,
                    heads = heads,
                    sectors = sectors,
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
                error("Unsupported HDF type")
            end
        else
            error("Unsupported HDF version")
        end
    else
        error("File " .. path .. " is not HDF")
    end
end

return hdf