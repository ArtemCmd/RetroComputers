-- local logger = require("retro_computers:logger")
local cp437 = require("retro_computers:emulator/cp437")

local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor
local video_mode = 3
local display
local cga_mode = 0x08
local cga_palette = 0x30
local cga_status = 0x09
local cga_mode_mask = 0x17
local reg_to_mode = {
    [0] = 0x04, -- 40x25 mono
    [1] = 0x00, -- 40x25 color
    [2] = 0x05, -- 80x25 mono
    [3] = 0x01, -- 80x25 color
    [4] = 0x02, -- 320x200 graphics
    [5] = 0x06, -- 320x200 alt graphics
    [6] = 0x16 -- 640x200 graphics
}

local vram = {}

local function vram_read(addr)
    -- logger:debug("CGA: Read from vram")
	return vram[addr - 0x9FFFF] or 0
end

local function vram_write(addr, val)
    -- logger:debug("CGA: Write %d to vram", val)
	if vram[addr - 0x9FFFF] == val then
        return
    end
	vram[addr - 0x9FFFF] = val
end

local function get_text_addr(x, y)
	return 0xB8000 + (y * 160) + (x * 2)
end

local function scroll_up(cpu, lines, empty_attr, y1, x1, y2, x2)
	if lines == 0 then
		for y=y1,y2 do
            for x=x1,x2 do
                cpu.memory:w16(get_text_addr(x,y), lshift(empty_attr, 8))
            end
		end
	else
		for y=y1+lines,y2 do
            for x=x1,x2 do
                cpu.memory:w16(get_text_addr(x,y-lines), cpu.memory:r16(get_text_addr(x,y)))
            end
		end
		for y=y2-lines+1,y2 do
            for x=x1,x2 do
                cpu.memory:w16(get_text_addr(x,y), lshift(empty_attr, 8))
            end
		end
	end
end

local function scroll_down(cpu, lines, empty_attr, y1, x1, y2, x2)
	if lines == 0 then
		for y=y1,y2 do
            for x=x1,x2 do
                cpu.memory:w16(get_text_addr(x,y), lshift(empty_attr, 8))
            end
		end
	else
		for y=y2-lines,y1,-1 do
            for x=x1,x2 do
                cpu.memory:w16(get_text_addr(x,y+lines), cpu.memory:r16(get_text_addr(x,y)))
            end
		end
		for y=y1,y1+lines-1 do
            for x=x1,x2 do
                cpu.memory:w16(get_text_addr(x,y), lshift(empty_attr, 8))
            end
		end
	end
end

local function get_mode()
    return video_mode
end

local function set_mode(cpu, vmode, clear)
    -- logger:debug("CGA: Attempt to set video mode: %02X", vmode)
    --vmode = 3
	if (vmode >= 0) and (vmode <= 6) then
        video_mode = vmode
        -- logger:debug("CGA: Seting video mode: " .. vmode)
        cga_mode = bor(cga_mode, reg_to_mode[vmode])
        cga_status = 0x09

        -- 0x449 - byte, video mode
        cpu.memory[0x449] = video_mode

        -- 0x44A - word, text width
        if vmode == 2 or vmode == 3 then
            cpu.memory[0x44A] = 80
            display.width = 80
        else
            cpu.memory[0x44A] = 40
            display.width = 40
        end
        cpu.memory[0x44B] = 0
        cpu.memory[0x465] = cga_mode
        cpu.memory[0x466] = cga_palette

        if clear then
            if (vmode >= 0 and vmode <= 3) then
                for y=0,24 do
                    for x=0,cpu.memory[0x44A]-1 do
                        cpu.memory:w16(get_text_addr(x,y), 0x0700)
                    end
                end
            else
                for i=0,7999 do
                    cpu.memory[0xB8000 + i] = 0
                    cpu.memory[0xBA000 + i] = 0
                end
            end
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
	return cpu.memory[0x450+page], cpu.memory[0x451+page]
end

local function set_cursor_pos(cpu, x, y, page)
	if page == nil then
		page = lshift(band(cpu.memory[0x462], 7), 1)
	end
	cpu.memory[0x450+page] = x
	cpu.memory[0x451+page] = y
    display.cursor_x = x
    display.cursor_y = y
end

-- CGA ports
local crtc_index = 0
local cursor_high = 0
local cursor_low = 0

local function port_3D4(cpu, port, val) -- CRT Controller Register's
	if not val then
        return crtc_index
	elseif val >= 0 and val <= 0x11 then
        crtc_index = val
    end
end

local function port_3D5(cpu, port, val)
	if val then
		if crtc_index == 0x0E then
			cursor_high = val
		elseif crtc_index == 0x0F then
			cursor_low = val
        elseif crtc_index == 0x0C then

        end

        local position = 0
        position = bor(position, cursor_low)
        position = bor(position, lshift(cursor_high, 8))
        display.cursor_x = math.floor(position % 80)
        display.cursor_y = math.floor(position / 80)
	else
		if crtc_index == 0x0E then
			return rshift(cursor_high, 8)
		elseif crtc_index == 0x0F then
			return band(cursor_low, 0xFF)
		else
			return 0
		end
	end
end

-- Mode
local function port_3D8(cpu, port, val)
	if not val then return cga_mode else
		cga_mode = band(val, 0x3F)
		for i=0,6 do
			if reg_to_mode[i] == band(cga_mode, cga_mode_mask) then
				set_mode(cpu, i, true)
			end
		end
		cpu.memory[0x465] = cga_mode
	end
end

-- Color
local function port_3D9(cpu, port, val)
	if not val then return cga_palette else
		cga_palette = band(val, 0x3F)
		cpu.memory[0x466] = cga_palette
	end
end

-- Status Register
local function port_3DA(cpu, port, val)
	if not val then
		cga_status = bxor(cga_status, 0x09)
		return cga_status
	end
end

-- Clear Light Pen Latch Register
local function port_3DB(cpu, port, val)
    
end

-- Set Light Pen Latch Register
local function port_3DC(cpu, port, val)
    
end

-- Interrupt
local function int_10(cpu, ax,ah,al)
    if ah == 0x00 then -- Set video mode
        local mode = band(al, 0xFF7F)
        set_mode(cpu, mode, band(al, 0x80) == 0)
        return true
    elseif ah == 0x01 then -- Set cursor shape, TODO
        return true
    elseif ah == 0x02 then -- Set cursor position
        set_cursor_pos(cpu, band(cpu.regs[3], 0xFF), rshift(cpu.regs[3], 8), rshift(cpu.regs[4], 8))
        return true
    elseif ah == 0x03 then -- Get cursor position
        local cursor_x, cursor_y = get_cursor_pos(cpu, rshift(cpu.regs[4], 8))
        cpu.regs[3] = bor(lshift(cursor_y, 8), (cursor_x))
        return true
    elseif ah == 0x04 then -- Query light pen
        -- cpu.regs[1] = al
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
        for i=1,cpu.regs[2] do
            cpu.memory[addr] = al
            if ah == 0x09 then
                cpu.memory[addr + 1] = bl
            end
            addr = addr + 2
        end
        return true
    elseif ah == 0x0B then -- Configure videomode
        local p = cga_palette
        local bh = rshift(cpu.regs[4], 8)
        local bl = band(cpu.regs[4], 0xFF)
        if bh == 0x00 then
        elseif bh == 0x01 then
            p = bor(band(p, 0xDF), lshift(band(bl, 0x01), 5))
        end
        cga_palette = p
        cpu.memory[0x466] = p
        return true
    elseif ah == 0x0C then -- Write Graphics Pixel
        -- TODO
        return false
    elseif ah == 0x0C then -- Read Graphics Pixel
        -- TODO
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
        set_cursor_pos(cpu, cursor_x, cursor_y)
        return true
    elseif ah == 0x0F then -- Read video mode
        local ah = cpu.memory[0x44A]
        local al = video_mode
        local bh = cpu.memory[0x462]
        cpu.regs[1] = bor(lshift(ah, 8), (al))
        cpu.regs[4] = bor(band(cpu.regs[4], 0xFF), lshift(bh, 8))
        return true
    else
        cpu:set_flag(0)
        return false
    end
end

-- Render
local function render_text(vram, addr, width, height, pitch)
	for y = 0, height - 1, 1 do
		local base = addr + (y * pitch)
		for x = 0, width - 1, 1 do
			local chr = cp437[vram[base + x*2] or 0]
			local atr = vram[base + x*2 + 1] or 0
            local bg = rshift(band(atr, 0xFF00), 8)
			local fg = band(atr, 0x00FF)
            display.buffer[y * width + x] = {chr, bg, fg}
		end
	end
end

local function render_mono(vram, addr)
	for y = 0, 199, 1 do
		for x = 0, 639, 1 do
            local c1 = vram[addr + (rshift((y / 2), 1) * 80) + (band((y / 2), 1) * 8192) + rshift(x, 3)] or 0
            display.buffer[y * 640 + x] = band(rshift(c1, (7 - band(x, 7))), 1) * 15
		end
	end
end

local function render_color(vram, addr)
    for y = 0, 399, 1 do
        for x = 0, 319, 1 do
            local pixel = vram[addr + (rshift((y / 2), 1) * 80) + (band((y / 2), 1) * 8192) + rshift(x, 2)]
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
            display.buffer[y * 320 + x] = pixel
        end
    end
end

local function update()
	if video_mode == 0 or video_mode == 1 then
		render_text(vram, 0xB8000 - 0x9FFFF, 40, 25, 160)
	elseif video_mode == 2 or video_mode == 3 then
		render_text(vram, 0xB8000 - 0x9FFFF, 80, 25, 160)
	elseif video_mode >= 4 and video_mode <= 6 then
		if video_mode < 6 then
			render_color(vram, 0xB8000 - 0x9FFFF)
		else
			render_mono(vram, 0xB8000 - 0x9FFFF)
		end
	end
    display.update()
end

local videocard = {}

local function reset(self)
    self.cpu.memory[0x450] = 0
    self.cpu.memory[0x451] = 0
    self.cpu.memory[0x462] = 0
    self.cpu.memory:w16(0x463, 0x3D4)
end

function videocard.new(cpu, d)
    local instance = {
        cpu = cpu,
        set_mode = set_mode,
        update = update,
        reset = reset,
        vram_read = vram_read,
        vram_write = vram_write,
        get_mode = get_mode
    }

    display = d

    instance:reset()
    cpu:register_interrupt_handler(0x10, int_10)

    cpu:port_set(0x3D4, port_3D4)
    cpu:port_set(0x3D5, port_3D5)
    cpu:port_set(0x3D8, port_3D8)
    cpu:port_set(0x3D9, port_3D9)
    cpu:port_set(0x3DA, port_3DA)
    cpu:port_set(0x3DB, port_3DB)
    cpu:port_set(0x3DC, port_3DC)
    return instance
end

return videocard