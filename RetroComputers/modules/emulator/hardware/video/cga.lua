local logger = require("retro_computers:logger")
local cp437 = require("retro_computers:emulator/cp437")

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot
local palette = {
    [0] = 0x000000, -- Black
    0x0000AA, -- Blue
    0x00AA00, -- Green
    0x00AAAA, -- Cyan
    0xAA0000, -- Red
    0xAA00AA, -- Magenta
    0x000055, -- Brown
    0xAAAAAA, -- Light gray
    0x555555, -- Dark gray
    0x5555FF, -- Light blue
    0x55FF55, -- Light green
    0x55FFFF, -- Light cyan
    0xFF5555, -- Light red
    0xFF55FF, -- Light magenta
    0xFFFF55, -- Yellow
    0xFFFFFF  -- White
}

local function update_cursor_pos(self)
    self.display.cursor_x = math.floor(self.cursor % 80)
    self.display.cursor_y = math.floor(self.cursor / 80)
end

local function update_cursor_shape(self)
    if self.cursor_offset_y > 7 then
        self.cursor_enable = false
        self.display.cursor_visible = false
    else
        self.cursor_height = self.cursor_end - self.cursor_offset_y + 1
        self.cursor_enable = true
    end

    self.display:update_cursor()
end

-- Font
local font_8_8 = {}
for _, code in pairs(cp437) do
    font_8_8[code] = "fonts/cga_8_8/glyphs/" .. code
end
setmetatable(font_8_8, {
    __index = function (t, k)
        if rawget(t, k) then
            return rawget(t, k)
        else
            return "fonts/cga_8_8/glyphs/0"
        end
    end
})

-- VRAM
local function vram_read(self, addr)
	return self.vram[band(addr, 0x3FFF)]
end

local function vram_write(self, addr, val)
	self.vram[band(addr, 0x3FFF)] = val
end

-- Ports
local function port_3D4(self)
    return function(cpu, port, val)
        if val then
            self.crtc_index = band(val, 31)
        else
            return self.crtc_index
        end
    end
end

local function port_3D5(self)
    return function(cpu, port, val)
        if val then
            if self.crtc_index == 0x0E then
                self.cursor = bor(band(self.cursor, 0x00FF), lshift(val, 8))
                update_cursor_pos(self)
            elseif self.crtc_index == 0x0F then
                self.cursor = bor(band(self.cursor, 0xFF00), band(val, 0xFF))
                update_cursor_pos(self)
            elseif self.crtc_index == 0x0C then
                self.offset = band(bor(band(self.offset, 0x00FF), lshift(val, 8)), 0x3FFF)
            elseif self.crtc_index == 0x0D then
                self.offset = band(bor(band(self.offset, 0xFF00), band(val, 0xFF)), 0x3FFF)
            elseif self.crtc_index == 0x0A then
                self.cursor_offset_y = band(val, 0xF)
                update_cursor_shape(self)
            elseif self.crtc_index == 0x0B then
                self.cursor_end = band(val, 0xF)
                update_cursor_shape(self)
            end
        else
            if self.crtc_index == 0x0E then
                return rshift(self.cursor, 8)
            elseif self.crtc_index == 0x0F then
                return band(self.cursor, 0xFF)
            else
                return 0x00
            end
        end
    end
end

local function port_3D8(self)
    return function(cpu, port, val)
        if val then
            self.mode_hires_text = band(val, 0x01) ~= 0
            self.mode_graphics = band(val, 0x02) ~= 0
            self.mode_enable = band(val, 0x08) ~= 0
            self.mode_hires_graphics = band(val, 0x10) ~= 0

            if self.mode_graphics then
                if self.mode_hires_graphics then
                    self.display:set_resolution(640, 200, true)
                else
                    self.display:set_resolution(320, 200, true)
                end
            else
                if self.mode_hires_text then
                    self.display:set_resolution(80, 25, false)
                else
                    self.display:set_resolution(40, 25, false)
                end
            end
        else
            return 0xFF
        end
    end
end

local function port_3D9(self)
    return function(cpu, port, val)
        if val then
            self.palette = val
        else
            return 0xFF
        end
    end
end

local function port_3DA(self)
    return function(cpu, port, val)
        if not val then
            self.status = bxor(self.status, 0x09)
            return self.status
        end
    end
end

local function port_3DB(self)
    return function(cpu, port, val)
        if not val then
            return 0xFF
        end
    end
end

local function port_3DC(self)
    return function(cpu, port, val)
        if not val then
            return 0xFF
        end
    end
end

-- Render
local function render_text(self, width)
    for i = 0, 25 * width - 1, 1 do
        local offset = lshift(self.offset + i, 1)
        local chr = cp437[self.vram[offset]]
        local atr = self.vram[offset + 1]
        local bg = rshift(band(atr, 0xF0), 4)
        local fg = band(atr, 0x0F)
        local char = self.display.char_buffer[i]

        char[1] = chr
        char[2] = palette[bg]
        char[3] = palette[fg]
    end

    if self.cursor_enable then
        self.display.cursor_visible = not self.display.cursor_visible
    end
end

local function render_mono(self)
	for y = 0, 199, 1 do
        local offset_y = (rshift(y, 1) * 80) + (band(y, 1) * 8192)

		for x = 0, 639, 1 do
            local pixel = self.vram[offset_y + rshift(x, 3)]
            self.display.buffer[y * 640 + x] = palette[band(rshift(pixel, (7 - band(x, 7))), 1) * 15]
		end
	end
end

local function render_color(self)
    for y = 0, 199, 1 do
        local offset_y = rshift(y, 1) * 80 + (band(y, 1) * 8192)

        for x = 0, 319, 1 do
            local offset = self.vram[offset_y + rshift(x, 2)]
            local pixel = band(rshift(offset, lshift(3 - band(x, 0x03), 1)), 0x03)

            self.display.buffer[y * 320 + x] = palette[pixel]
        end
    end
end

local function update(self)
    if self.mode_graphics then
        if self.mode_hires_graphics then
            render_mono(self)
        else
            render_color(self)
        end
    else
        render_text(self, 80)
    end

    self.display.update()
end

local function reset(self)
    self.crtc_index = 0
    self.cursor = 0
    self.status = 0x08
    self.palette = 0
    self.offset = 0
    self.cursor_height = 0
    self.cursor_offset_y = 0
    self.cursor_end = 0
    self.cursor_enable = false
    self.mode_hires_text = false
    self.mode_graphics = false
    self.mode_hires_graphics = false
    self.mode_enable = false
end

local function save_state(self, stream)
    stream:write_uint32(6)
    stream:write_uint16(self.cursor)
    stream:write(self.status)
    stream:write(self.palette)
    stream:write(self.crtc_index)
end

local function load_state(self, data)
    self.cursor = bor(data[1], lshift(data[2], 8))
    self.status = data[3]
    self.palette = data[4]
    self.crtc_index = data[5]

    update_cursor_pos(self)
end

local function get_type(self)
    return 1
end

local videocard = {}

function videocard.new(cpu, display)
    local self = {
        display = display,
        status = 0x08,
        palette = 0,
        crtc_index = 0,
        cursor = 0,
        offset = 0,
        font = font_8_8,
        glyph_width = 8,
        glyph_height = 8,
        cursor_color = {255, 255, 255, 255},
        cursor_height = 0,
        cursor_offset_y = 0,
        cursor_end = 0,
        cursor_enable = false,
        mode_enable = false,
        mode_graphics = false,
        mode_hires_graphics = false,
        mode_hires_text = false,
        vram = {},
        vram_start = 0xB8000,
        vram_end = 0xBFFFF,
        vram_read = vram_read,
        vram_write = vram_write,
        get_type = get_type,
        update = update,
        reset = reset,
        save_state = save_state,
        load_state = load_state
    }

    cpu:set_port(0x3D4, port_3D4(self))
    cpu:set_port(0x3D5, port_3D5(self))
    cpu:set_port(0x3D8, port_3D8(self))
    cpu:set_port(0x3D9, port_3D9(self))
    cpu:set_port(0x3DA, port_3DA(self))
    cpu:set_port(0x3DB, port_3DB(self))
    cpu:set_port(0x3DC, port_3DC(self))

    -- Initialize VRAM
    for i = 0, 0x3FFF, 1 do
        self.vram[i] = 0x00
    end

    return self
end

return videocard