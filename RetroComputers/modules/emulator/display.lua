local bit_converter = require("core:bit_converter")

local function reset(self)
    self.cursor_x = 0
    self.cursor_y = 0
    self.width = 80
    self.height = 25
    self.textmode = true

    for i = 0, #self.buffer - 1, 1 do
        self.buffer[i] = 0
    end

    for i = 0, #self.char_buffer - 1, 1 do
        self.char_buffer[i][1] = 0
        self.char_buffer[i][2] = 0
        self.char_buffer[i][3] = 0
    end
end

local function save(self, stream)
    stream:write_bytes(bit_converter.uint32_to_bytes(7, "LE"))
    stream:write_bytes(bit_converter.uint16_to_bytes(self.width, "BE"))
    stream:write_bytes(bit_converter.uint16_to_bytes(self.height, "BE"))
    stream:write(self.textmode and 1 or 0)
    stream:write(self.cursor_x)
    stream:write(self.cursor_y)
end

local function load(self, data)
    self.width = bit_converter.bytes_to_uint16({data[1], data[2]}, "BE")
    self.height = bit_converter.bytes_to_uint16({data[3], data[4]}, "BE")
    self.textmode = data[5] == 1
    self.cursor_x = data[6]
    self.cursor_y = data[7]
end

local display = {}

function display.new()
    local self = {
        cursor_x = 0,
        cursor_y = 0,
        width = 80,
        height = 25,
        textmode = true,
        cursor_visible = false,
        char_buffer = {},
        buffer = {},
        reset = reset,
        update = function() end,
        set_resolution = function (width, height, graphics) end,
        save = save,
        load = load
    }

    for i = 0, self.width * self.height - 1, 1 do
        self.char_buffer[i] = {0, 0, 0}
    end

    for i = 0, self.width * self.height - 1, 1 do
        self.buffer[i] = 0
    end

    return self
end

return display