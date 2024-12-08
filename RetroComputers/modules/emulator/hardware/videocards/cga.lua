local logger = require("retro_computers:logger")
local cp437 = require("retro_computers:emulator/cp437")

local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor
local reg_to_mode = {
    [0] = 0x04, -- 40x25 mono
    [1] = 0x00, -- 40x25 color
    [2] = 0x05, -- 80x25 mono
    [3] = 0x01, -- 80x25 color
    [4] = 0x02, -- 320x200 graphics
    [5] = 0x06, -- 320x200 alt graphics
    [6] = 0x16 -- 640x200 graphics
}
-- Font
local font_8_8 = {}
for _, v in pairs(cp437) do
    font_8_8[v] = "fonts/ibm_pc_8_8/glyphs/" .. v
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

local function vram_read(self, addr)
    -- logger:debug("CGA: Read from vram")
	return self.vram[addr - 0x9FFFF] or 0
end

local function vram_write(self, addr, val)
    -- logger:debug("CGA: Write %s to vram", string.char(val))
	if self.vram[addr - 0x9FFFF] == val then
        return
    end
	self.vram[addr - 0x9FFFF] = val
end

local function get_text_addr(x, y)
	return 0xB8000 + (y * 160) + (x * 2)
end

local function scroll_up(cpu, lines, empty_attr, y1, x1, y2, x2)
	if lines == 0 then
		for y = y1, y2, 1 do
            for x = x1, x2, 1 do
                cpu.memory:w16(get_text_addr(x, y), lshift(empty_attr, 8))
            end
		end
	else
		for y = y1 + lines, y2, 1 do
            for x = x1, x2, 1 do
                cpu.memory:w16(get_text_addr(x, y - lines), cpu.memory:r16(get_text_addr(x, y)))
            end
		end
		for y = y2 - lines + 1, y2 do
            for x=x1,x2 do
                cpu.memory:w16(get_text_addr(x, y), lshift(empty_attr, 8))
            end
		end
	end
end

local function scroll_down(cpu, lines, empty_attr, y1, x1, y2, x2)
	if lines == 0 then
		for y = y1, y2, 1 do
            for x = x1, x2, 1 do
                cpu.memory:w16(get_text_addr(x, y), lshift(empty_attr, 8))
            end
		end
	else
		for y = y2 - lines, y1, -1 do
            for x = x1, x2, 1 do
                cpu.memory:w16(get_text_addr(x, y + lines), cpu.memory:r16(get_text_addr(x, y)))
            end
		end
		for y = y1, y1 + lines - 1, 1 do
            for x = x1, x2 do
                cpu.memory:w16(get_text_addr(x, y), lshift(empty_attr, 8))
            end
		end
	end
end

local function get_mode(self)
    return self.vmode
end

local function set_mode(self, cpu, vmode, clear)
    logger:debug("CGA: Attempt to set video mode: %02X", vmode)
    -- vmode = 3
	if (vmode >= 0) and (vmode <= 6) then
        self.vmode = vmode
        self.mode = bor(vmode, reg_to_mode[vmode])
        self.status = 0x09

        -- 0x449 - byte, video mode
        cpu.memory[0x449] = self.mode

        -- 0x44A - word, text width
        if (vmode == 2) or (vmode == 3) then
            cpu.memory[0x44A] = 80
            self.display.width = 80
            self.display.height = 25
        elseif (vmode == 1) or (vmode == 0) then
            cpu.memory[0x44A] = 40
            self.display.width = 40
            self.display.height = 25
        elseif (vmode == 4) or (vmode == 5) then
            self.display.width = 320
            self.display.height = 200
        elseif vmode == 6 then
            self.display.width = 640
            self.display.height = 200
        end

        cpu.memory[0x44B] = 0
        cpu.memory[0x465] = self.mode
        cpu.memory[0x466] = self.palette

        if clear then
            if (vmode >= 0 and vmode <= 3) then
                for y = 0, 24, 1 do
                    for x = 0, cpu.memory[0x44A] - 1, 1 do
                        cpu.memory:w16(get_text_addr(x,y), 0x0700)
                    end
                end
            else
                for i = 0, 7999, 1 do
                    cpu.memory[0xB8000 + i] = 0
                    cpu.memory[0xBA000 + i] = 0
                end
            end
        end

        if self.vmode < 4 then
            self.textmode = true
        else
            self.textmode = false
        end
        return true
	else
        return false
    end
end

local function get_cursor_pos(cpu, page)
	if page == nil then
		page = lshift(band(cpu.memory[0x462], 7), 1)
	end
	return cpu.memory[0x450 + page], cpu.memory[0x451 + page]
end

local function set_cursor_pos(self, cpu, x, y, page)
	if page == nil then
		page = lshift(band(cpu.memory[0x462], 7), 1)
	end
	cpu.memory[0x450 + page] = x
	cpu.memory[0x451 + page] = y
    self.display.cursor_x = x
    self.display.cursor_y = y
end

-- CGA ports
local function port_3D4(self) -- CRT Controller Register's
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
            elseif self.crtc_index == 0x0F then
                self.cursor = bor(band(self.cursor, 0xFF00), band(val, 0xFF))
            elseif self.crtc_index == 0x0C then

            end

            local position = bor(band(self.cursor, 0x00FF), lshift(band(rshift(self.cursor, 8), 0xFF), 8))
            self.display.cursor_x = math.floor(position % 80)
            self.display.cursor_y = math.floor(position / 80)
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

-- Mode
local function port_3D8(self)
    return function(cpu, port, val)
        if val then
            self.mode = band(val, 0x3F)
            for i = 0, 6 do
                if reg_to_mode[i] == band(self.mode, 0x17) then
                    set_mode(self, cpu, i, true)
                end
            end
            cpu.memory[0x465] = self.mode
        else
            return self.mode
        end
    end
end

-- Color
local function port_3D9(self)
    return function(cpu, port, val)
        if val then
            self.palette = band(val, 0x3F)
            cpu.memory[0x466] = self.palette
        else
            return self.palette
        end
    end
end

-- Status Register
local function port_3DA(self)
    return function(cpu, port, val)
        if not val then
            self.status = bxor(self.status, 0x09)
            return self.status
        end
    end
end

-- Clear Light Pen Latch Register
local function port_3DB(self)
    return function(cpu, port, val)
    end
end

-- Set Light Pen Latch Register
local function port_3DC(self)
    return function(cpu, port, val)
    end
end

-- Interrupt
local function int_10(self)
    return function(cpu, ax,ah,al)
        if ah == 0x00 then -- Set video mode
            local mode = band(al, 0xFF7F)
            set_mode(self, cpu, mode, band(al, 0x80) == 0)
            return true
        elseif ah == 0x01 then -- Set cursor shape, TODO
            return true
        elseif ah == 0x02 then -- Set cursor position
            set_cursor_pos(self, cpu, band(cpu.regs[3], 0xFF), rshift(cpu.regs[3], 8), rshift(cpu.regs[4], 8))
            return true
        elseif ah == 0x03 then -- Get cursor position
            local cursor_x, cursor_y = get_cursor_pos(cpu, rshift(cpu.regs[4], 8))
            cpu.regs[3] = bor(lshift(cursor_y, 8), (cursor_x))
            return true
        elseif ah == 0x04 then -- Query light pen
            cpu.regs[1] = 0
            return true
        elseif ah == 0x05 then  -- Select video page
            cpu.memory[0x462] = band(al, 0x07)
            return true
        elseif ah == 0x06 then -- Scroll up
            scroll_up(cpu, al, rshift(cpu.regs[4], 8), rshift(cpu.regs[2], 8), band(cpu.regs[2], 0xFF), rshift(cpu.regs[3], 8), band(cpu.regs[3], 0xFF));
            return true
        elseif ah == 0x07 then -- Scroll down
            scroll_down(al, rshift(cpu.regs[4], 8), rshift(cpu.regs[2], 8), band(cpu.regs[2], 0xFF), rshift(cpu.regs[3], 8), band(cpu.regs[3], 0xFF));
            return true
        elseif ah == 0x08 then -- Read character
            local cursor_x, cursor_y = get_cursor_pos(cpu, rshift(cpu.regs[4], 8))
            local addr = get_text_addr(cursor_x, cursor_y)
            cpu.regs[1] = bor(0x0800, cpu.memory[addr])
            cpu.regs[4] = bor(band(cpu.regs[4], 0xFF), lshift(cpu.memory[addr + 1], 8))
            return true
        elseif ah == 0x09 or ah == 0x0A then  -- Write character/attribute (0x09) or char (0x0A)
            local cursor_x, cursor_y = get_cursor_pos(cpu, rshift(cpu.regs[4], 8))
            local addr = get_text_addr(cursor_x, cursor_y)
            local bl = band(cpu.regs[4], 0xFF)
            for _ = 1, cpu.regs[2], 1 do
                cpu.memory[addr] = al
                if ah == 0x09 then
                    cpu.memory[addr + 1] = bl
                end
                addr = addr + 2
            end
            return true
        elseif ah == 0x0B then -- Configure videomode
            local p = self.palette
            local bh = rshift(cpu.regs[4], 8)
            local bl = band(cpu.regs[4], 0xFF)
            if bh == 0x00 then
            elseif bh == 0x01 then
                p = bor(band(p, 0xDF), lshift(band(bl, 0x01), 5))
            end
            self.palette = p
            cpu.memory[0x466] = p
            return true
        elseif ah == 0x0C then -- Write Graphics Pixel
            if self.mode > 3 then
                local x = cpu.regs[3]
                local y = cpu.regs[2]
                local color = band(cpu.regs[1], 0xFF)
                self.vram[(0xB8000 - 0x9FFFF) + (rshift((y / 2), 1) * 80) + (band((y / 2), 1) * 8192) + rshift(x, 2)] = color
            end
            return false
        elseif ah == 0x0C then -- Read Graphics Pixel
            if self.mode > 3 then
                local x = cpu.regs[3]
                local y = cpu.regs[2]
                cpu.regs[1] = bor(lshift(ah, 8), self.vram[(0xB8000 - 0x9FFFF) + (rshift((y / 2), 1) * 80) + (band((y / 2), 1) * 8192) + rshift(x, 2)])
            end
            return false
        elseif ah == 0x0E then -- Write Character in TTY Mode
            local cursor_x, cursor_y = get_cursor_pos(cpu)
            local addr = get_text_addr(cursor_x, cursor_y)
            local cursor_width = cpu.memory[0x44A]
            local cursor_height = 25
            if al == 0x0D then -- CR
                cursor_x = 0
            elseif al == 0x0A then -- LF
                if cursor_y < (cursor_height - 1) then
                    cursor_y = cursor_y + 1
                else
                scroll_up(cpu, 1, 0x07, 0, 0, cursor_height - 1, cursor_width - 1)
                end
            elseif al == 0x08 then -- BS
                if cursor_x > 0 then
                    cursor_x = cursor_x - 1
                end
                cpu.memory[get_text_addr(cursor_x, cursor_y)] = 0
            elseif al == 0x07 then -- BEll

            else
                cpu.memory[addr] = al
                cursor_x = cursor_x + 1
                if cursor_x >= cursor_width then
                    cursor_x = 0
                    if cursor_y < (cursor_height - 1) then
                        cursor_y = cursor_y + 1
                    else
                        scroll_up(cpu, 1, 0x07, 0, 0, cursor_height - 1, cursor_width - 1)
                    end
                end
            end
            set_cursor_pos(self, cpu, cursor_x, cursor_y)
            return true
        elseif ah == 0x0F then -- Read video mode
            local ah = cpu.memory[0x44A]
            local al = self.vmode
            local bh = cpu.memory[0x462]
            cpu.regs[1] = bor(lshift(ah, 8), (al))
            cpu.regs[4] = bor(band(cpu.regs[4], 0xFF), lshift(bh, 8))
            return true
        else
            cpu:set_flag(0)
            return false
        end
    end
end

-- Render
local function render_text(self, addr, width, height)
	for y = 0, height - 1, 1 do
		local base = addr + (y * 160)
		for x = 0, width - 1, 1 do
			local chr = cp437[self.vram[base + x * 2] or 0]
			local atr = self.vram[base + x * 2 + 1] or 0
            local bg = rshift(band(atr, 0xFF00), 8)
			local fg = band(atr, 0x00FF)
            self.display.buffer[y * width + x] = {chr, bg, fg}
		end
	end
end

local function render_mono(self, addr)
	for y = 0, 199, 1 do
		for x = 0, 639, 1 do
            local pixel = self.vram[addr + (rshift((y / 2), 1) * 80) + (band((y / 2), 1) * 8192) + rshift(x, 3)] or 0
            self.display.buffer[y * 640 + x] = band(rshift(pixel, (7 - band(x, 7))), 1) * 15
		end
	end
end

local function render_color(self, addr)
    for y = 0, 199, 1 do
        for x = 0, 319, 1 do
            local pixel = self.vram[addr + (rshift((y / 2), 1) * 80) + (band((y / 2), 1) * 8192) + rshift(x, 2)]
            local p = band(x, 3)
            if p == 3 then
                pixel = band(pixel, 3)
            elseif p == 2 then
                pixel = band(rshift(pixel, 2), 2)
            elseif p == 1 then
                pixel = band(rshift(pixel, 4), 3)
            elseif p == 0 then
                pixel = band(rshift(pixel, 6), 3)
            end
            self.display.buffer[y * 320 + x] = pixel
        end
    end
end

local function update(self)
	if self.vmode == 0 or self.vmode == 1 then
		render_text(self, 0xB8000 - 0x9FFFF, 40, 25)
	elseif self.vmode == 2 or self.vmode == 3 then
		render_text(self, 0xB8000 - 0x9FFFF, 80, 25)
	elseif self.vmode >= 4 and self.vmode <= 6 then
		if self.vmode < 6 then
			render_color(self, 0xB8000 - 0x9FFFF)
		else
			render_mono(self, 0xB8000 - 0x9FFFF)
		end
	end
    self.display.update()
end

local videocard = {}

local function reset(self)
    self.cpu.memory[0x450] = 0
    self.cpu.memory[0x451] = 0
    self.cpu.memory[0x462] = 0
    self.cpu.memory:w16(0x463, 0x3D4)
end

function videocard.new(cpu, display)
    local self = {
        cpu = cpu,
        vram = {},
        status = 0x09,
        mode = 8,
        vmode = 0,
        palette = 0x30,
        crtc_index = 0,
        cursor = 0,
        display = display,
        set_mode = set_mode,
        update = update,
        reset = reset,
        vram_read = vram_read,
        vram_write = vram_write,
        get_mode = get_mode,
        textmode = true,
        start_addr = 0xB8000,
        end_addr = 0xBFFFF,
        -- Font
        font = font_8_8,
        glyph_width = 8,
        glyph_height = 8,
        color_palette = {
            {0, 0, 0, 255}, -- black
            {0, 0, 170, 255}, -- blue
            {0, 170, 0, 255}, -- green
            {0, 170, 170, 255}, -- cyan
            {170, 0, 0, 255}, -- red
            {170, 0, 170, 255}, -- magenta
            {170, 85, 0, 255}, -- brown
            {170, 170, 170, 255}, -- light gray
            {85, 85, 85, 255}, -- dark gray
            {85, 85, 255, 255}, -- light blue
            {85, 255, 85, 255}, -- light green
            {85, 255, 255, 255}, -- light cyan
            {255, 85, 85, 255}, -- light red
            {255, 85, 255, 255}, -- light magenta
            {255, 255, 85, 255}, -- yellow
            {255, 255, 255, 255} -- white
        }
    }
    setmetatable(self.color_palette, {
        __index = function (t, k)
            if rawget(t, k) then
                return rawget(t, k)
            end
            return {0, 255, 255, 255}
        end
    })

    cpu:register_interrupt_handler(0x10, int_10(self))

    cpu:port_set(0x3D4, port_3D4(self))
    cpu:port_set(0x3D5, port_3D5(self))
    cpu:port_set(0x3D8, port_3D8(self))
    cpu:port_set(0x3D9, port_3D9(self))
    cpu:port_set(0x3DA, port_3DA(self))
    cpu:port_set(0x3DB, port_3DB(self))
    cpu:port_set(0x3DC, port_3DC(self))

    self:reset()
    return self
end

return videocard