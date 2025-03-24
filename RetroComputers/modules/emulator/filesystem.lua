local logger = require("retro_computers:logger")

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local filesytem = {}
local files = {}

function filesytem.open(path, nocache)
    local handler = {
        pos = 1,
        get_position = function(self)
            return self.pos
        end,
        set_position = function(self, pos)
            self.pos = pos + 1
        end,
        read = function(self)
            local byte =  self.buffer[self.pos]
            self.pos = self.pos + 1
            return byte
        end,
        read_bytes = function(self, count)
            local bytes = {}

            for i = 1, count or #self.buffer, 1 do
                bytes[i] = self.buffer[self.pos]
                self.pos = self.pos + 1
            end

            return bytes
        end,
        read_uint16 = function(self, order)
            local bytes = self:read_bytes(2)

            if order == "LE" then
               return bor(bytes[1], lshift(bytes[2], 8))
            end

            return bor(bytes[2], lshift(bytes[1], 8))
        end,
        read_uint32 = function(self, order)
            local bytes = self:read_bytes(4)

            if order == "LE" then
               return bor(bor(bor(bytes[1], lshift(bytes[2], 8)), lshift(bytes[3], 16)), lshift(bytes[4], 32))
            end

            return bor(bor(bor(bytes[4], lshift(bytes[3], 8)), lshift(bytes[2], 16)), lshift(bytes[1], 32))
        end,
        read_string = function(self)
            local result = {}

            while true do
                local byte = self:read()

                if byte then
                    if byte == 0 then
                        break
                    end

                    result[#result+1] = string.char(byte)
                else
                    break
                end
            end

            return table.concat(result)
        end,
        write = function(self, byte)
            self.buffer[self.pos] = byte
            self.pos = self.pos + 1
        end,
        write_bytes = function(self, bytes)
            for i = 1, #bytes, 1 do
                self.buffer[self.pos] = bytes[i]
                self.pos = self.pos + 1
            end
        end,
        write_uint16 = function(self, value, order)
            if order == "LE" then
                self:write(band(value, 0xFF))
                self:write(rshift(value, 8))
            else
                self:write(rshift(value, 8))
                self:write(band(value, 0xFF))
            end
        end,
        write_uint32 = function(self, value, order)
            if order == "LE" then
                self:write(band(value, 0xFF))
                self:write(band(rshift(value, 8), 0xFF))
                self:write(band(rshift(value, 16), 0xFF))
                self:write(band(rshift(value, 24), 0xFF))
            else
                self:write(band(rshift(value, 24), 0xFF))
                self:write(band(rshift(value, 16), 0xFF))
                self:write(band(rshift(value, 8), 0xFF))
                self:write(band(value, 0xFF))
            end
        end,
        write_string = function(self, str)
            for i = 1, #str, 1 do
                self:write(string.byte(str:sub(i, i)))
            end

            self:write(0)
        end,
        flush = function(self)
            if file.is_writeable(path) then
                file.write_bytes(path, self.buffer)
            end
        end,
        close = function(self)
            self:flush()
            files[path] = nil
        end,
        get_buffer = function(self)
            return self.buffer
        end
    }

    if files[path] then
        handler.buffer = files[path]
    elseif file.exists(path) then
        local ok, result = pcall(file.read_bytes, path)

        if ok then
            handler.buffer = result
        else
            return nil
        end

    else
        handler.buffer = {}
    end

    if (not nocache) and (not files[path]) then
        files[path] = handler.buffer
    end

    return handler
end

return filesytem