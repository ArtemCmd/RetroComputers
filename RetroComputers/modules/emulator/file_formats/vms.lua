---@diagnostic disable: undefined-field
-- VMS (Virtual Machine State) Format
-- Signature "VMS" (ASCII, 3 bytes)
-- Version "1" (uint8, LE)
-- Chunks
-- Chunk structure:
-- Header (ASCII, 16 bytes)
-- Chunk size (uint32, LE)

local logger = require("retro_computers:logger")
local filesystem = require("retro_computers:emulator/filesystem")
local bit_converter = require("core:bit_converter")

local vms = {}

function vms.create(path, machine)
    local stream = filesystem.open(path)

    if stream then
        stream:write_bytes({86, 77, 83})
        stream:write(1)

        for name, device in pairs(machine.components) do
            if (device.save ~= nil) then
                local chunk_name = {string.byte(name, 1, -1)}
                logger:debug("VMS: Create chunk: %s", name)

                if #chunk_name > 16 then
                    for i = 1, #chunk_name - 16, 1 do
                        table.remove(chunk_name, i * 3)
                    end
                else
                    for i = #chunk_name + 1, 16, 1 do
                        chunk_name[i] = 0
                    end
                end

                stream:write_bytes(chunk_name)
                device:save(stream)
            end
        end
    end

    stream:flush()
end

function vms.load(path, components)
    local stream = filesystem.open(path)
    local file_size = file.length(path)

    if stream then
        local signature = stream:read(3)
        local version = stream:read(1)

        if (signature[1] == 86) and (signature[2] == 77) and (signature[3] == 83) then
            if version[1] == 1 then
                local chunks = {}

                while stream:get_position() < file_size do
                    local chunk_name = string.replace(string.char(unpack(stream:read(16))), "\0", "")
                    local length = bit_converter.bytes_to_uint32(stream:read(4))

                    if not (chunk_name == '') then
                        logger:debug("VMS: Found chunk: %s, %d, %d", chunk_name, length, stream:get_position())
                    end

                    if components[chunk_name] then
                        chunks[chunk_name] = stream:read(length)
                    end
                end

                for device_name, device in pairs(components) do
                    local chunk = chunks[device_name]

                    if chunk then
                        if device.load ~= nil then
                            logger:debug("VMS: Load chunk: %s", device_name)
                            device:load(chunk)
                        end
                    end
                end
            else
                stream:close()
                error("Unsupported VMS version")
            end
        else
            stream:close()
            error("File is not VMS")
        end
    end

    stream:close()
end

return vms