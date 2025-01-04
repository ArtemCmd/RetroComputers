local logger = require("retro_computers:logger")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

-- Serial
local com_ports = {[0] = 0x3F8, 0x2F8, 0x3E8}
local com_speed = {[0] = {1047, 4}, {2304, 9}, {384, 1}, {192, 00}, {96, 00}, {48, 00}, {24, 00}, {12, 00}}

-- LPT
local lpt_ports = {0x378, 0x278, 0x3BC}

-- Keyboard
local extended_ascii = {
    [0x3B] = 0x3B, -- F1
    [0x3C] = 0x3C, -- F2
    [0x3D] = 0x3D, -- F3
    [0x3E] = 0x3E, -- F4
    [0x3F] = 0x3F, -- F5
    [0x40] = 0x40, -- F6
    [0x41] = 0x41, -- F7
    [0x42] = 0x42, -- F8
    [0x43] = 0x43, -- F9
    [0x44] = 0x44, -- F10
    [0x52] = 0x52, -- Ins
    [0x53] = 0x53, -- Del
    [0x50] = 0x50, -- Down
    [0x4B] = 0x4B, -- Left
    [0x4D] = 0x4D, -- Right
    [0x48] = 0x48, -- Up
    [0x49] = 0x49, -- PgUp
    [0x51] = 0x51  -- PgDn
}

-- Scancode, ASCII code
local shift_ascii = {
    [0x10] = 0x51, -- Q
    [0x11] = 0x57, -- W
    [0x12] = 0x45, -- E
    [0x13] = 0x52, -- R
    [0x14] = 0x54, -- T
    [0x15] = 0x59, -- Y
    [0x16] = 0x55, -- U
    [0x17] = 0x49, -- I
    [0x18] = 0x4F, -- O
    [0x19] = 0x50, -- P
    [0x1A] = 0x7B, -- {
    [0x1B] = 0x7D, -- }
    [0x1E] = 0x41, -- A
    [0x1F] = 0x53, -- S
    [0x20] = 0x44, -- D
    [0x21] = 0x46, -- F
    [0x22] = 0x47, -- G
    [0x23] = 0x48, -- H
    [0x24] = 0x49, -- J
    [0x25] = 0x4B, -- K
    [0x26] = 0x4C, -- L
    [0x27] = 0x3A, -- :
    [0x28] = 0x22, -- "
    [0x29] = 0x7E, -- ~
    [0x2B] = 0x7C, -- |
    [0x2C] = 0x5A, -- Z
    [0x2D] = 0x58, -- X
    [0x2E] = 0x43, -- C
    [0x2F] = 0x56, -- V
    [0x30] = 0x42, -- B
    [0x31] = 0x4E, -- N
    [0x32] = 0x4D, -- M
    [0x33] = 0x3C, -- <
    [0x34] = 0x3E, -- >
    [0x35] = 0x3F, -- ?
    [0x02] = 0x21, -- !
    [0x03] = 0x40, -- @
    [0x04] = 0x23, -- #
    [0x05] = 0x24, -- $
    [0x06] = 0x25, -- %
    [0x07] = 0x5E, -- ^
    [0x08] = 0x26, -- &
    [0x09] = 0x2A, -- *
    [0x0A] = 0x28, -- (
    [0x0B] = 0x29  -- )
}

-- Scancode, ASCII code
local ascii_table = {
    [0x10] = 0x71, -- q
    [0x11] = 0x77, -- w
    [0x12] = 0x65, -- e
    [0x13] = 0x72, -- r
    [0x14] = 0x74, -- t
    [0x15] = 0x79, -- y
    [0x16] = 0x75, -- u
    [0x17] = 0x69, -- i
    [0x18] = 0x6F, -- o
    [0x19] = 0x70, -- p
    [0x1A] = 0x5B, -- [
    [0x1B] = 0x5D, -- ]
    [0x1E] = 0x61, -- a
    [0x1F] = 0x73, -- s
    [0x20] = 0x64, -- d
    [0x21] = 0x66, -- f
    [0x22] = 0x67, -- g
    [0x23] = 0x68, -- h
    [0x24] = 0x6A, -- j
    [0x25] = 0x6B, -- k
    [0x26] = 0x6C, -- l
    [0x27] = 0x3B, -- ;
    [0x28] = 0x27, -- '
    [0x29] = 0x60, -- `
    [0x2B] = 0x5C, -- \
    [0x2C] = 0x7A, -- z
    [0x2D] = 0x78, -- x
    [0x2E] = 0x63, -- c
    [0x2F] = 0x76, -- v
    [0x30] = 0x62, -- b
    [0x31] = 0x6E, -- n
    [0x32] = 0x6D, -- m
    [0x33] = 0x2C, -- ,
    [0x34] = 0x2E, -- .
    [0x35] = 0x2F, -- /
    [0x02] = 0x31, -- 1
    [0x03] = 0x32, -- 2
    [0x04] = 0x33, -- 3
    [0x05] = 0x34, -- 4
    [0x06] = 0x35, -- 5
    [0x07] = 0x36, -- 6
    [0x08] = 0x37, -- 7
    [0x09] = 0x38, -- 8
    [0x0A] = 0x39, -- 9
    [0x0B] = 0x30, -- 0
    [0x0D] = 0x3D, -- =
    [0x1C] = 0x0D, -- Enter
    [0x01] = 0x1B, -- Escape
    [0x0E] = 0x08, -- Backspace
    [0x39] = 0x20, -- Space
    [0x0F] = 0x09, -- Tab
    [0x0C] = 0x2D, -- -
}

-- Scancode, ASCII
local ctrl_ascii = {
    [0x10] = 0x11, -- q
    [0x11] = 0x17, -- w
    [0x12] = 0x05, -- e
    [0x13] = 0x12, -- r
    [0x14] = 0x14, -- t
    [0x15] = 0x19, -- y
    [0x16] = 0x15, -- u
    [0x17] = 0x09, -- i
    [0x18] = 0x0F, -- o
    [0x19] = 0x10, -- p
    [0x1A] = 0xF0, -- [
    [0x1B] = 0xF0, -- ]
    [0x1E] = 0x01, -- a
    [0x1F] = 0x13, -- s
    [0x20] = 0x04, -- d
    [0x21] = 0x06, -- f
    [0x22] = 0x07, -- g
    [0x23] = 0x08, -- h
    [0x24] = 0x09, -- j
    [0x25] = 0x0B, -- k
    [0x26] = 0x0C, -- l
    [0x2B] = 0x1C, -- \
    [0x2C] = 0x1A, -- z
    [0x2D] = 0x18, -- x
    [0x2E] = 0x03, -- c
    [0x2F] = 0x16, -- v
    [0x30] = 0x02, -- b
    [0x31] = 0x0E, -- n
    [0x32] = 0x0D, -- m
    [0x52] = 0x00  -- Insert
}

-- Graphics
local reg_to_mode = {
    [0] = 0x04, -- 40x25 mono
    [1] = 0x00, -- 40x25 color
    [2] = 0x05, -- 80x25 mono
    [3] = 0x01, -- 80x25 color
    [4] = 0x02, -- 320x200 graphics
    [5] = 0x06, -- 320x200 alt graphics
    [6] = 0x16 -- 640x200 graphics
}

local function get_text_addr(x, y)
	return 0xB8000 + (y * 160) + (x * 2)
end

local function get_cursor_pos(cpu, page)
	if page == nil then
		page = lshift(band(cpu.memory[0x462], 7), 1)
	end

	return cpu.memory[0x450 + page], cpu.memory[0x451 + page]
end

local function set_cursor_pos(self, x, y, page)
    local position = y * 80 + x
    self.cpu:out_port(0x3D4, 0x0F)
    self.cpu:out_port(0x3D5, band(position, 0xFF))
    self.cpu:out_port(0x3D4, 0x0E)
    self.cpu:out_port(0x3D5, band(rshift(position, 8), 0xFF))

    if page == nil then
		page = lshift(band(self.memory[0x462], 7), 1)
	end

	self.memory[0x450 + page] = x
	self.memory[0x451 + page] = y
end

local function scroll_up(cpu, lines, empty_attr, startY, startX, endY, endX)
    -- logger:debug("DaveBIOS: Video: Scroll Up, Lines = %d, StartX = %d, StartY = %d, EndX = %d, EndY = %d", lines, startX, startY, endX, endY)

	if lines == 0 then
		for y = startY, endY, 1 do
            local offset_y = 0xB8000 + (y * 160)
            for x = startX, endX, 1 do
                local offset_x = x * 2
                cpu.memory:w16(offset_y + offset_x, lshift(empty_attr, 8))
            end
		end
	else
		for y = startY + lines, endY, 1 do
            for x = startX, endX, 1 do
                cpu.memory:w16(get_text_addr(x, y - lines), cpu.memory:r16(get_text_addr(x, y)))
            end
		end

		for y = endY - lines + 1, endY do
            for x = startX, endX, 1 do
                cpu.memory:w16(get_text_addr(x, y), lshift(empty_attr, 8))
            end
		end
	end
end

local function scroll_down(cpu, lines, empty_attr, startY, startX, endY, endX)
    -- logger:debug("DaveBIOS: Video: Scroll Down, Lines = %d, StartX = %d, StartY = %d, EndX = %d, EndY = %d", lines, startX, startY, endX, endY)

	if lines == 0 then
		for y = startY, endY, 1 do
            for x = startX, endX, 1 do
                cpu.memory:w16(get_text_addr(x, y), lshift(empty_attr, 8))
            end
		end
	else
		for y = endY - lines, startY, -1 do
            for x = startX, endX, 1 do
                cpu.memory:w16(get_text_addr(x, y + lines), cpu.memory:r16(get_text_addr(x, y)))
            end
		end

		for y = startY, startY + lines - 1, 1 do
            for x = startX, endX, 1 do
                cpu.memory:w16(get_text_addr(x, y), lshift(empty_attr, 8))
            end
		end
	end
end

local function set_mode(self, vmode, clear)
    logger:debug("DaveBIOS: Trying to set video mode: %02X", vmode)
    -- vmode = 3
	if (vmode >= 0) and (vmode <= 6) then
        local mode = reg_to_mode[vmode]
        -- 0x449 - Video mode
        self.cpu.memory[0x449] = vmode

        -- 0x44A - Text width
        if (vmode == 2) or (vmode == 3) then
            self.cpu.memory[0x44A] = 80
        elseif (vmode == 1) or (vmode == 0) then
            self.cpu.memory[0x44A] = 40
        end

        self.cpu.memory[0x44B] = 0
        self.cpu.memory[0x465] = mode
        self.cpu.memory[0x466] = 0

        if clear then
            if (vmode >= 0 and vmode <= 3) then
                for y = 0, 24, 1 do
                    for x = 0, self.cpu.memory[0x44A] - 1, 1 do
                        self.cpu.memory:w16(get_text_addr(x, y), 0x0700)
                    end
                end
            else
                for i = 0, 7999, 1 do
                    self.cpu.memory[0xB8000 + i] = 0
                    self.cpu.memory[0xBA000 + i] = 0
                end
            end
        end

        self.cpu:out_port(0x3D8, mode)
        return true
	else
        return false
    end
end

local function put_char(self, x, y, char, atr)
    local addr = get_text_addr(x, y)
    self.memory[addr] = string.byte(char)
    self.memory[addr + 1] = atr
end

local function vprintf(self, x, y, str, foreground, background, ...)
    local formatted_str = string.format(str, ...)

    for i = 1, #str, 1 do
        put_char(self, x + (i - 1), y, formatted_str:sub(i, i), band(bor(lshift(background, 8), foreground), 0xFFFF))
    end

    set_cursor_pos(self, x + #str, y)
end

-- Keyboard
local function check_key(self)
    local head = self.cpu.memory:r16(0x41A)
    local tail = self.cpu.memory:r16(0x41C)

    if head == tail then
        return -1
    end

    return self.cpu.memory:r16(head)
end

local function get_key(self)
    local head = self.cpu.memory:r16(0x41A)
    local tail = self.cpu.memory:r16(0x41C)

    if head == tail then
        return -1
    end

    local nhead = head + 2
    if nhead >= 0x3E then
        nhead = 0x1E
    end

    self.cpu.memory:w16(0x41A, nhead)
    return self.cpu.memory:r16(0x400 + head)
end

-- Interrupts
local function int_8(self)
    return function(cpu)
        cpu.memory:w32(0x46C, cpu.memory:r32(0x46C) + 1)
        return true
    end
end

local function int_9(self)
    return function(cpu, ax, ah, al)
        local scancode = cpu:in_port(0x60)
        local flags0 = cpu.memory[0x417]

        if scancode == 0x2A then -- Shift pressed
            flags0 = bor(flags0, 2)
        elseif scancode == 0xAA then -- Shift
            flags0 = band(flags0, bnot(2))
        elseif scancode == 0x1D then -- CTRL Pressed
            flags0 = bor(flags0, 0x04)
        elseif scancode == 0x9D then -- CTRL Reliazed
            flags0 = band(flags0, bnot(0x04))
        elseif scancode == 0x38 then -- Alt Reliazed
            flags0 = band(flags0, bnot(0x08))
        elseif scancode == 0xB8 then -- Alt Reliazed
            flags0 = band(flags0, bnot(0x08))
        else
            local ascii = 0
            if (band(flags0, 2) == 2) and shift_ascii[scancode] then
                ascii = shift_ascii[scancode]
            elseif (band(flags0, 0x04) == 0x04) and ctrl_ascii[scancode] then
                ascii = ctrl_ascii[scancode]
            elseif not extended_ascii[scancode] then
                ascii = ascii_table[scancode] or 0
            end

            if band(scancode, 0x80) == 0 then
                local head = self.cpu.memory:r16(0x41A)
                local tail = self.cpu.memory:r16(0x41C)
                local ntail = tail + 2

                if ntail >= 0x3E then
                    ntail = 0x1E
                end

                if ntail ~= head then
                    self.cpu.memory:w16(0x400 + tail, bor(lshift(band(scancode, 0xFF), 8), band(ascii, 0xFF)))
                    self.cpu.memory:w16(0x41C, ntail)
                end
            end
        end

        cpu.memory[0x417] = band(flags0, 0xFF)
        -- logger:debug("DaveBIOS: Interrupt 9h: Scancode = 0x%02X, Pressed = %s, LShift = %s", scancode, band(scancode, 0x80) == 0, band(keys, 2) == 2)
        return true
    end
end

local function int_10(self)
    return function(cpu, _, ah, al)
        local current_mode = self.memory[0x449]
        -- logger:debug("DaveBIOS: Interrupt 10h, AH = %02X", ah)
        if ah == 0x00 then -- Set video mode
            local mode = band(al, 0xFF7F)
            set_mode(self, mode, band(al, 0x80) == 0)
            return true
        elseif ah == 0x01 then -- Set cursor shape, TODO
            return true
        elseif ah == 0x02 then -- Set cursor position
            set_cursor_pos(self, band(cpu.regs[3], 0xFF), rshift(cpu.regs[3], 8), rshift(cpu.regs[4], 8))
            return true
        elseif ah == 0x03 then -- Get cursor position
            local cursor_x, cursor_y = get_cursor_pos(cpu, rshift(cpu.regs[4], 8))
            cpu.regs[3] = bor(lshift(cursor_y, 8), (cursor_x))
            return true
        elseif ah == 0x04 then -- Query light pen
            cpu.regs[1] = rshift(cpu.regs[1], 8)
            return true
        elseif ah == 0x05 then  -- Select video page
            cpu.memory[0x462] = band(al, 0x07)
            return true
        elseif ah == 0x06 then -- Scroll up
            scroll_up(cpu, al, rshift(cpu.regs[4], 8), rshift(cpu.regs[2], 8), band(cpu.regs[2], 0xFF), rshift(cpu.regs[3], 8), band(cpu.regs[3], 0xFF))
            return true
        elseif ah == 0x07 then -- Scroll down
            scroll_down(cpu, al, rshift(cpu.regs[4], 8), rshift(cpu.regs[2], 8), band(cpu.regs[2], 0xFF), rshift(cpu.regs[3], 8), band(cpu.regs[3], 0xFF))
            return true
        elseif ah == 0x08 then -- Read character
            local cursor_x, cursor_y = get_cursor_pos(cpu, rshift(cpu.regs[4], 8))
            local addr = get_text_addr(cursor_x, cursor_y)
            cpu.regs[1] = bor(0x0800, cpu.memory[addr])

            if current_mode < 4 then
                cpu.regs[4] = bor(band(cpu.regs[4], 0xFF), lshift(cpu.memory[addr + 1], 8))
            end

            return true
        elseif ah == 0x09 or ah == 0x0A then  -- Write character/attribute (0x09) or char (0x0A)
            local cursor_x, cursor_y = get_cursor_pos(cpu, rshift(cpu.regs[4], 8))
            local addr = get_text_addr(cursor_x, cursor_y)
            local bl = band(cpu.regs[4], 0xFF)

            if current_mode < 4 then
                for _ = 1, cpu.regs[2], 1 do
                    cpu.memory[addr] = al
                    if ah == 0x09 then
                        cpu.memory[addr + 1] = bl
                    end
                    addr = addr + 2
                end
            end
            return true
        elseif ah == 0x0B then -- Configure videomode
            local palette = 0
            local bh = rshift(cpu.regs[4], 8)
            local bl = band(cpu.regs[4], 0xFF)

            if bh == 0x00 then
            elseif bh == 0x01 then
                palette = bor(band(palette, 0xDF), lshift(band(bl, 0x01), 5))
            end

            cpu.memory[0x466] = palette
            return true
        elseif ah == 0x0C then -- Write Graphics Pixel
            if current_mode > 3 then
                local x = cpu.regs[3]
                local y = cpu.regs[2]
                local color = band(cpu.regs[1], 0xFF)
                if current_mode == 6 then
                    self.memory[(rshift(y, 1) * 80) + (band(y, 1) * 8192) + rshift(x, 3)] = band(color, 1)
                else
                    self.memory[(rshift(y, 1) * 80) + (band(y, 1) * 8192) + rshift(x, 2)] = band(color, 3)
                end
            end
            return true
        elseif ah == 0x0D then -- Read Graphics Pixel
            if current_mode > 3 then
                local x = cpu.regs[3]
                local y = cpu.regs[2]
                local pixel = 0

                if current_mode == 6 then
                    pixel = self.memory[(rshift(y, 1) * 80) + (band(y, 1) * 8192) + rshift(x, 3)]
                else
                    pixel = self.memory[(rshift(y, 1) * 80) + (band(y, 1) * 8192) + rshift(x, 2)]
                end

                cpu.regs[1] = bor(lshift(ah, 8), pixel)
            end
            return true
        elseif ah == 0x0E then -- Write Character in TTY Mode
            if current_mode < 4 then
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

                set_cursor_pos(self, cursor_x, cursor_y)
            end
            return true
        elseif ah == 0x0F then -- Read video mode
            cpu.regs[1] = bor(current_mode, lshift(cpu.memory[0x44A], 8))
            cpu.regs[4] = bor(band(cpu.regs[4], 0xFF), lshift(cpu.memory[0x462], 8))
            return true
        else
            cpu:set_flag(0)
            return false
        end
    end
end

local function int_11(self)
    return function (cpu)
        cpu.regs[1] = cpu.memory:r16(0x410)
        return true
    end
end

local function int_12(self)
    return function (cpu)
        cpu.regs[1] = cpu.memory:r16(0x413)
        return true
    end
end

local function int_14(cpu, ax, ah, al)
    if ah == 0 then -- Initilize port
        local id = cpu.regs[3] -- DX
        local word_lenght = band(al, 0x03)
        local stop_bit = rshift(band(al, 0x04), 2)
        local parity = rshift(band(al, 24), 4)
        local speed = band(rshift(al, 5), 7)
        local port = com_ports[id]

        if port then
            cpu:out_port(port + 1, 0x00) -- Disable all interrupts
            cpu:out_port(port + 3, 0x80) -- Enable DLAB
            local cspeed = com_speed[speed]
            if cspeed then
                cpu:out_port(port, cspeed[1]) -- Set divisor lo byte
                cpu:out_port(port + 1, cspeed[2]) -- Set divisor hi byte
            else -- Set to default speed
                cpu:out_port(port, 96) -- Set divisor lo byte
                cpu:out_port(port + 1, 0) -- Set divisor hi byte
            end
            cpu:out_port(port + 3, 0x03) -- Set bits, parity, stop bit
            cpu:out_port(port + 2, 0xC7) -- Enable FIFO, clear them, with 14-byte threshold
            cpu:out_port(port + 4, 0x0B) -- IRQs enabled, RTS/DSR set
            cpu:out_port(port + 4, 0x0F) -- Set to not-loopback mode with IRQs enabled and OUT#1 and OUT#2 bits enabled

            cpu.regs[1] = band(lshift(cpu:in_port(port + 5), 8), 0xFF00)
            logger:debug("DaveBIOS: Interrupt 14h: Initilize COM Port %d, Word lenght = %d, Stop Bit = %d, Parity = %d, Speed = %d", id, word_lenght, stop_bit, parity, speed)
        else
            cpu.regs[1] = 0
        end
        return true
    elseif ah == 1 then -- Write byte to port
        local id = band(cpu.regs[3], 3)
        local port = com_ports[id]

        if port then
            cpu:out_port(port, al)
            logger:debug("DaveBIOS: Interrupt 14h: Write %d to COM port %d", al, id)
            cpu.regs[1] = band(lshift(cpu:in_port(port + 5), 8), 0xFF00)
        else
            cpu.regs[1] = 0
        end

        return true
    elseif ah == 2 then -- Read byte from port
        local id = cpu.regs[3]
        local port = com_ports[id]

        if port then
            cpu:out_port(port, al)
            logger:debug("DaveBIOS: Interrupt 14h: Reading byte from COM port %d", id)
            cpu.regs[1] = bor(lshift(cpu:in_port(port + 5), 8), cpu:in_port(port))
        else
            cpu.regs[1] = 0
        end

        return true
    elseif ah == 3 then -- Get port status
        local id = cpu.regs[3]
        local port = com_ports[id]

        if port then
            logger:debug("DaveBIOS: Interrupt 14h: Getting status from COM port %d", id)
            cpu.regs[1] = bor(lshift(cpu:in_port(port + 5), 8), 0)
        else
            cpu.regs[1] = 0
        end

        return true
    elseif ah == 4 then -- Extended Initilize (TODO)
        local port = cpu.regs[3]
        local chetnost = cpu.regs[2]
        local stop_bits = band(lshift(cpu.regs[2], 4), 0xFF)
        local word_lenght = band(lshift(cpu.regs[4], 4), 0xFF)
        local speed = cpu.regs[4]
        logger:debug("DaveBIOS: Interrupt 14h: Extended Initilize port %d: Word lenght = %d, Stop Bit = %d, chetnost = %d, Speed = %d, BREAK status = %s", port, word_lenght, stop_bits, chetnost, speed, al)
        cpu.regs[1] = 0
        return true
    elseif ah == 5 then -- Extended modem control (TODO)
        if al == 0 then -- Read from modem
            logger:debug("DaveBIOS: Interrupt 14h: Modem: Read")
        elseif al == 1 then -- Write too modem
            logger:debug("DaveBIOS: Interrupt 14h: Modem: Write")
        end
        return true
    else
        cpu:set_flag(0)
        return false
    end
end

local function int_15(cpu, ax, ah, al)
    cpu.regs[1] = bor(0x8600, band(cpu.regs[1], 0xFF))
    cpu:set_flag(0)
	return false
end

local function int_16(self)
    return function(cpu, ax, ah, al)
        -- logger:debug("DaveBIOS: interrupt 16h, AH = %02X", ah)
        if ah == 0x00 then -- Read Character
            local key = get_key(self)
            if key > 0 then
                cpu.regs[1] = key
            else
                return -1
            end
            return true
        elseif ah == 0x01 then -- Read Input Status
            local key = check_key(self)
            if key > 0 then
                cpu:clear_flag(6)
                cpu.regs[1] = key
            else
                cpu:set_flag(6)
            end
            return true
        elseif ah == 0x02 then -- Read Keyboard Shift Status
            cpu.regs[1] = bor(lshift(ah, 8), cpu.memory[0x417])
            return true
        elseif ah == 0x05 then -- Send char to keyboard buffer
            local scancode = rshift(cpu.regs[2], 8)
            local ascii = band(cpu.regs[2], 0xFF)
            -- send(self, scancode)
            cpu.regs[1] = lshift(ah, 8)
            return true
        else
            cpu:set_flag(0)
            return false
        end
    end
end

local function int_17(self)
    return function (cpu, _, ah, al)
        if ah == 0 then -- Print Word
            -- logger:debug("DaveBIOS: Interrupt 17h: Print word %02X", al)
            local id = cpu.regs[3]
            local port = lpt_ports[id]

            if port then
                cpu:out_port(port, al)
            end

            cpu.regs[1] = band(cpu.regs[1], 0xFF)
            return true
        elseif ah == 1 then -- Initilize Printer
            local id = cpu.regs[3]
            -- logger:debug("DaveBIOS: Interrupt 17h: Initilize Printer %d", id)
            cpu.regs[1] = band(cpu.regs[1], 0xFF)
            return true
        elseif ah == 2 then -- Printer Status
            local id = cpu.regs[3]
            -- logger:debug("DaveBIOS: Interrupt 17h: Printer %d Status", id)
            cpu.regs[1] = bor(lshift(0x00, 8), band(al, 0xFF))
            return true
        else
            return false
        end
    end
end

local function int_1A(self)
    return function(cpu, ax, ah, al)
        if ah == 0x00 then -- Read Time
            local timer_ticks = cpu.memory:r32(0x46C)
            cpu.regs[1] = bor(band(cpu.regs[1], 0xFF00), 0)
            cpu.regs[2] = band(rshift(timer_ticks, 16), 0xFFFF)
            cpu.regs[3] = band(timer_ticks, 0xFFFF)
            return true
        elseif ah == 0x01 then -- Set Time
            local timer_ticks = bor(cpu.regs[3], lshift(cpu.regs[2], 16))
            cpu.memory:w32(0x46c, timer_ticks)
            return true
        else
            cpu:set_flag(0)
            return false
        end
    end
end

local function int_1C(self)
    return function()
        return true
    end
end

local function start(self)
    -- Interrupt vector table
    for i = 0, 255, 1 do
        if self.cpu.interrupt_handlers[i + 1] then
            self.memory[0xF1100 + i] = 0x90
        else
            self.memory[0xF1100 + i] = 0xCF
        end
    end

    for i = 0, 255, 1 do
        self.memory:w16(i * 4, 0x1100 + i)
        self.memory:w16(i * 4 + 2, 0xF000)
    end

    -- COM Ports
    self.memory:w16(0x400, 0x3F8) -- COM 1
    self.memory:w16(0x402, 0x2F8) -- COM 2
    self.memory:w16(0x404, 0x3E8) -- COM 3
    self.memory:w16(0x406, 0x2E8) -- COM 4

    -- LPT Ports
    self.memory:w16(0x408, 0x378) -- LPT 1
    self.memory:w16(0x40A, 0x278) -- LPT 2
    self.memory:w16(0x40C, 0x3BC) -- LPT 3

    -- Equipment list flags
    local equipment = bor(0x0061, lshift(1, 6))
    self.memory:w16(0x410, equipment)

    self.memory:w16(0x413, 640) -- Memory size
    self.memory[0xFFFFE] = 0xFE -- Model

    -- Keyboard
    self.cpu.memory[0x471] = 0 -- Break key check
    self.cpu.memory[0x496] = 0 -- Keyboard mode/type
    self.cpu.memory[0x497] = 0 -- Keyboard LED flags
    self.cpu.memory[0x417] = 0 -- Keyboard flags 1
    self.cpu.memory[0x418] = 0 -- Keyboard flags 2
    -- Start - 0x41E, End = 0x43E 
    self.cpu.memory:w16(0x41A, 0x1E) -- Head buffer
    self.cpu.memory:w16(0x41C, 0x1E) -- Tail buffer

    -- RTC
    local date = os.date("*t")
    self.cpu.memory:w32(0x46C, math.ceil((date.hour * 3600 + date.min * 60 + date.sec) * 18.2)) -- Current time

    -- PIT
    self.cpu:out_port(0x43, 0x36)
    self.cpu:out_port(0x40, 0x00)
    self.cpu:out_port(0x40, 0x00)
    self.cpu:out_port(0x43, 0x54)
    self.cpu:out_port(0x43, 0x12)

    -- BEEP
    self.cpu:out_port(0x61, 0x03)
    self.cpu:out_port(0x61, 0xFC)

    -- PIC
    self.cpu:out_port(0x20, 0x13)
    self.cpu:out_port(0x21, 0x08)
    self.cpu:out_port(0x21, 0x09)

    set_mode(self, 3, true)
    vprintf(self, 0, 0, "DaveBIOS v2", 0x07, 0x00)
    vprintf(self, 0, 1, "(C) Dave", 0x07, 0x00)
    vprintf(self, 0, 3, "RAM [ 640KB ]", 0x03, 0x00)
    vprintf(self, 0, 4, "CPU [ i8086 ]", 0x03, 0x00)
    vprintf(self, 0, 5, "LPT [ 0x378, 0x278, 0x3BC ]", 0x03, 0x00)
    vprintf(self, 0, 6, "Serial [ 0x3F8, 0x2F8, 0x3E8, 0x2E8 ]", 0x03, 0x00)
    vprintf(self, 0, 7, "Video [ CGA ]", 0x03, 0x00)
    vprintf(self, 0, 9, "Booting OS...", 0x02, 0x00)
    set_cursor_pos(self, 0, 11)
end

local bios = {}

function bios.new(cpu, memory)
    local self = {
        cpu = cpu,
        memory = memory,
        start = start
    }

    self.cpu:register_interrupt_handler(0x08, int_8(self))
    self.cpu:register_interrupt_handler(0x9, int_9(self))
    self.cpu:register_interrupt_handler(0x10, int_10(self))
    self.cpu:register_interrupt_handler(0x11, int_11(self))
    self.cpu:register_interrupt_handler(0x12, int_12(self))
    self.cpu:register_interrupt_handler(0x14, int_14)
    self.cpu:register_interrupt_handler(0x15, int_15)
    self.cpu:register_interrupt_handler(0x16, int_16(self))
    self.cpu:register_interrupt_handler(0x17, int_17(self))
    self.cpu:register_interrupt_handler(0x1C, int_1C(self))
    self.cpu:register_interrupt_handler(0x1A, int_1A(self))

    return self
end

return bios