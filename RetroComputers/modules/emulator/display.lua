local event = require("retro_computers:emulator/events")
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local display = {
    EVENTS = {
        SET_RESOLUTION = 0
    }
}

local function set_resolution(self, width, height, graphics_mode)
    self.width = width
    self.height = height
    self.text_mode = not graphics_mode

    self.events:emit(display.EVENTS.SET_RESOLUTION, width, height, graphics_mode)
end

local function reset(self)
    self.cursor_x = 0
    self.cursor_y = 0
    self.width = 80
    self.height = 25
    self.text_mode = true
    self.cursor_visible = false

    for i = 0, 640 * 320, 1 do
        self.buffer[i] = 0
    end

    for i = 0, #self.char_buffer, 1 do
        self.char_buffer[i][1] = 0
        self.char_buffer[i][2] = 0
        self.char_buffer[i][3] = 0
    end
end

local function save_state(self, stream)
    stream:write_uint32(7)
    stream:write_uint16(self.width)
    stream:write_uint16(self.height)
    stream:write(self.text_mode and 1 or 0)
    stream:write(self.cursor_x)
    stream:write(self.cursor_y)
end

local function load_state(self, data)
    self.width = bor(lshift(data[1], 8), data[2])
    self.height = bor(lshift(data[3], 8), data[4])
    self.text_mode = data[5] == 1
    self.cursor_x = data[6]
    self.cursor_y = data[7]
end

function display.new()
    local self = {
        cursor_x = 0,
        cursor_y = 0,
        width = 80,
        height = 25,
        text_mode = true,
        cursor_visible = false,
        char_buffer = {},
        buffer = {},
        events = event.new(),
        reset = reset,
        update = function() end,
        set_resolution = set_resolution,
        update_cursor = function() end,
        save_state = save_state,
        load_state = load_state
    }

    for i = 0, self.width * self.height - 1, 1 do
        self.char_buffer[i] = {0, 0, 0}
    end

    return self
end

return display