-- Keyboard XT (https://frolov-lib.ru/books/bsp/v02/ch2_1.htm)

local logger = require("retro_computers:logger")

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local function send(self, code)
    -- logger:debug("Keybooard XT: Key = %s, Scancode = %02X, ASCII = %02X, lShift=%s, Key Queue End = %d", string.char(char),code, char, self.lshift, self.key_queue_end)
    self.key_queue[self.key_queue_end] = code
    self.key_queue_end = band(self.key_queue_end + 1, 0x0F)
end

local function update(self)
    if (#self.buffer > 0) then
        local key =  table.remove(self.buffer, 1)
        send(self, key)
    end

    if (self.key_queue_start ~= self.key_queue_end) then
        self.data_reg = self.key_queue[self.key_queue_start]
        self.key_queue_start = band(self.key_queue_start + 1, 0x0F)
        self.cpu:emit_interrupt(9, false)
    end
end

-- Ports
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
            -- logger:debug("Keyboard XT: Write %d to port 0x61", val)
            self.control_reg = val
            self.speaker_enabled = (band(val, 3) == 3)

            if self.speaker_enabled then
                audio.play_sound_2d("computer/beep", 1.0, 1.0)
            end
        else
            return self.control_reg
        end
    end
end

local function port_62(self)
    return function(cpu, port, val)
        if not val then
            return self.switch_reg
        end
    end
end

local function port_63(self)
    return function(cpu, port, val)
        if not val then
            return self.configuration_reg
        end
    end
end

local function port_64(self)
    return function(cpu, port, val)
        if val then
            self.status_reg = 1
        else
            local ret = bor(self.status, lshift(self.status_reg, 3))
            if self.key_queue_start == self.key_queue_end then
                self.status = bxor(self.status, 3)
            else
                self.status = band(self.status, 0xFC)
            end
            return ret
        end
    end
end

local function send_key(self, scancode)
    if (scancode >= 0x00) and (scancode <= 0xFF) then
        self.buffer[#self.buffer+1] = scancode
    end
end

local keyboard = {}

local function reset(self)
    self.control_reg = 0x03
    self.data_reg = 0x00
    self.configuration_reg = 0x6C
    self.status_reg = 0x00
    self.status = 0x10
    self.key_queue_end = 0
    self.key_queue_start = 0
    self.speaker_enabled = false

    for i = 0, #self.key_queue, 1 do
        self.key_queue[i] = 0
    end

    for i = 1, #self.buffer, 1 do
        self.buffer[i] = nil
    end
end

function keyboard.new(machine)
    local self = {
        cpu = machine.components.cpu,
        key_queue = {[0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        key_queue_start = 0,
        key_queue_end = 0,
        control_reg = 0x03,
        data_reg = 0x00,
        configuration_reg = 0x6C,
        switch_reg = 0x00, -- 0x03
        status_reg = 0x00,
        status = 0x10,
        speaker_enabled = false,
        buffer = {},
        update = update,
        send_key = send_key,
        reset = reset,
    }

    local timer = 0
    local lastkey = 0
    local key_matrix = {}

    self.cpu:port_set(0x60, port_60(self))
    self.cpu:port_set(0x61, port_61(self))
    self.cpu:port_set(0x62, port_62(self))
    self.cpu:port_set(0x63, port_63(self))
    self.cpu:port_set(0x64, port_64(self))

    events.on("retro_computers:input_manager.key_down",  function(keyname, code)
        if machine.is_focused then
            -- logger:debug("Keyboard XT: Key %d pressed", code)
            if not (lastkey == code) then
                timer = 0
            end
            if key_matrix[code] == true then
                if timer > 5 then
                    send(self, code)
                else
                    timer = timer + 1
                end
            else
                send(self, code)
                key_matrix[code] = true
            end

            lastkey = code
        end
    end)

    events.on("retro_computers:input_manager.key_up", function(keyname, code)
        if machine.is_focused then
            -- logger:debug("Keyboard XT: Key %d realesed", code)
            audio.play_sound_2d("computer/keyboard", 1.0, 1.0)
            send(self,  bor(code, 0x80))
            key_matrix[code] = false
            timer = 0
        end
    end)

    return self
end

return keyboard