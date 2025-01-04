local fifo = {}

local function get_count(self)
    if self.buffer_end == self.buffer_start then
        if self.full then
            return self.len
        else
            return 0
        end
    else
        return math.abs(self.buffer_end - self.buffer_start)
    end
end

local function reset(self)
    self.buffer_start = 0
    self.buffer_end = 0
    self.full = false
    self.empty = true
    self.ready = false
end

local function ereset(self)
    self:reset()
    if self.full_event ~= nil then
        self.full_event(self)
    end
    if self.empty_event ~= nil then
        self.empty_event(self)
    end
    if self.ready_event ~= nil then
        self.ready_event(self)
    end
end

local function read(self)
    if not self.empty then
        local result = self.buffer[self.buffer_start]
        self.buffer_start = (self.buffer_start + 1) % self.len

        local count = get_count(self)

        if count < self.trigger_len then
            self.ready = false

            if count == 0 then
                self.empty = true
            end
        end

        return result
    end
    return 0
end

local function eread(self)
    if not self.empty then
        local result = self.buffer[self.buffer_start]
        self.buffer_start = (self.buffer_start + 1) % self.len

        if (self.full == true) and (self.full_event ~= nil) then
            self.full_event(self)
        end

        local count = get_count(self)

        if count < self.trigger_len then
            self.ready = false

            if self.ready_event ~= nil then
                self.ready_event(self)
            end

            if count == 0 then
                self.empty = true

                if self.empty_event ~= nil then
                    self.empty_event(self)
                end
            end
        end

        return result
    end

    return 0
end

local function write(self, val)
    if self.full then
        self.overflow = true
    else
        self.buffer[self.buffer_end] = val
        self.buffer_end = (self.buffer_end + 1) % self.len

        if self.buffer_end == self.buffer_start then
            self.full = true
        end

        self.empty = false

        if get_count(self) >= self.trigger_len then
            self.ready = true
        end
    end
end

local function ewrite(self, val)
    if self.full then
        self.overflow = true
        if self.overflow_event then
            self.overflow_event(self)
        end
    else
        self.buffer[self.buffer_end] = val
        self.buffer_end = (self.buffer_end + 1) % self.len

        if self.buffer_end == self.buffer_start then
            self.full = true
            if self.full_event ~= nil then
                self.full_event(self)
            end
        end

        self.empty = false
        if self.empty_event ~= nil then
            self.empty_event(self)
        end

        if get_count(self) >= self.trigger_len then
            self.ready = true
            if self.ready_event ~= nil then
                self.ready_event(self)
            end
        end
    end
end

local function set_full_event(self, handler)
    self.full_event = handler
end

local function set_ready_event(self, handler)
    self.ready_event = handler
end

local function set_empty_event(self, handler)
    self.empty_event = handler
end

local function set_overflow_event(self, handler)
    self.overflow_event = handler
end

function fifo.new(lenght, full_event, ready_event, empty_event, overflow_event)
    local self = {
        len = lenght,
        trigger_len = lenght,
        empty = true,
        ready = false,
        full = false,
        overflow = false,
        buffer = {},
        buffer_start = 0,
        buffer_end = 0,
        full_event = full_event,
        ready_event = ready_event,
        empty_event = empty_event,
        overflow_event = overflow_event,
        reset = reset,
        ereset = ereset,
        read = read,
        eread = eread,
        write = write,
        ewrite = ewrite,
        set_full_event = set_full_event,
        set_ready_event = set_ready_event,
        set_empty_event = set_empty_event,
        set_overflow_event = set_overflow_event
    }

    for i = 0, lenght, 1 do
        self.buffer[i] = 0
    end

    return self
end

return fifo