-- CGA

local logger = require("retro_computers:logger")
local cp437 = require("retro_computers:emulator/cp437")
local bit_converter = require("core:bit_converter")

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local palette = {
    [0] = 0, -- black
    170, -- blue
    43520, -- green
    43690, -- cyan
    11141120, -- red
    11141290, -- magenta
    85, -- brown
    11184810, -- light gray
    5592405, -- dark gray
    5592575, -- light blue
    5635925, -- light green
    5636095, -- light cyan
    16733525, -- light red
    16733695, -- light magenta
    16777045, -- yellow
    16777215 -- white
}
setmetatable(palette, {
    __index = function (t, k)
        if (k >= 0) and (k <= 15) then
            return rawget(t, k)
        end

        -- logger:debug("CGA: unnown palette index: %d", k)

        return 16777215
    end
})

local function update_cursor_pos(self)
    local position = bor(band(self.cursor, 0x00FF), lshift(band(rshift(self.cursor, 8), 0xFF), 8))
    self.display.cursor_x = math.floor(position % 80)
    self.display.cursor_y = math.floor(position / 80)
end

-- Font
local font_8_8 = {}
for _, code in pairs(cp437) do
    font_8_8[code] = "fonts/ibm_pc_8_8/glyphs/" .. code
end
setmetatable(font_8_8, {
    __index = function (t, k)
        if rawget(t, k) then
            return rawget(t, k)
        else
            return "fonts/ibm_pc_8_8/glyphs/0"
        end
    end
})

-- VRAM
local function vram_read(self, addr)
    -- logger:debug("CGA: Read from vram")
	return self.vram[addr - 0xB8000] or 0
end

local function vram_write(self, addr, val)
    -- logger:debug("CGA: Write %d to vram", val)
    local index = addr - 0xB8000
	if self.vram[index] == val then
        return
    end
	self.vram[index] = val
end

-- Ports
local function port_3D4(self) -- CRT Controller Register's
    return function(_, _, val)
        if val then
            self.crtc_index = band(val, 31)
            -- logger:debug("CGA: Select CRTC register %d", self.crtc_index)
        else
            return self.crtc_index
        end
    end
end

local function port_3D5(self)
    return function(_, _, val)
        if val then
            if self.crtc_index == 0x0E then
                self.cursor = bor(band(self.cursor, 0x00FF), lshift(val, 8))
            elseif self.crtc_index == 0x0F then
                self.cursor = bor(band(self.cursor, 0xFF00), band(val, 0xFF))
            end

            update_cursor_pos(self)
            -- logger:debug("CGA: Write %d to CRTC register %02X", val, self.crtc_index)
        else
            if self.crtc_index == 0x0E then
                return rshift(self.cursor, 8)
            elseif self.crtc_index == 0x0F then
                return band(self.cursor, 0xFF)
            else
                return 0
            end
        end
    end
end

local function port_3D8(self)
    return function(_, _, val)
        if val then
            -- logger:debug("CGA: Write %02X to port 0x3D8", val)
            self.mode = val
            if band(self.mode, 2) == 2 then
                self.display.textmode = false
                if band(self.mode, 4) == 4 then
                    self.display.width = 640
                else
                    self.display.width = 320
                end
                self.display.height = 200
            else
                self.display.textmode = true
                if band(self.mode, 1) == 1 then
                    self.display.width = 80
                else
                    self.display.width = 40
                end
                self.display.height = 25
            end
            self.display.set_resolution(self.display.width, self.display.height, not self.display.textmode)
            logger:debug("CGA: Mode Select Register: 80x25 = %s, Graphics mode = %s, Composite mode = %s, Video enable = %s, 640x200 enable = %s, Attribute controls background = %s", band(val, 0x01) == 0x01, band(val, 0x02) == 0x02, band(val, 0x04) == 0x04, band(val, 0x08) == 0x08, band(val, 0x10) == 0x10, band(val, 0x20) == 0x20)
        else
            return self.mode
        end
    end
end

local function port_3D9(self)
    return function(_, _, val)
        if val then
            self.palette = band(val, 0x3F)
        else
            return 0xFF
        end
    end
end

local function port_3DA(self)
    return function(_, _, val)
        if not val then
            self.status = bxor(self.status, 0x09)
            return self.status
        end
    end
end

local function port_3DB(self)
    return function()
    end
end

local function port_3DC(self)
    return function()
    end
end

-- Render
local function render_text(self, width)
	for y = 0, 24, 1 do
		local offset_y = y * 160
		for x = 0, width - 1, 1 do
            local offset_x = x * 2
			local chr = cp437[self.vram[offset_y + offset_x]]
			local atr = self.vram[offset_y + offset_x + 1]
            local bg = rshift(band(atr, 0xFF00), 8)
			local fg = band(atr, 0x00FF)
            self.display.char_buffer[y * 80 + x][1] = chr
            self.display.char_buffer[y * 80 + x][2] = palette[bg]
            self.display.char_buffer[y * 80 + x][3] = palette[fg]
		end
	end

    self.display.cursor_visible = not self.display.cursor_visible
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
            local pixel = band(rshift(offset, 2 * (3 - band(x, 3))), 3)

            self.display.buffer[y * 320 + x] = palette[pixel]
        end
    end
end

local function update(self)
    if band(self.mode, 2) == 2 then
        if band(self.mode, 4) == 4 then
            render_mono(self)
        else
            render_color(self)
        end
    else
        if band(self.mode, 1) == 1 then
            render_text(self, 80)
        else
            render_text(self, 40)
        end
    end

    self.display.update()
end

local videocard = {}

local function reset(self)
    self.mode = 0
    self.crtc_index = 0
    self.cursor = 0
    self.status = 0x09
    self.palette = 0x30
end

local function save(self, stream)
    stream:write_bytes(bit_converter.uint32_to_bytes(6))
    stream:write(self.mode)
    stream:write_bytes(bit_converter.uint16_to_bytes(self.cursor))
    stream:write(self.status)
    stream:write(self.palette)
    stream:write(self.crtc_index)
end

local function load(self, data)
    self.mode = data[1]
    self.cursor = bit_converter.bytes_to_uint16({data[2], data[3]})
    self.status = data[4]
    self.palette = data[5]
    self.crtc_index = data[6]

    update_cursor_pos(self)

    logger:debug("CGA: Load: Mode = %d, Cursor = %d, Status = %d, Palette = %d, CRTC Index = %d", self.mode, self.cursor, self.status, self.palette, self.crtc_index)
end

function videocard.new(cpu, display)
    local self = {
        vram = {},
        status = 0x09,
        mode = 0,
        palette = 0x30,
        crtc_index = 0,
        cursor = 0,
        start_addr = 0xB8000,
        end_addr = 0xBFFFF,
        display = display,
        font = font_8_8,
        glyph_width = 8,
        glyph_height = 8,
        cursor_color = {255, 255, 255, 255},
        vram_read = vram_read,
        vram_write = vram_write,
        update = update,
        reset = reset,
        save = save,
        load = load
    }

    cpu:port_set(0x3D4, port_3D4(self))
    cpu:port_set(0x3D5, port_3D5(self))
    cpu:port_set(0x3D8, port_3D8(self))
    cpu:port_set(0x3D9, port_3D9(self))
    cpu:port_set(0x3DA, port_3DA(self))
    cpu:port_set(0x3DB, port_3DB(self))
    cpu:port_set(0x3DC, port_3DC(self))

    return self
end

return videocard