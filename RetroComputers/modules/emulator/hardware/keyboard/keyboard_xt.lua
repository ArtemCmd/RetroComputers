local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local function send(self, code)
    self.key_queue[self.key_queue_end] = code
    self.key_queue_end = band(self.key_queue_end + 1, 0x0F)
end

local function update(self)
    if (#self.buffer > 0) then
        local key =  table.remove(self.buffer, #self.buffer)
        send(self, key)
    end

    if (self.key_queue_start ~= self.key_queue_end) and self.enabled then
        self.port_a = self.key_queue[self.key_queue_start]
        self.key_queue_start = band(self.key_queue_start + 1, 0x0F)
        self.enabled = false
        self.pic:request_interrupt(2, true)
    end
end

local function send_key(self, scancode)
    if (scancode >= 0x00) and (scancode <= 0xFF) then
        table.insert(self.buffer, 1, scancode)
    end
end

local function reset(self)
    self.port_a = 0x00
    self.port_b = 0x00
    self.key_queue_end = 0
    self.key_queue_start = 0
    self.speaker_enabled = false
    self.clock = false
    self.enabled = false

    for i = 0, #self.key_queue, 1 do
        self.key_queue[i] = 0
    end

    for i = 1, #self.buffer, 1 do
        self.buffer[i] = nil
    end
end

-- Ports
local function port_60(self)
    return function(cpu, port, val)
        if not val then
            return self.port_a
        end
    end
end

local function port_61(self)
    return function(cpu, port, val)
        if val then
            self.port_b = val
            self.speaker.enabled = band(val, 0x03) == 0x03
            self.speaker:update()
            self.pit:set_channel_gate(2, band(val, 0x01) == 0x01)

            if band(val, 0x80) == 0 then
                if not self.clock and (band(val, 0x40) ~= 0) then
                    self.key_queue_start = 0
                    self.key_queue_end = 0
                    self.enabled = true
                    send(self, 0xAA)
                end

                self.clock = band(val, 0x40) ~= 0
            else
                self.port_a = 0
                self.enabled = true
                self.pic:request_interrupt(2, false)
            end
        else
            return self.port_b
        end
    end
end

local function port_62(self)
    return function(cpu, port, val)
        if not val then
            local ret = self.speaker.ppi_enabled and 0x20 or 0x00

            if band(self.port_b, 0x08) ~= 0 then
                ret = bor(ret, rshift(self.port_d, 4))
            else
                ret = bor(ret, band(self.port_d, 0x0D))
            end

            return ret
        end
    end
end

local function port_63(self)
    return function(cpu, port, val)
        if not val then
            return self.port_d
        end
    end
end

local keyboard = {}

function keyboard.new(machine, cpu, pic, pit, speaker, videocard, fdd_count)
    local self = {
        pic = pic,
        pit = pit,
        speaker = speaker,
        key_queue = {[0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        key_queue_start = 0,
        key_queue_end = 0,
        buffer = {},
        port_a = 0x00,
        port_b = 0x00,
        port_d = 0x00,
        clock = false,
        speaker_enabled = false,
        enabled = false,
        update = update,
        send_key = send_key,
        reset = reset,
    }

    self.port_d = bor(lshift(fdd_count - 1, 6), 0x1)

    local type = videocard:get_type()

    if type == 1 then
        self.port_d = bor(self.port_d, 0x20)
    elseif type == 2 then
        self.port_d = bor(self.port_d, 0x30)
    end

    local ticks = 0
    local last_key = 0
    local key_matrix = {}

    cpu:set_port(0x60, port_60(self))
    cpu:set_port(0x61, port_61(self))
    cpu:set_port(0x62, port_62(self))
    cpu:set_port(0x63, port_63(self))

    events.on("retro_computers:input_manager.key_down",  function(keyname, code)
        if machine.is_focused then
            if not (last_key == code) then
                ticks = 0
            end

            if key_matrix[code] == true then
                if ticks > 5 then
                    send(self, code)
                else
                    ticks = ticks + 1
                end
            else
                send(self, code)
                key_matrix[code] = true
            end

            last_key = code
        end
    end)

    events.on("retro_computers:input_manager.key_up", function(keyname, code)
        if machine.is_focused then
            audio.play_sound_2d("computer/keyboard", 1.0, 1.0)
            send(self,  bor(code, 0x80))
            key_matrix[code] = false
            ticks = 0
        end
    end)

    return self
end

return keyboard