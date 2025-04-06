local event = require("retro_computers:emulator/events")
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local display = {
    EVENTS = {
        SET_RESOLUTION = 0
    }
}

local function get_pixel(self, index)
    local offset = lshift(index, 2) + 1

    return {self.buffer[offset], self.buffer[offset + 1], self.buffer[offset + 2], self.buffer[offset + 3]}
end

local function set_pixel(self, index, color)
    local offset = lshift(index, 2) + 1

    self.buffer[offset] = color[1]
    self.buffer[offset + 1] = color[2]
    self.buffer[offset + 2] = color[3]
    self.buffer[offset + 3] = color[4]
end

local function set_resolution(self, width, height)
    self.width = width
    self.height = height

    self.events:emit(display.EVENTS.SET_RESOLUTION, width, height)
end

local function reset(self)
    self.width = 640
    self.height = 200

    for i = 0, self.width * self.height * 4, 1 do
        self.buffer[i] = 0
    end
end

local function save_state(self, stream)
    stream:write_uint32(2)
    stream:write_uint16(self.width)
    stream:write_uint16(self.height)
end

local function load_state(self, data)
    self.width = bor(lshift(data[1], 8), data[2])
    self.height = bor(lshift(data[3], 8), data[4])
end

function display.new()
    local self = {
        events = event.new(),
        buffer = {},
        width = 640,
        height = 200,
        reset = reset,
        update = function() end,
        set_resolution = set_resolution,
        get_pixel = get_pixel,
        set_pixel = set_pixel,
        save_state = save_state,
        load_state = load_state
    }

    reset(self)

    return self
end

return display