-- =====================================================================================================================================================================
-- IBM Monochrome Display Adapter (MDA) emulation.
-- =====================================================================================================================================================================

local common = require("retro_computers:emulator/hardware/video/common")
local filesystem = require("retro_computers:emulator/filesystem")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local mda = {}

local font_9_14 = filesystem.open("retro_computers:modules/emulator/roms/video/mda.bin", "r", true):read_bytes()
local palette = {
    [0] = {0x000000, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0x000000, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0x000000, 0xAAAAAA},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0x000000, 0xAAAAAA},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0x000000, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0x000000, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0x000000, 0xAAAAAA},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0xAAAAAA, 0x000000},
    {0x000000, 0xAAAAAA},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000},
    {0xFFFFFF, 0x000000}
}

local crtc_regs_write = {
    [0x00] = function(self, val) -- Horizontal Total Register
    end,
    [0x01] = function(self, val) -- Horizontal Displayed Register
    end,
    [0x02] = function(self, val) -- Horizontal Sync Position Register
    end,
    [0x03] = function(self, val) -- Horizontal Sync Pulse Width Register
    end,
    [0x04] = function(self, val) -- Vertical Total Register
        self.crtc_vertical_total = band(val, 0x7F)
    end,
    [0x05] = function(self, val) -- Vertical Total Adjust Register
    end,
    [0x06] = function(self, val) -- Vertical Displayed Register
        self.crtc_vertical_displayed = band(val, 0x7F)
    end,
    [0x07] = function(self, val) -- Vertical Sync Register
        self.crtc_vsync = band(val, 0x7F)
    end,
    [0x08] = function(self, val) -- Interlase Mode Register
    end,
    [0x09] = function(self, val) -- Max Scan Line Register
        self.crtc_max_scanline = band(val, 0x1F)
    end,
    [0x0A] = function(self, val) -- Cursor Start Register
        self.crtc_cursor_start = band(val, 0x1F)
    end,
    [0x0B] = function(self, val) -- Cursor End Register
        self.crtc_cursor_end = band(val, 0x1F)
    end,
    [0x0C] = function(self, val) -- Start Address Register High
        self.crtc_start_addr = bor(band(self.crtc_start_addr, 0x00FF), lshift(band(val, 0x3F), 8))
    end,
    [0x0D] = function(self, val) -- Start Address Register Low
        self.crtc_start_addr = bor(band(self.crtc_start_addr, 0xFF00), val)
    end,
    [0x0E] = function(self, val) -- Cursor Location Register High
        self.crtc_cursor_addr = bor(band(self.crtc_cursor_addr, 0x00FF), lshift(val, 8))
    end,
    [0x0F] = function(self, val) -- Cursor Location Register Low
        self.crtc_cursor_addr = bor(band(self.crtc_cursor_addr, 0xFF00), val)
    end
}

local crtc_regs_read = {
    [0x0E] = function(self)
        return band(rshift(self.crtc_cursor_addr, 8), 0xFF)
    end,
    [0x0F] = function(self)
        return band(self.crtc_cursor_addr, 0xFF)
    end
}

-- VRAM
local function vram_read(self, addr)
    return self[band(addr, 0xFFF)]
end

local function vram_write(self, addr, val)
    self[band(addr, 0xFFF)] = val
end

-- Ports
local function port_crtc_address_out(self)
    return function(cpu, port, val)
        self.crtc_index = band(val, 0x1F)
    end
end

local function port_crtc_address_in(self)
    return function(cpu, port)
        return self.crtc_index
    end
end

local function port_crtc_data_out(self)
    return function(cpu, port, val)
        local reg = crtc_regs_write[self.crtc_index]

        if reg then
            reg(self, val)
        end
    end
end

local function port_crtc_data_in(self)
    return function(cpu, port)
        local reg = crtc_regs_read[self.crtc_index]

        if reg then
            return reg(self)
        end

        return 0xFF
    end
end

local function port_mode_register_out(self)
    return function(cpu, port, val)
        self.video_enable = band(val, 0x08) ~= 0
        self.blink_char_enable = band(val, 0x20) ~= 0
    end
end

local function port_status_in(self)
    return function(cpu, port)
        self.status = bxor(self.status, 0x09)
        return bor(self.status, 0xF0)
    end
end

-- Render
local function update(self)
    for _ = 1, 700, 1 do
        if self.vertical_beam then
            self.vertical_beam = false

            if self.display_on then
                local screen_buffer_index = self.current_line * 720

                for x = 0, 719, 9 do
                    if self.video_enable then
                        local memory_addr = lshift(self.memory_addr, 1)
                        local chr = self.vram[band(memory_addr, 0xFFF)]
                        local attr = self.vram[band(memory_addr + 1, 0xFFF)]
                        local glyph_row = font_9_14[lshift(self.scanline, 8) + chr + 1]
                        local draw_cursor = (self.crtc_cursor_addr == self.memory_addr) and self.cursor_enable
                        local blink = self.blink_enabled and self.blink_char_enable and (band(attr, 0x80) ~= 0) and (not draw_cursor)
                        local colors = palette[attr]
                        local foreground
                        local background

                        if blink or draw_cursor then
                            foreground = colors[2]
                            background = colors[1]
                        else
                            foreground = colors[1]
                            background = colors[2]
                        end

                        if (self.scanline == 12) and (band(attr, 0x07) == 0x01) then -- Underline
                            for i = 0, 8, 1 do
                                self.screen:set_pixel_rgb_i(screen_buffer_index + x + i, foreground)
                            end
                        else
                            local color

                            for i = 0, 7, 1 do
                                if (band(glyph_row, rshift(0x80, band(i, 0x07))) ~= 0) then
                                    color = foreground
                                else
                                    color = background
                                end

                                self.screen:set_pixel_rgb_i(screen_buffer_index + x + i, color)
                            end

                            if band(chr, 0xE0) == 0xC0 then
                                self.screen:set_pixel_rgb_i(screen_buffer_index + x + 8, color)
                            else
                                self.screen:set_pixel_rgb_i(screen_buffer_index + x + 8, background)
                            end
                        end
                    else
                        for i = 0, 8, 1 do
                            self.screen:set_pixel_rgb_i(screen_buffer_index + x + i, 0x000000)
                        end
                    end

                    self.memory_addr = self.memory_addr + 1
                end
            end

            self.current_line = self.current_line + 1

            if self.current_line >= 500 then
                self.current_line = 0
            end
        else
            self.vertical_beam = true

            if self.scanline == self.crtc_max_scanline then
                local old_vlc = self.vlc

                self.memory_addr_backup = self.memory_addr
                self.scanline = 0
                self.vlc = band(self.vlc + 1, 0x7F)

                if self.vlc == self.crtc_vertical_displayed then
                    self.display_on = false
                end

                if old_vlc == self.crtc_vertical_total then
                    self.vlc = 0
                    self.display_on = true
                    self.memory_addr_backup = self.crtc_start_addr
                    self.memory_addr = self.memory_addr_backup
                    self.current_line = 0
                end

                if self.vlc == self.crtc_vsync then
                    self.display_on = false
                    self.blink = band(self.blink + 1, 0x7F)
                    self.blink_enabled = band(self.blink, 0x10) ~= 0

                    if self.crtc_vsync > 0 then
                       self.screen:update()
                    end
                end
            else
                self.scanline = band(self.scanline + 1, 0x1F)
                self.memory_addr = self.memory_addr_backup
                self.cursor_enable = (self.scanline >= self.crtc_cursor_start) and (self.scanline <= self.crtc_cursor_end) and self.blink_enabled
            end
        end
    end
end

local function get_type(self)
    return common.TYPE.MDA
end

local function reset(self)
    self.crtc_index = 0
    self.status = 0x01
    self.current_line = 0
    self.scanline = 0
    self.vlc = 0
    self.memory_addr = 0
    self.memory_addr_backup = 0
    self.blink = 0
    self.crtc_vertical_total = 0
    self.crtc_vertical_displayed = 0
    self.crtc_vsync = 0
    self.crtc_max_scanline = 0
    self.crtc_cursor_start = 0
    self.crtc_cursor_end = 0
    self.crtc_start_addr = 0
    self.crtc_cursor_addr = 0
    self.blink_enabled = false
    self.blink_char_enable = false
    self.video_enable = false
    self.cursor_enable = false
    self.display_on = false
    self.vertical_beam = true
    self.screen:set_scale(1.0, 1.0)
    self.screen:set_resolution(720, 350)
end

function mda.new(cpu, memory, screen)
    local self = {
        screen = screen,
        crtc_index = 0,
        status = 0x01,
        current_line = 0,
        scanline = 0,
        vlc = 0,
        memory_addr = 0,
        memory_addr_backup = 0,
        blink = 0,
        crtc_vertical_total = 0,
        crtc_vertical_displayed = 0,
        crtc_vsync = 0,
        crtc_max_scanline = 0,
        crtc_cursor_start = 0,
        crtc_cursor_end = 0,
        crtc_start_addr = 0,
        crtc_cursor_addr = 0,
        display_on = false,
        vertical_beam = true,
        blink_enabled = false,
        video_enable = false,
        blink_char_enable = false,
        cursor_enable = false,
        vram = {},
        vram_read = vram_read,
        vram_write = vram_write,
        get_type = get_type,
        update = update,
        reset = reset
    }

    local cpu_io = cpu:get_io()

    local crtc_address_out, crtc_address_in = port_crtc_address_out(self),  port_crtc_address_in(self)
    local crtc_data_out, crtc_data_in = port_crtc_data_out(self),  port_crtc_data_in(self)

    cpu_io:set_port(0x3B0, crtc_address_out, crtc_address_in)
    cpu_io:set_port(0x3B1, crtc_data_out, crtc_data_in)
    cpu_io:set_port(0x3B2, crtc_address_out, crtc_address_in)
    cpu_io:set_port(0x3B3, crtc_data_out, crtc_data_in)
    cpu_io:set_port(0x3B4, crtc_address_out, crtc_address_in)
    cpu_io:set_port(0x3B5, crtc_data_out, crtc_data_in)
    cpu_io:set_port(0x3B6, crtc_address_out, crtc_address_in)
    cpu_io:set_port(0x3B7, crtc_data_out, crtc_data_in)
    cpu_io:set_port_out(0x3B8, port_mode_register_out(self))
    cpu_io:set_port(0x3B9, crtc_data_out, crtc_data_in)
    cpu_io:set_port_in(0x3BA, port_status_in(self))

    for i = 0, 0xFFF, 1 do
        self.vram[i] = 0x00
    end

    memory:set_mapping(0xB0000, 0xB8000, vram_read, vram_write, self.vram)

    return self
end

return mda
