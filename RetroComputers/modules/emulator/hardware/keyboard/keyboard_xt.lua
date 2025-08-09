-- =====================================================================================================================================================================
-- XT Keyboard emulation.
-- =====================================================================================================================================================================

local video = require("retro_computers:emulator/hardware/video/common")
local common = require("retro_computers:emulator/hardware/keyboard/common")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local keyboard = {}
local KEYBOARD_IRQ = 1

local function send(self, code)
    self.key_queue[self.key_queue_end] = code
    self.key_queue_end = band(self.key_queue_end + 1, 0x0F)
end

local function send_key(self, scancode)
    table.insert(self.buffer, 1, band(scancode, 0xFF))
end

local function update(self)
    if band(self.port_b, 0x40) == 0 then
        return
    end

    if #self.buffer > 0 then
        local key =  table.remove(self.buffer, #self.buffer)
        send(self, key)
    end

    if self.send_interrupt then
        self.send_interrupt = false
        self.enabled = false
        self.port_a = self.current_key
        self.pic:request_interrupt(KEYBOARD_IRQ)
    end

    if (self.key_queue_start ~= self.key_queue_end) and self.enabled then
        self.current_key = self.key_queue[self.key_queue_start]
        self.key_queue_start = band(self.key_queue_start + 1, 0x0F)
        self.send_interrupt = true
    end
end

local function reset(self)
    self.port_a = 0x00
    self.port_b = 0x00
    self.key_queue_end = 0
    self.key_queue_start = 0
    self.current_key = 0x00
    self.clock = false
    self.enabled = true
    self.send_interrupt = false

    for i = 1, #self.buffer, 1 do
        self.buffer[i] = nil
    end
end

-- Ports
local function port_a_in(self)
    return function(cpu, port)
        if band(self.port_b, 0x80) ~= 0 then
            return 0xFF
        end

        return self.port_a
    end
end

local function port_b_out(self)
    return function(cpu, port, val)
        self.port_b = val

        self.speaker:update()
        self.speaker.gated = band(val, 0x01) ~= 0
        self.speaker.enabled = band(val, 0x02) ~= 0
        self.pit:set_channel_gate(2, self.speaker.gated)

        if band(val, 0x80) == 0 then
            local new_clock = band(val, 0x40) ~= 0

            if (not self.clock) and new_clock then
                self.key_queue_start = 0
                self.key_queue_end = 0
                self.enabled = true
                self.send_interrupt = false
                send(self, 0xAA) -- Send Reset Byte
            end

            self.clock = new_clock
        else
            self.port_a = 0
            self.enabled = true
            self.pic:clear_interrupt(KEYBOARD_IRQ)
        end
    end
end

local function port_b_in(self)
    return function(cpu, port)
        return self.port_b
    end
end

local function port_c_in(self)
    return function(cpu, port)
        local ret = self.speaker.ppi_enabled and 0x20 or 0x00

        if band(self.port_b, 0x08) ~= 0 then
            ret = bor(ret, rshift(self.port_d, 4))
        else
            ret = bor(ret, band(self.port_d, 0x0D))
        end

        return ret
    end
end

local function port_d_in(self)
    return function(cpu, port)
        return self.port_d
    end
end

function keyboard.new(cpu, pic, pit, speaker, videocard, fdd_count, base_port, machine)
    local self = {
        pic = pic,
        pit = pit,
        speaker = speaker,
        key_queue = {[0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        key_queue_start = 0,
        key_queue_end = 0,
        key_matrix = {},
        buffer = {},
        port_a = 0x00,
        port_b = 0x00,
        port_d = 0x0C,
        current_key = 0x00,
        clock = false,
        enabled = true,
        send_interrupt = false,
        update = update,
        send_key = send_key,
        reset = reset
    }

    local type = videocard:get_type()
    local cpu_io = cpu:get_io()

    if type == video.TYPE.CGA then
        self.port_d = bor(self.port_d, 0x20)
    elseif type == video.TYPE.MDA then
        self.port_d = bor(self.port_d, 0x30)
    end

    if fdd_count > 0 then
       self.port_d = bor(self.port_d, bor(lshift(fdd_count - 1, 6), 0x01))
    end

    cpu_io:set_port_in(base_port, port_a_in(self))
    cpu_io:set_port_in(base_port + 2, port_c_in(self))
    cpu_io:set_port_in(base_port + 3, port_d_in(self))
    cpu_io:set_port(base_port + 1, port_b_out(self), port_b_in(self))

    events.on("retro_computers:input_manager.key_down",  function(key, code)
        if common.ignore_keys[key] or (not machine.is_focused) then
            return
        end

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
        send(self,  bor(code, 0x80))

        self.key_matrix[code] = false
    end)

    return self
end

return keyboard
