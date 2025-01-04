local logger = require("retro_computers:logger")
local data_buffer = require("core:data_buffer")

local filesytem = {}
local files = {}

function filesytem.open(path, nocache)
    local handler = {
        get_position = function(self)
            return self.buffer.pos
        end,
        set_position = function(self, pos)
            self.buffer:set_position(pos + 1)
        end,
        read = function(self, count)
            return self.buffer:get_bytes(count)
        end,
        read_bytes = function(self, count)
            return self.buffer:get_bytes(count)
        end,
        write = function(self, byte)
            self.buffer:put_byte(byte)
        end,
        write_bytes = function(self, bytes)
            self.buffer:put_bytes(bytes)
        end,
        flush = function(self)
            file.write_bytes(path, self.buffer:get_bytes())
        end,
        close = function(self)
            self:flush()
            files[path] = nil
        end
    }

    if file.exists(path) then
        local reason, result = pcall(file.read_bytes, path)
        if reason then
            if not nocache then
                files[path] = data_buffer(result)
            end
            handler.buffer = files[path]
        else
            logger:error("Filesytem: File %s load error", path)
            return nil
        end
    elseif files[path] then
        handler.buffer = files[path]
    else
        handler.buffer = data_buffer()
    end

    return handler
end

return filesytem