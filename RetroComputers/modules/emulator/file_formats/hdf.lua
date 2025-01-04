-- HDF (Hard Disk File)
-- Structure:
-- Signature "HDF" (ASCII, 3 bytes)
-- Version "10" (2 bytes, uint16, LE)
-- Type "00" (1 byte)
-- Sector size (2 bytes, uint16, LE)
-- Cylinders (2 bytes, uint16, LE)
-- Heads (2 bytes, uint16, LE)
-- Sectors (2 bytes, uint16, LE)
-- RAW DISK DATA

local filesystem = require("retro_computers:emulator/filesystem")
local bit_converter = require("core:bit_converter")

local hdf = {}

function hdf.new(path, cylinders, heads, sectors, sector_size)
    local stream = filesystem.open(path)
    stream:write_bytes({72, 68, 70}) -- Signature
    stream:write_bytes({1, 0}) -- Version
    stream:write(0) -- Type
    stream:write_bytes(bit_converter.uint16_to_bytes(sector_size)) -- Sector size
    stream:write_bytes(bit_converter.uint16_to_bytes(cylinders)) -- Cylinders
    stream:write_bytes(bit_converter.uint16_to_bytes(heads)) -- Heads
    stream:write_bytes(bit_converter.uint16_to_bytes(sectors)) -- Sectors
    local disk_size = sector_size * cylinders * heads * sectors

    for _ = 1, disk_size, 1 do
        stream:write(0)
    end

    stream:close()
end

function hdf.load(path)
    local handler = filesystem.open(path)
    handler:set_position(0)
    local signature = handler:read(3)

    if (signature[1] == 72) and (signature[2] == 68) and (signature[3] == 70) then
        local version = handler:read(2)
        if ((version[1] == 49) and (version[2] == 48)) or ((version[1] == 1) and (version[2] == 0)) then
            local type = handler:read(1)
            if type[1] == 0 then
                local disk = {
                    sector_size = bit_converter.bytes_to_uint16(handler:read(2)),
                    cylinders = bit_converter.bytes_to_uint16(handler:read(2)),
                    heads = bit_converter.bytes_to_uint16(handler:read(2)),
                    sectors = bit_converter.bytes_to_uint16(handler:read(2)),
                    handler = {
                        set_position = function (self, pos)
                            handler:set_position(14 + pos)
                        end,
                        read = function (self, n)
                            return handler:read(n)
                        end,
                        write = function (self, byte)
                            handler:write(byte)
                        end,
                        flush = function (self)
                            handler:flush()
                        end
                    }
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