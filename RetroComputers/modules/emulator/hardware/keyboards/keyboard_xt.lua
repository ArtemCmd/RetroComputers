-- Keyboard XT (https://frolov-lib.ru/books/bsp/v02/ch2_1.htm)

local logger = require("retro_computers:logger")
local input_manager = require("retro_computers:emulator/input_manager")

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

-- Scancode, Extended ASCII code
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
    [0x4D] = 0x4d, -- Right
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
    [0x24] = 0x69, -- j
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
    [0x1C] = 0x0D, -- Enter
    [0x0E] = 0x08, -- Backspace
    [0x39] = 0x20, -- Space
    [0x0F] = 0x09  -- Tab
}

local function send(self, char, code, pressed)
    -- logger:debug("Keybooard XT: Key = %s, Scancode = %02X, ASCII = %02X, lShift=%s, Key Queue End = %d", string.char(char),code, char, self.lshift, self.key_queue_end)
    self.key_queue[self.key_queue_end] = code
    self.key_queue_end = band(self.key_queue_end + 1, 0x0F)

    -- BIOS
    -- if pressed then -- Emulate BIOS Keyboard buffer
    --     -- self.bios_key_queue_end = band(self.bios_key_queue_end + 2, 31)
    --     -- self.cpu.memory[self.cpu.memory:r16(0x41C)] = code
    --     -- self.cpu.memory[self.cpu.memory:r16(0x41C) + 1] = char
    --     -- self.cpu.memory:w16(0x41C, 0x41E + self.bios_key_queue_end) -- End buffer
    --     -- logger:debug("Keyboard XT: BIOS key buffer, Start = %03X, End = %03X, Scancode = %s", self.cpu.memory:r16(0x41A), self.cpu.memory:r16(0x41C), self.cpu.memory[self.cpu.memory:r16(0x41A)])
    --     -- if self.bios_key_queue_start ~= self.bios_key_queue_end then
    --     --     self.bios_key_queue_start = band(self.bios_key_queue_start + 2, 31)
    --     --     self.cpu.memory:w16(0x41A, 0x41E + self.bios_key_queue_start)
    --     --     logger:debug("Keyboard XT: Interrupt 9h: Buffer Start = %03X, Buffer End = %03X", self.cpu.memory:r16(0x41A), self.cpu.memory:r16(0x41C))
    --     -- end
    -- end

    if code == 0x2A or code == 0xAA then
        if code == 0x2A then
            self.lshift = true
        else
            self.lshift = false
        end
    end

    if self.lshift and shift_ascii[code] then
        self.char_queue[#self.char_queue+1] = {shift_ascii[code], code}
    elseif extended_ascii[code] then
        self.char_queue[#self.char_queue+1] = {0, extended_ascii[code]}
    else
        self.char_queue[#self.char_queue+1] = {ascii_table[code] or 0, code}
    end
end

local function get_keys_status(self, ks)
	local keys = 0
	for i = 1, #ks, 1 do
        if input_manager.is_pressed(ks[i]) and self.machine.is_focused then
			keys = bor(keys, lshift(1, (i - 1)))
		end
	end
	return keys
end

local function update(self)
    if (#self.buffer > 0) then
        local key =  table.remove(self.buffer, 1)
        send(self, key[1], key[2])
    end
    if (self.key_queue_start ~= self.key_queue_end) then
        self.data_reg = self.key_queue[self.key_queue_start]
        self.key_queue_start = band(self.key_queue_start + 1, 0x0F)
        self.cpu:emit_interrupt(9, false)
    end

    -- BIOS
    self.cpu.memory[0x417] = get_keys_status(self, {42}) -- Shift, Ctrl, Alt, ScrollLock, NumLock, CapsLock, Insert
    -- self.cpu.memory[0x418] = get_keys_status(self, {0}) -- lShift + Ctrl, lShift + Alt, Sysreq, Pause, ScrollLock, NumLock, CapsLock, Insert
end

-- Keyboard ports
local function port_60(self)
    return function(cpu, port, val)
        if not val then
            return self.data_reg
        end
    end
end

local function port_61(self)
    return function(cpu, port, val)
        if val then
            self.control_reg = val
            self.speaker_enebled = (band(val, 3) == 3)
            if self.speaker_enebled then
                -- logger:debug("Keyboard XT: Speaker enebled")
                audio.play_sound_2d("computer/beep", 1.0, 1.0)
            end
        else
            return self.control_reg
        end
    end
end

local function port_64(self)
    return function(cpu, port, val)
        if val then
            self.status_reg = 1
        else
            local ret = bor(self.status, lshift(self.status_reg, 3))
            if #self.char_queue > 0 then
                self.status = bxor(self.status, 3)
            else
                self.status = band(self.status, 0xFC)
            end
            return ret
        end
    end
end

-- Keybooard interrupts
local function int_9(self)
    return function(cpu, ax, ah, al)
        return true
    end
end

local function int_16(self)
    return function(cpu, ax, ah, al)
        -- logger:debug("Keyboard XT: interrupt 16h, AH = %02X", ah)
        if ah == 0x00 then -- Read Character
            if #self.char_queue > 0 then
                local char =  table.remove(self.char_queue, 1)
                local scancode, ascii = char[2], char[1]

                if scancode < 0x7F then
                    cpu:clear_flag(6)
                    cpu.regs[1] = bor(lshift(band(scancode, 0xFF), 8), band(ascii, 0xFF))
                else
                    cpu:set_flag(6)
                end
                return true
            else
                self.wait_for_key_press = true
                cpu:set_flag(6)
                return -1
            end
        elseif ah == 0x01 then -- Read Input Status
            if #self.char_queue > 0 then
                local ascii, scancode = self.char_queue[1][1], self.char_queue[1][2]
                if scancode == nil then
                    return true
                else
                    cpu:clear_flag(6)
                    cpu.regs[1] = bor(lshift(band(scancode, 0xFF), 8), band(ascii, 0xFF))
                    return true
                end
            else
                return true
            end
        elseif ah == 0x02 then -- Read Keyboard Shift Status
            cpu.regs[1] = bor(lshift(ah, 8), cpu.memory[0x417])
            return true
        elseif ah == 0x05 then -- Send char to keyboard buffer
            local scancode = rshift(cpu.regs[2], 8)
            local ascii = band(cpu.regs[2], 0xFF)
            send(self, ascii, scancode)
            cpu.regs[1] = lshift(ah, 8)
            return true
        else
            cpu:set_flag(0)
            return false
        end
    end
end

local function send_key(self, keyname)
    local keycode = input_manager.get_keycode(keyname) or {0, 57}
    if keyname == "left-shift" then
        if not self.lshift then
            self.buffer[#self.buffer+1] = {0, keycode[2]}
            self.lshift = true
        else
            self.buffer[#self.buffer+1] = {0, bor(0x80, keycode[2])}
            self.lshift = false
        end
    else
        self.buffer[#self.buffer+1] = {keycode[1], keycode[2]}
        self.buffer[#self.buffer+1] = {keycode[1], bor(0x80, keycode[2])}
    end
end

local keyboard = {}

local function reset(self)
    self.control_reg = 3
    self.data_reg = 0
    self.configuration_reg = 0x6C
    self.status_reg = 0
    self.status = 0x10
    self.key_queue_end = 0
    self.key_queue_start = 0

    for i = 0, #self.key_queue, 1 do
        self.key_queue[i]= 0
    end

    for i = 1, #self.char_queue, 1 do
        self.char_queue[i] = nil
    end

    for i = 1, #self.buffer, 1 do
        self.buffer[i] = nil
    end

    self.speaker_enebled = false
    self.lshift = false

    -- BIOS
    self.cpu.memory[0x471] = 0 -- Break key check
    self.cpu.memory[0x496] = 0 -- Keyboard mode/type
    self.cpu.memory[0x497] = 0 -- Keyboard LED flags
    self.cpu.memory[0x417] = 0 -- Keyboard flags 1
    self.cpu.memory[0x418] = 0 -- Keyboard flags 2
    self.cpu.memory[0x041A] = 0x41E -- Start buffer
    self.cpu.memory[0x041C] = 0x41E -- End buffer
end

function keyboard.new(machine)
    local self = {
        machine = machine,
        cpu = machine.components.cpu,
        update = update,
        send_key = send_key,
        reset = reset,
        lshift = false,
        key_queue = {[0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        key_queue_start = 0,
        key_queue_end = 0,
        control_reg = 3,
        data_reg = 0,
        configuration_reg = 0x6C,
        status_reg = 0,
        status = 0x10,
        speaker_enebled = false,
        buffer = {},
        -- BIOS
        bios_key_queue_start = 0,
        bios_key_queue_end = 0,
        char_queue = {}
    }

    local timer = 0
    local lastkey = 0
    local key_matrix = {}
    self.cpu:port_set(0x60, port_60(self))
    self.cpu:port_set(0x61, port_61(self))
    self.cpu:port_set(0x64, port_64(self))
    self.cpu:register_interrupt_handler(0x9, int_9(self))
    self.cpu:register_interrupt_handler(0x16, int_16(self))

    events.on("retro_computers:input_manager.key_down",  function(char, ascii, code)
        if machine.is_focused then
            -- logger:debug("Keyboard XT: Key %d pressed", code)
            if not (lastkey == code) then
                timer = 0
            end
            if key_matrix[code] == true then
                if timer > 5 then
                    send(self, ascii, code, true)
                else
                    timer = timer + 1
                end
            else
                send(self, ascii, code, true)
                key_matrix[code] = true
            end
            lastkey = code
        end
    end)

    events.on("retro_computers:input_manager.key_up", function(char, ascii, code)
        if machine.is_focused then
            -- logger:debug("Keyboard XT: Key %d realesed", code)
            self.bios_key_queue_start = self.bios_key_queue_end
            self.cpu.memory:w16(0x41A, 0x41E + self.bios_key_queue_start)
            send(self, ascii,  bor(0x80, code))
            key_matrix[code] = false
            timer = 0
        end
    end)

    return self
end

return keyboard