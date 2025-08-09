-- =====================================================================================================================================================================
-- Okean 240 Keyboard emulation.
-- =====================================================================================================================================================================

local common = require("retro_computers:emulator/hardware/keyboard/common")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local keyboard = {}

local KEYBOARD_IRQ = 1
local key_codes = {
    [0x01] = 0x1B, -- Escape
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
    [0x0C] = 0x2D, -- -
    [0x0D] = 0x3D, -- =
    [0x0E] = 0x08, -- Backspace
    [0x0F] = 0x09, -- Tab
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
    [0x1A] = 0x5B, -- [
    [0x1B] = 0x5D, -- ]
    [0x1C] = 0x0D, -- Enter
    [0x1E] = 0x41, -- A
    [0x1F] = 0x53, -- S
    [0x20] = 0x44, -- D
    [0x21] = 0x46, -- F
    [0x22] = 0x47, -- G
    [0x23] = 0x48, -- H
    [0x24] = 0x4A, -- J
    [0x25] = 0x4B, -- K
    [0x26] = 0x4C, -- L
    [0x27] = 0x3B, -- ;
    [0x28] = 0x27, -- '
    [0x29] = 0x60, -- `
    [0x2B] = 0x5C, -- \
    [0x2C] = 0x5A, -- Z
    [0x2D] = 0x58, -- X
    [0x2E] = 0x43, -- C
    [0x2F] = 0x56, -- V
    [0x30] = 0x42, -- B
    [0x31] = 0x4E, -- N
    [0x32] = 0x4D, -- M
    [0x33] = 0x2C, -- ,
    [0x34] = 0x2E, -- .
    [0x35] = 0x2F, -- /
    [0x37] = 0x2A, -- *
    [0x39] = 0x20, -- Space
    [0x4A] = 0x2D  -- -
}

local function send(self, scancode)
    local code = key_codes[scancode]

    if code then
        self.key_queue[self.key_queue_end] = code
        self.key_queue_end = band(self.key_queue_end + 1, 0x0F)
    end
end

local function port_a_in(self)
    return function(cpu, port)
        return self.port_a
    end
end

local function port_b_out(self)
    return function(cpu, port, val)
        if band(val, 0x20) ~= 0 then
            self.pic:clear_interrupt(KEYBOARD_IRQ)
        end
    end
end

local function port_c_out(self)
    return function(cpu, port, val)
        if band(val, 0x80) ~= 0 then
            self.port_a = 0
            self.enabled = true
            self.pic:clear_interrupt(KEYBOARD_IRQ)
        end
    end
end

local function update(self)
    if (self.key_queue_start ~= self.key_queue_end) and self.enabled then
        self.port_a = self.key_queue[self.key_queue_start]
        self.key_queue_start = band(self.key_queue_start + 1, 0x0F)
        self.enabled = false
        self.pic:request_interrupt(KEYBOARD_IRQ)
    end
end

local function reset(self)
    self.port_a = 0
    self.port_b = 0
    self.port_c = 0
    self.key_queue_start = 0
    self.key_queue_end = 0
    self.target_time = 0
end

function keyboard.new(cpu, pic, machine)
    local self = {
        pic = pic,
        key_matrix = {},
        key_queue = {[0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        port_a = 0,
        port_b = 0,
        port_c = 0,
        key_queue_start = 0,
        key_queue_end = 0,
        target_time = 0,
        update = update,
        send_key = send,
        reset = reset
    }

    local cpu_io = cpu:get_io()

    cpu_io:set_port_in(0x40, port_a_in(self))
    cpu_io:set_port_out(0x41, port_b_out(self))
    cpu_io:set_port_out(0x42, port_c_out(self))

    events.on("retro_computers:input_manager.key_down",  function(key, code)
        if common.ignore_keys[key] or (not machine.is_focused) then
            return
        end

        print(machine.is_focused, machine.enabled, machine.id)

        if self.key_matrix[code] then
            if time.uptime() > self.target_time then
                send(self, code)
            end
        else
            send(self, code)
            self.key_matrix[code] = true
            self.target_time = time.uptime() + 0.5
        end
    end)

    events.on("retro_computers:input_manager.key_up", function(key, code)
        if common.ignore_keys[key] then
            return
        end

        audio.play_sound_2d("computer/keyboard", 1.0, 1.0)
        self.key_matrix[code] = false
    end)

    return self
end

return keyboard
