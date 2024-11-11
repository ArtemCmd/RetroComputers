local logger = require("retro_computers:logger")
local data_buffer = require("core:data_buffer")

local filesytem = {}
local handlers = {}

local function set_position(self, position)
    self.buffer:set_position(position + 1)
end

local function read(self, count)
    return self.buffer:get_bytes(count)
end

local function write(self, bytes)
    self.buffer:put_byte(bytes)
end

local function flush(self)
    file.write_bytes(self.path, self.buffer:get_bytes())
end

function filesytem.open(path)
    if handlers[path] == nil then
        local handle = {path = path}
        if file.exists(path) then
            local reason, result = pcall(file.read_bytes, path)
            if reason then
                handle.buffer = data_buffer(result)
            else
                logger:error("Filesytem: file %s load error", path)
                return nil
            end
        else
            handle.buffer = data_buffer()
        end

        handle.set_position = set_position
        handle.read = read
        handle.write = write
        handle.flush = flush
        handlers[path] = handle
        return handle
    else
        return handlers[path]
    end
end

return filesytem