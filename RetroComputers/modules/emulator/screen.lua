local event = require("retro_computers:emulator/events")
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local screen = {
    EVENTS = {
        SET_RESOLUTION = 1,
        SET_SCALE = 2
    }
}

local function get_pixel_rgb_i(self, index)
    local offset = lshift(index, 2) + 1

    return bor(lshift(self.buffer[offset], 16), bor(lshift(self.buffer[offset + 1], 8), self.buffer[offset + 2]))
end

local function set_pixel_rgb_i(self, index, color)
    local offset = lshift(index, 2) + 1

    self.buffer[offset] = band(rshift(color, 16), 0xFF)
    self.buffer[offset + 1] = band(rshift(color, 8), 0xFF)
    self.buffer[offset + 2] = band(color, 0xFF)
    self.buffer[offset + 3] = 0xFF
end

local function set_resolution(self, width, height)
    if (self.width ~= width) or (self.height ~= height) then
        for i = self.width * self.height * 4, width * height * 4, 1 do
            self.buffer[i] = 0x000000
        end
    end

    self.width = width
    self.height = height
    self.events:emit(screen.EVENTS.SET_RESOLUTION, width, height, self.scale_x, self.scale_y)
end

local function set_scale(self, x, y)
    self.scale_x = x
    self.scale_y = y
    self.events:emit(screen.EVENTS.SET_SCALE, x, y)
end

local function update(self)
end

local function reset(self)
    for i = 0, self.width * self.height * 4, 1 do
        self.buffer[i] = 0x000000
    end
end

function screen.new()
    local self = {
        events = event.new(),
        buffer = {},
        width = 640,
        height = 200,
        scale_x = 1.0,
        scale_y = 1.0,
        reset = reset,
        update = update,
        set_resolution = set_resolution,
        set_scale = set_scale,
        get_pixel_rgb_i = get_pixel_rgb_i,
        set_pixel_rgb_i = set_pixel_rgb_i
    }

    for i = 0, self.width * self.height * 4, 1 do
        self.buffer[i] = 0x000000
    end

    return self
end

return screen
