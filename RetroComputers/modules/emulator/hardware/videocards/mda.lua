local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot
local cp437 = require("retro_computers:emulator/cp437")
local logger = require("retro_computers:logger")
local mda = {}

local font_9_14 = {}
for _, v in pairs(cp437) do
    font_9_14[v] = "fonts/ibm_pc_8_8/glyphs/" .. v
end
setmetatable(font_9_14, {
    __index = function (t, k)
        if rawget(t, k) then
            return rawget(t, k)
        else
            return "fonts/ibm_pc_8_8/glyphs/0"
        end
    end
})

local function set_cursor_pos(self, x, y)
    self.cursor_x = x
    self.cursor_y = y
    self.display.cursor_x = x
    self.display.cursor_y = y
end

local function get_text_addr(x, y)
	return 0xB0000 + (y * 160) + (x * 2)
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

local function set_mode(self, cpu, vmode, clear)
    logger:debug("MDA: Attempt to set video mode: %02X", vmode)
    -- vmode = 3
	if vmode == 7 then
        self.vmode = vmode
        -- self.mode = bor(vmode, reg_to_mode[vmode])
        self.mode = 0x07
        -- self.status = 0x09

        -- 0x449 - byte, video mode
        cpu.memory[0x449] = self.mode

        -- 0x44A - word, text width
        if vmode == 2 or vmode == 3 then
            cpu.memory[0x44A] = 80
            self.display.width = 80
        else
            cpu.memory[0x44A] = 40
            self.display.width = 40
        end
        cpu.memory[0x44B] = 0
        cpu.memory[0x465] = self.mode
        cpu.memory[0x466] = self.palette

        if clear then
            for y = 0, 24, 1 do
                for x = 0, cpu.memory[0x44A] - 1, 1 do
                    local addr = self.start_addr + ((y * 160) + (x * 2))
                    cpu.memory:w16(addr, 0x0700)
                end
            end
        end
        return true
	else
        return false
    end
end

local function port_3B0_3B2_3B4_3B6(self)
    return function(cpu, port, val)
        if val then
            self.index = band(val, 31)
        else
            return self.index
        end
    end
end

local function port_3B1_3B3_3B5_3B7(self)
    return function (cpu, port, val)
        if val then
            self.regs[self.index] = val
            if (self.regs[10] == 6) and (self.regs[11] == 7) then
                self.regs[10] = 0xB
                self.regs[11] = 0xC
            end
        else
            return self.regs[self.index]
        end
    end
end

local function port_3B8(self)
    return function (cpu, port, val)
        if val then
            self.ctrl = val
        end
    end
end

local function port_3BA(self)
    return function (cpu, port, val)
        return bor(self.status, 0xF0)
    end
end

local function read(self, addr)
    return self.vram[addr - 0xB0000] or 0
end

local function write(self, addr, val)
    self.vram[addr - 0xB0000] = val
end

local function update(self)
    for y = 0, 24, 1 do
        local base = (y * 160)
		for x = 0, 79, 1 do
			local chr = (self.vram[base + (x * 2)] or 0) or 0
			local atr = self.vram[base + x + 1] or 0
            local bg = rshift(band(atr, 0xFF00), 8)
			local fg = band(atr, 0x00FF)
            self.display.buffer[y * 80 + x] = {chr, 1, 1}
            self.status = bor(self.status, 8)
            self.status = band(self.status, bnot(1))
		end
	end
    self.display.update()
end

local function reset(self)
    
end

local function int_10(self)
    return function(cpu, ax,ah,al)
        if ah == 0x00 then -- Set video mode
            local mode = band(al, 0xFF7F)
            set_mode(self, cpu, mode, band(al, 0x80) == 0)
            return true
        elseif ah == 0x01 then -- Set cursor shape, TODO
            return true
        elseif ah == 0x02 then -- Set cursor position
            -- set_cursor_pos(self, cpu, band(cpu.regs[3], 0xFF), rshift(cpu.regs[3], 8), rshift(cpu.regs[4], 8))
            return true
        elseif ah == 0x03 then -- Get cursor position
            -- local cursor_x, cursor_y = get_cursor_pos(cpu, rshift(cpu.regs[4], 8))
            cpu.regs[3] = bor(lshift(0, 8), (0))
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
            -- local cursor_x, cursor_y = get_cursor_pos(cpu, rshift(cpu.regs[4], 8))
            -- local addr = get_text_addr(cursor_x, cursor_y)
            -- cpu.regs[1] = bor(0x0800, cpu.memory[addr])
            -- cpu.regs[4] = bor(band(cpu.regs[4], 0xFF), lshift(cpu.memory[addr + 1], 8))
            return true
        elseif ah == 0x09 or ah == 0x0A then  -- Write character/attribute (0x09) or char (0x0A)
            local addr = self.start_addr + ((self.cursor_y * 160) + (self.cursor_x * 2))
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

            return false
        elseif ah == 0x0C then -- Read Graphics Pixel

            return false
        elseif ah == 0x0E then -- Write Character in TTY Mode
            local cursor_x, cursor_y = self.cursor_x, self.cursor_y
            -- local addr = get_text_addr(cursor_x, cursor_y)
            local addr = self.start_addr + ((cursor_y * 160) + (cursor_x * 2))
            if al == 0x0D then -- CR
                cursor_x = 0
            elseif al == 0x0A then -- LF
                if cursor_y < 24 then
                    cursor_y = cursor_y + 1
                else
                scroll_up(cpu, 1, 0x07, 0, 0, 24, 79)
                end
            elseif al == 0x08 then -- BS
                if cursor_x > 0 then
                    cursor_x = cursor_x - 1
                end
                -- cpu.memory[get_text_addr(cursor_x, cursor_y)] = 0
            elseif al == 0x07 then -- BEll

            else
                cpu.memory[addr] = al
                cursor_x = cursor_x + 1
                if cursor_x >= 80 then
                    cursor_x = 0
                    if cursor_y < 24 then
                        cursor_y = cursor_y + 1
                    else
                        scroll_up(cpu, 1, 0x07, 0, 0, 24, 79)
                    end
                end
            end
            set_cursor_pos(self, cursor_x, cursor_y)
            return true
        elseif ah == 0x0F then -- Read video mode
            local ah = cpu.memory[0x44A]
            local al = 0
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

function mda.new(cpu, display)
    local self = {
        index = 0,
        regs = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        ctrl = 0,
        status = 0,
        vram = {},
        vram_read = read,
        vram_write = write,
        update = update,
        reset = reset,
        get_mode = function ()
            return 7
        end,
        set_mode = function ()

        end,
        display = display,
        start_addr = 0xB0000,
        end_addr = 0xBFFFF,
        cursor_x = 0,
        cursor_y = 0,
        color_palette = {{0, 255, 0, 255}},
        glyph_width = 8,
        glyph_height = 8,
        textmode = true,
        font = font_9_14
    }
    setmetatable(self.color_palette, {
        __index = function (t, k)
            if rawget(t, k) then
                return rawget(t, k)
            end
            return {0, 255, 0, 255}
        end
    })

    cpu:port_set(0x3B0, port_3B0_3B2_3B4_3B6(self))
    cpu:port_set(0x3B2, port_3B0_3B2_3B4_3B6(self))
    cpu:port_set(0x3B4, port_3B0_3B2_3B4_3B6(self))
    cpu:port_set(0x3B6, port_3B0_3B2_3B4_3B6(self))

    cpu:port_set(0x3B1, port_3B1_3B3_3B5_3B7(self))
    cpu:port_set(0x3B3, port_3B1_3B3_3B5_3B7(self))
    cpu:port_set(0x3B5, port_3B1_3B3_3B5_3B7(self))
    cpu:port_set(0x3B7, port_3B1_3B3_3B5_3B7(self))

    cpu:port_set(0x3B8, port_3B8(self))
    cpu:port_set(0x3BA, port_3BA(self))

    cpu:register_interrupt_handler(0x10, int_10(self))

    return self
end

return mda