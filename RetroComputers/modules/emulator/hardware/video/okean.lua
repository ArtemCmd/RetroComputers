-- =====================================================================================================================================================================
-- Okean 240 Videocard emulation.
-- =====================================================================================================================================================================

local logger = require("dave_logger:logger")("RetroComputers")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local video = {}

local palette_color = {
    [0] = {[0] = 0x000000, 0xFF0000, 0x00FF00, 0x0000FF},
    {[0] = 0xFFFFFF, 0xFF0000, 0x00FF00, 0x0000FF},
    {[0] = 0xFF0000, 0x00FF00, 0xFF0000, 0xFFFF00},
    {[0] = 0x000000, 0xFF0000, 0xBF00FF, 0xFFFFFF},
    {[0] = 0x000000, 0xFF0000, 0xFFFF00, 0x0000FF},
    {[0] = 0x000000, 0x0000FF, 0x00FF00, 0xFFFF00},
    {[0] = 0xFF0000, 0xFFFFFF, 0xFFFF00, 0x0000FF},
    {[0] = 0x000000, 0x000000, 0x000000, 0x000000}
}

local palette_mono = {
    [0] = {[0] = 0xFFFFFF, 0x000000},
	{[0] = 0x00007F, 0x00FF00},
	{[0] = 0xFF0000, 0x7F0000},
	{[0] = 0xCF00CF, 0x0000FF},
	{[0] = 0x007F00, 0xBF00FF},
	{[0] = 0x004B96, 0xFFFF00},
	{[0] = 0xFF4000, 0x000000},
	{[0] = 0x7F7F7F, 0x7F7F7F}
}

local function get_vram(self)
    return self.vram
end

local function render_mono(self)
    for i = 0, 255, 1 do
        local addr = i
        local offset = lshift(band(i - self.vram_offset, 0xFF), 9)

        for j = 0, 511, 1 do
            local color = band(rshift(self.vram[addr], band(j, 0x07)), 0x01)

            if band(j, 0x07) == 0x07 then
                addr = addr + 0x100
            end

            self.screen:set_pixel_rgb_i(offset + i, self.palette[color])
        end
    end
end

local function render_color(self)
    for i = 0, 255, 1 do
        local addr = i
        local offset = lshift(band(i - self.vram_offset, 0xFF), 8)

        for j = 0, 255, 1 do
            local bit = band(j, 0x07)
            local color = lshift(band(rshift(self.vram[addr], bit), 0x01), 1)
            color = bor(color, band(rshift(self.vram[bor(addr, 0x100)], bit), 0x01))

            if band(j, 0x07) == 0x07 then
                addr = addr + 0x200
            end

            self.screen:set_pixel_rgb_i(offset + j, self.palette[color])
        end
    end
end

-- Ports
local function port_control_out(self)
    return function(cpu, port, val)
        local palette

        if band(val, 0x40) ~= 0 then
            palette = palette_color
            self.render = render_color
            self.screen.scale_x = 2.0
            self.screen.scale_y = 2.0
            self.screen:set_resolution(256, 256)
        else
            palette = palette_mono
            self.render = render_mono
            self.screen.scale_x = 1.0
            self.screen.scale_y = 2.0
            self.screen:set_resolution(512, 256)
        end

        self.palette = palette[band(val, 0x07)]
    end
end

local function port_offset_out(self)
    return function(cpu, port, val)
        self.vram_offset = band(val, 0xFF)
    end
end

local function update(self)
    self.render(self)
    self.screen:update()
end

local function get_type(self)
    return 0
end

local function reset(self)
    self.palette = palette_mono[0]
    self.vram_offset = 0
    self.render = render_mono
    self.screen:set_scale(1.0, 1.0)
    self.screen:set_resolution(512, 256)
end

function video.new(cpu, screen)
    local self = {
        screen = screen,
        vram = {},
        palette = palette_mono[0],
        vram_offset = 0,
        get_vram = get_vram,
        get_type = get_type,
        render = render_mono,
        update = update,
        reset = reset
    }

    local cpu_io = cpu:get_io()

    cpu_io:set_port_out(0xC0, port_offset_out(self))
    cpu_io:set_port_out(0xE1, port_control_out(self))

    for i = 0, 16383, 1 do
        self.vram[i] = 0x00
    end

    return self
end

return video
