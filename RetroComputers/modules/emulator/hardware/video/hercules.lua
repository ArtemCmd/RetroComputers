local logger = require("retro_computers:logger")
local cp437 = require("retro_computers:emulator/cp437")

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local read_regs = {
    [0x0E] = true,
    [0x0F] = true,
    [0x10] = true,
    [0x11] = true
}

-- Font
local font_9_14 = {}
for _, val in pairs(cp437) do
    font_9_14[val] = "fonts/mda_9_14/glyphs/" .. val
end
setmetatable(font_9_14, {
    __index = function (t, k)
        if rawget(t, k) then
            return rawget(t, k)
        else
            return "fonts/mda_9_14/glyphs/0"
        end
    end
})

-- Colors
local graphics_palette = {
    [0] = 0x000000,
    [1] = 0xFFFFFF,
}

local attrs = {
    [0x00] = 0x000000,
    [0x01] = 0xAAAAAA,
    [0x02] = 0xAAAAAA,
    [0x03] = 0xAAAAAA,
    [0x04] = 0xAAAAAA,
    [0x05] = 0xAAAAAA,
    [0x06] = 0xAAAAAA,
    [0x07] = 0xAAAAAA,
    [0x08] = 0x000000,
    [0x09] = 0xFFFFFF,
    [0x0A] = 0xFFFFFF,
    [0x0B] = 0xFFFFFF,
    [0x0C] = 0xFFFFFF,
    [0x0D] = 0xFFFFFF,
    [0x0E] = 0xFFFFFF,
    [0x0F] = 0xFFFFFF,
    [0x10] = 0xAAAAAA,
    [0x11] = 0xAAAAAA,
    [0x12] = 0xAAAAAA,
    [0x13] = 0xAAAAAA,
    [0x14] = 0xAAAAAA,
    [0x15] = 0xAAAAAA,
    [0x16] = 0xAAAAAA,
    [0x17] = 0xAAAAAA,
    [0x18] = 0xFFFFFF,
    [0x19] = 0xFFFFFF,
    [0x1A] = 0xFFFFFF,
    [0x1B] = 0xFFFFFF,
    [0x1C] = 0xFFFFFF,
    [0x1D] = 0xFFFFFF,
    [0x1E] = 0xFFFFFF,
    [0x1F] = 0xFFFFFF,
    [0x20] = 0xAAAAAA,
    [0x21] = 0xAAAAAA,
    [0x22] = 0xAAAAAA,
    [0x23] = 0xAAAAAA,
    [0x24] = 0xAAAAAA,
    [0x25] = 0xAAAAAA,
    [0x26] = 0xAAAAAA,
    [0x27] = 0xAAAAAA,
    [0x28] = 0xFFFFFF,
    [0x29] = 0xFFFFFF,
    [0x2A] = 0xFFFFFF,
    [0x2B] = 0xFFFFFF,
    [0x2C] = 0xFFFFFF,
    [0x2D] = 0xFFFFFF,
    [0x2E] = 0xFFFFFF,
    [0x2F] = 0xFFFFFF,
    [0x30] = 0xAAAAAA,
    [0x31] = 0xAAAAAA,
    [0x32] = 0xAAAAAA,
    [0x33] = 0xAAAAAA,
    [0x34] = 0xAAAAAA,
    [0x35] = 0xAAAAAA,
    [0x36] = 0xAAAAAA,
    [0x37] = 0xAAAAAA,
    [0x38] = 0xFFFFFF,
    [0x39] = 0xFFFFFF,
    [0x3A] = 0xFFFFFF,
    [0x3B] = 0xFFFFFF,
    [0x3C] = 0xFFFFFF,
    [0x3D] = 0xFFFFFF,
    [0x3E] = 0xFFFFFF,
    [0x3F] = 0xFFFFFF,
    [0x40] = 0xAAAAAA,
    [0x41] = 0xAAAAAA,
    [0x42] = 0xAAAAAA,
    [0x43] = 0xAAAAAA,
    [0x44] = 0xAAAAAA,
    [0x45] = 0xAAAAAA,
    [0x46] = 0xAAAAAA,
    [0x47] = 0xAAAAAA,
    [0x48] = 0xFFFFFF,
    [0x49] = 0xFFFFFF,
    [0x4A] = 0xFFFFFF,
    [0x4B] = 0xFFFFFF,
    [0x4C] = 0xFFFFFF,
    [0x4D] = 0xFFFFFF,
    [0x4E] = 0xFFFFFF,
    [0x4F] = 0xFFFFFF,
    [0x50] = 0xAAAAAA,
    [0x51] = 0xAAAAAA,
    [0x52] = 0xAAAAAA,
    [0x53] = 0xAAAAAA,
    [0x54] = 0xAAAAAA,
    [0x55] = 0xAAAAAA,
    [0x56] = 0xAAAAAA,
    [0x57] = 0xAAAAAA,
    [0x58] = 0xFFFFFF,
    [0x59] = 0xFFFFFF,
    [0x5A] = 0xFFFFFF,
    [0x5B] = 0xFFFFFF,
    [0x5C] = 0xFFFFFF,
    [0x5D] = 0xFFFFFF,
    [0x5E] = 0xFFFFFF,
    [0x5F] = 0xFFFFFF,
    [0x60] = 0xAAAAAA,
    [0x61] = 0xAAAAAA,
    [0x62] = 0xAAAAAA,
    [0x63] = 0xAAAAAA,
    [0x64] = 0xAAAAAA,
    [0x65] = 0xAAAAAA,
    [0x66] = 0xAAAAAA,
    [0x67] = 0xAAAAAA,
    [0x68] = 0xFFFFFF,
    [0x69] = 0xFFFFFF,
    [0x6A] = 0xFFFFFF,
    [0x6B] = 0xFFFFFF,
    [0x6C] = 0xFFFFFF,
    [0x6D] = 0xFFFFFF,
    [0x6E] = 0xFFFFFF,
    [0x6F] = 0xFFFFFF,
    [0x70] = 0xAAAAAA,
    [0x71] = 0xAAAAAA,
    [0x72] = 0xAAAAAA,
    [0x73] = 0xAAAAAA,
    [0x74] = 0xAAAAAA,
    [0x75] = 0xAAAAAA,
    [0x76] = 0xAAAAAA,
    [0x77] = 0xAAAAAA,
    [0x78] = 0xFFFFFF,
    [0x79] = 0xFFFFFF,
    [0x7A] = 0xFFFFFF,
    [0x7B] = 0xFFFFFF,
    [0x7C] = 0xFFFFFF,
    [0x7D] = 0xFFFFFF,
    [0x7E] = 0xFFFFFF,
    [0x7F] = 0xFFFFFF,
    [0x80] = 0x000000,
    [0x81] = 0xAAAAAA,
    [0x82] = 0xAAAAAA,
    [0x83] = 0xAAAAAA,
    [0x84] = 0xAAAAAA,
    [0x85] = 0xAAAAAA,
    [0x86] = 0xAAAAAA,
    [0x87] = 0xAAAAAA,
    [0x88] = 0x000000,
    [0x89] = 0xFFFFFF,
    [0x8A] = 0xFFFFFF,
    [0x8B] = 0xFFFFFF,
    [0x8C] = 0xFFFFFF,
    [0x8D] = 0xFFFFFF,
    [0x8E] = 0xFFFFFF,
    [0x8F] = 0xFFFFFF,
    [0x90] = 0xAAAAAA,
    [0x91] = 0xAAAAAA,
    [0x92] = 0xAAAAAA,
    [0x93] = 0xAAAAAA,
    [0x94] = 0xAAAAAA,
    [0x95] = 0xAAAAAA,
    [0x96] = 0xAAAAAA,
    [0x97] = 0xAAAAAA,
    [0x98] = 0xFFFFFF,
    [0x99] = 0xFFFFFF,
    [0x9A] = 0xFFFFFF,
    [0x9B] = 0xFFFFFF,
    [0x9C] = 0xFFFFFF,
    [0x9D] = 0xFFFFFF,
    [0x9E] = 0xFFFFFF,
    [0x9F] = 0xFFFFFF,
    [0xA0] = 0xAAAAAA,
    [0xA1] = 0xAAAAAA,
    [0xA2] = 0xAAAAAA,
    [0xA3] = 0xAAAAAA,
    [0xA4] = 0xAAAAAA,
    [0xA5] = 0xAAAAAA,
    [0xA6] = 0xAAAAAA,
    [0xA7] = 0xAAAAAA,
    [0xA8] = 0xFFFFFF,
    [0xA9] = 0xFFFFFF,
    [0xAA] = 0xFFFFFF,
    [0xAB] = 0xFFFFFF,
    [0xAC] = 0xFFFFFF,
    [0xAD] = 0xFFFFFF,
    [0xAE] = 0xFFFFFF,
    [0xAF] = 0xFFFFFF,
    [0xB0] = 0xAAAAAA,
    [0xB1] = 0xAAAAAA,
    [0xB2] = 0xAAAAAA,
    [0xB3] = 0xAAAAAA,
    [0xB4] = 0xAAAAAA,
    [0xB5] = 0xAAAAAA,
    [0xB6] = 0xAAAAAA,
    [0xB7] = 0xAAAAAA,
    [0xB8] = 0xFFFFFF,
    [0xB9] = 0xFFFFFF,
    [0xBA] = 0xFFFFFF,
    [0xBB] = 0xFFFFFF,
    [0xBC] = 0xFFFFFF,
    [0xBD] = 0xFFFFFF,
    [0xBE] = 0xFFFFFF,
    [0xBF] = 0xFFFFFF,
    [0xC0] = 0xAAAAAA,
    [0xC1] = 0xAAAAAA,
    [0xC2] = 0xAAAAAA,
    [0xC3] = 0xAAAAAA,
    [0xC4] = 0xAAAAAA,
    [0xC5] = 0xAAAAAA,
    [0xC6] = 0xAAAAAA,
    [0xC7] = 0xAAAAAA,
    [0xC8] = 0xFFFFFF,
    [0xC9] = 0xFFFFFF,
    [0xCA] = 0xFFFFFF,
    [0xCB] = 0xFFFFFF,
    [0xCC] = 0xFFFFFF,
    [0xCD] = 0xFFFFFF,
    [0xCE] = 0xFFFFFF,
    [0xCF] = 0xFFFFFF,
    [0xD0] = 0xAAAAAA,
    [0xD1] = 0xAAAAAA,
    [0xD2] = 0xAAAAAA,
    [0xD3] = 0xAAAAAA,
    [0xD4] = 0xAAAAAA,
    [0xD5] = 0xAAAAAA,
    [0xD6] = 0xAAAAAA,
    [0xD7] = 0xAAAAAA,
    [0xD8] = 0xFFFFFF,
    [0xD9] = 0xFFFFFF,
    [0xDA] = 0xFFFFFF,
    [0xDB] = 0xFFFFFF,
    [0xDC] = 0xFFFFFF,
    [0xDD] = 0xFFFFFF,
    [0xDE] = 0xFFFFFF,
    [0xDF] = 0xFFFFFF,
    [0xE0] = 0xAAAAAA,
    [0xE1] = 0xAAAAAA,
    [0xE2] = 0xAAAAAA,
    [0xE3] = 0xAAAAAA,
    [0xE4] = 0xAAAAAA,
    [0xE5] = 0xAAAAAA,
    [0xE6] = 0xAAAAAA,
    [0xE7] = 0xAAAAAA,
    [0xE8] = 0xFFFFFF,
    [0xE9] = 0xFFFFFF,
    [0xEA] = 0xFFFFFF,
    [0xEB] = 0xFFFFFF,
    [0xEC] = 0xFFFFFF,
    [0xED] = 0xFFFFFF,
    [0xEE] = 0xFFFFFF,
    [0xEF] = 0xFFFFFF,
    [0xF0] = 0xAAAAAA,
    [0xF1] = 0xAAAAAA,
    [0xF2] = 0xAAAAAA,
    [0xF3] = 0xAAAAAA,
    [0xF4] = 0xAAAAAA,
    [0xF5] = 0xAAAAAA,
    [0xF6] = 0xAAAAAA,
    [0xF7] = 0xAAAAAA,
    [0xF8] = 0xFFFFFF,
    [0xF9] = 0xFFFFFF,
    [0xFA] = 0xFFFFFF,
    [0xFB] = 0xFFFFFF,
    [0xFC] = 0xFFFFFF,
    [0xFD] = 0xFFFFFF,
    [0xFE] = 0xFFFFFF,
    [0xFF] = 0xFFFFFF
}

-- Cursor
local function update_cursor_pos(self)
    local position = bor(self.crtc_regs[0x0F], lshift(self.crtc_regs[0x0E], 8))

    self.display.cursor_x = math.floor(position % 80)
    self.display.cursor_y = math.floor(position / 80)
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

-- VRAM
local function vram_read(self, addr)
    return self.vram[band(addr, self.vram_mask)]
end

local function vram_write(self, addr, val)
    self.vram[band(addr, self.vram_mask)] = val
end

-- Ports
local function port_3B0_3B2_3B4_3B6(self)
    return function(cpu, port, val)
        if val then
            self.crtc_index = band(val, 0x1F)
        else
            return self.crtc_index
        end
    end
end

local function port_3B1_3B3_3B5_3B7(self)
    return function(cpu, port, val)
        if val then
            self.crtc_regs[self.crtc_index] = band(val, 0xFF)

            if (self.crtc_index == 0x0E) or (self.crtc_index == 0x0F) then
                update_cursor_pos(self)
            elseif self.crtc_index == 0x0A then
                self.cursor_offset_y = band(val, 0xF)
                update_cursor_shape(self)
            elseif self.crtc_index == 0x0B then
                self.cursor_end = band(val, 0xF)
                update_cursor_shape(self)
            end
        else
            if read_regs[self.crtc_index] then
                return self.crtc_regs[self.crtc_index]
            else
                return 0xFF
            end
        end
    end
end

local function port_3B8(self) -- Mode control register
    return function(cpu, port, val)
        if val then
            self.graphics_mode = band(val, 0x02) ~= 0

            if band(val, 0x02) == 0x02 then
                self.display:set_resolution(720, 348, true)
            else
                self.display:set_resolution(80, 25, false)
            end
        else
            return 0xFF
        end
    end
end

local function port_3B9(self)
    return function(cpu, port, val)
        if not val then
            return 0xFF
        end
    end
end

local function port_3BA(self)
    return function (cpu, port, val)
        self.status = bxor(self.status, 0x09)
        return self.status
    end
end

local function port_3BB(self)
    return function(cpu, port, val)
        if not val then
            return 0xFF
        end
    end
end

local function port_3BF(self) -- Graphics mode enable
    return function(cpu, port, val)
        if val then
            if band(val, 0x01) ~= 0 then
                self.vram_mask = 0xFFFF
            else
                self.vram_mask = 0x0FFF
            end

            if band(val, 0x02) ~= 0 then
                self.vram_offset = 0x10000
            else
                self.vram_offset = 0x08000
            end
        else
            return 0xFF
        end
    end
end

-- Render
local function update(self)
    if self.graphics_mode then
        for y = 0, 347, 1 do

            for x = 0, 719, 1 do
                local pixel = self.vram[self.vram_offset + lshift(band(y, 3), 13) + rshift(y, 2) * 90 + rshift(x, 3)]
                self.display.buffer[y * 720 + x] = graphics_palette[band(rshift(pixel, (7 - band(x, 0x07))), 0x01)]
            end
        end
    else
        for y = 0, 24, 1 do
            local offset_y = (y * 160)

            for x = 0, 79, 1 do
                local offset = offset_y + lshift(x, 1)
                local chr = self.vram[offset]
                local attr = self.vram[offset + 1]
                local cell = self.display.char_buffer[y * 80 + x]

                cell[1] = cp437[chr]
                cell[2] = 0x00
                cell[3] = attrs[attr]
            end
        end

        if self.cursor_enable then
            self.display.cursor_visible = not self.display.cursor_visible
        end
    end

    self.display.update()
end

local function reset(self)
    for i = 0, 16, 1 do
        self.crtc_regs[i] = 0
    end

    self.crtc_index = 0
    self.status = 0x00
    self.vram_mask = 0x0FFF
    self.vram_offset = 0
    self.cursor_height = 0
    self.cursor_offset_y = 0
    self.cursor_end = 0
    self.cursor_enable = false
    self.graphics_mode = false
end

local function get_type(self)
    return 2
end

local hercules = {}

function hercules.new(cpu, display)
    local self = {
        crtc_regs = {[0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        crtc_index = 0,
        vram_offset = 0,
        vram_mask = 0x0FFF,
        status = 0x00,
        graphics_mode = false,
        display = display,
        glyph_width = 9,
        glyph_height = 14,
        font = font_9_14,
        cursor = 0,
        cursor_color = {255, 255, 255, 255},
        cursor_height = 0,
        cursor_offset_y = 0,
        cursor_end = 0,
        cursor_enable = false,
        vram_start = 0xB0000,
        vram_end = 0xBFFFF,
        vram = {},
        vram_read = vram_read,
        vram_write = vram_write,
        get_type = get_type,
        update = update,
        reset = reset,
    }

    cpu:set_port(0x3B0, port_3B0_3B2_3B4_3B6(self))
    cpu:set_port(0x3B2, port_3B0_3B2_3B4_3B6(self))
    cpu:set_port(0x3B4, port_3B0_3B2_3B4_3B6(self))
    cpu:set_port(0x3B6, port_3B0_3B2_3B4_3B6(self))
    cpu:set_port(0x3B1, port_3B1_3B3_3B5_3B7(self))
    cpu:set_port(0x3B3, port_3B1_3B3_3B5_3B7(self))
    cpu:set_port(0x3B5, port_3B1_3B3_3B5_3B7(self))
    cpu:set_port(0x3B7, port_3B1_3B3_3B5_3B7(self))
    cpu:set_port(0x3B8, port_3B8(self))
    cpu:set_port(0x3B9, port_3B9(self))
    cpu:set_port(0x3BA, port_3BA(self))
    cpu:set_port(0x3BB, port_3BB(self))
    cpu:set_port(0x3BF, port_3BF(self))

    return self
end

return hercules