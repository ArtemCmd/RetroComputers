local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local filesytem = {}
local files = {}

function filesytem.open(path, mode, nocache)
    if (mode == "r") then
        if  (not files[path]) and (not file.exists(path)) then
            return nil
        end
    end

    local stream = {
        filename = path,
        mode = mode,
        pos = 1,
        advance = function(self, offset)
            self.pos = self.pos + offset
        end,
        get_mode = function(self)
            return self.mode
        end,
        get_filename = function(self)
            return self.filename
        end,
        get_position = function(self)
            return self.pos - 1
        end,
        set_position = function(self, pos)
            self.pos = pos + 1
        end,
        read_byte = function(self)
            local byte =  self.buffer[self.pos]
            self.pos = self.pos + 1
            return byte
        end,
        write_byte = function(self, byte)
            self.buffer[self.pos] = byte
            self.pos = self.pos + 1
        end,
        read_bytes = function(self, count)
            if not count then
                return self.buffer
            end

            local bytes = {}

            for i = 1, count, 1 do
                bytes[i] = self.buffer[self.pos]
                self.pos = self.pos + 1
            end

            return bytes
        end,
        write_bytes = function(self, bytes)
            for i = 1, #bytes, 1 do
                self.buffer[self.pos] = bytes[i]
                self.pos = self.pos + 1
            end
        end,
        read_uint16_l = function(self)
            local low = self:read_byte()
            local high = self:read_byte()
            return bor(low, lshift(high, 8))
        end,
        write_uint16_l = function(self, val)
            self:write_byte(band(val, 0xFF))
            self:write_byte(band(rshift(val, 8), 0xFF))
        end,
        read_uint32_l = function(self)
            local low = self:read_uint16_l()
            local high = self:read_uint16_l()
            return bor(low, lshift(high, 8))
        end,
        write_uint32_l = function(self, value)
            self:write_byte(band(value, 0xFF))
            self:write_byte(band(rshift(value, 8), 0xFF))
            self:write_byte(band(rshift(value, 16), 0xFF))
            self:write_byte(band(rshift(value, 24), 0xFF))
        end,
        read_string = function(self, count)
            local result = {}

            for i = 1, count, 1 do
                local byte = self:read()

                if not byte then
                    return table.concat(result)
                end

                result[i] = string.char(byte)
            end

            return table.concat(result)
        end,
        write_string = function(self, str)
            for i = 1, #str, 1 do
                self:write_byte(string.byte(str:sub(i, i)))
            end
        end,
        read_asciiz = function(self)
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
        write_asciiz = function(self, str)
            for i = 1, #str, 1 do
                self:write_byte(string.byte(str:sub(i, i)))
            end

            self:write_byte(0)
        end,
        flush = function(self)
            if file.is_writeable(path) then
                file.write_bytes(self.filename, self.buffer)
            end
        end,
        close = function(self)
            self:flush()
            files[path] = nil
        end
    }

    if mode == "w" then
        stream.buffer = {}
    elseif mode == "r" then
        if files[path] then
            stream.buffer = files[path]
        else
            local ok, result = pcall(file.read_bytes, path)

            if ok then
                stream.buffer = result
            else
                return nil
            end
        end
    end

    if (not nocache) and (not files[path]) then
        files[path] = stream.buffer
    end

    return stream
end

return filesytem
