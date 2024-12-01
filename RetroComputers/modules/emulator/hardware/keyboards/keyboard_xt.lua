-- local logger = require("retro_computers:logger")
local input_manager = require("retro_computers:emulator/input_manager")

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot
local is_pressed = input.is_pressed

local function send(self, char, code)
    -- logger:debug("Keybooard XT: Key = %s, Scancode = %02X, ASCII = %02X, lShift=%s, Key Queue End = %d", string.char(char),code, char, self.lshift, self.key_queue_end)
    if code == 0x2A or code == 0xAA then
        self.char_queue[#self.char_queue+1] = {0, code}
        if code == 0x2A then
            self.lshift = true
        else
            self.lshift = false
        end
    else
        if self.lshift and (char >= 0x61) and (char <= 0x7A) then
            self.char_queue[#self.char_queue+1] = {char - 32, code}
        else
            self.char_queue[#self.char_queue+1] = {char, code}
        end
    end

    self.key_queue[self.key_queue_end][1] = char
    self.key_queue[self.key_queue_end][2] = code
    self.key_queue_end = band(self.key_queue_end + 1, 0x0F)
end

local function get_keys_status(self, ks)
	local keys = 0
	for i = 1, #ks, 1 do
        if is_pressed("key:" .. ks[i]) and self.machine.is_focused then
			keys = bor(keys, lshift(1, (i - 1)))
		end
	end
	return keys
end

local function update(self)
    self.cpu.memory[0x417] = get_keys_status(self, {"left-shift", "nil", "nil", "nil", "nil", "nil", "caps-lock", "nil"}) -- Shift, Ctrl, Alt, ScrollLock, NumLock, CapsLock, Insert
	-- self.cpu.memory[0x418] = get_keys_status(self, {"nil", "nil", "nil", "nil", "nil", "nil", "nil", "nil"}) -- lShift + Ctrl, lShift + Alt, Sysreq, Pause, ScrollLock, NumLock, CapsLock, Insert
    if (#self.buffer > 0) then
        local key =  table.remove(self.buffer, 1)
        send(self, key[1], key[2])
    end
    if (self.key_queue_start ~= self.key_queue_end) then
        self.data_reg = self.key_queue[self.key_queue_start][2]
        self.key_queue_start = band(self.key_queue_start + 1, 0x0F)
        self.cpu:emit_interrupt(9, false)
    end
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
                audio.play_sound_2d("computer/beep", 1.0, 1.0)
            end
        else
            return self.control_reg
        end
    end
end

local function port_64(self)
    return function(cpu, port,val)
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
    return function(cpu, ax,ah,al)
        return true
    end
end

local function int_16(self)
    return function(cpu, ax,ah,al)
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
                cpu:set_flag(6)
                return true
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
            if ah == 0x12 then
                ah = cpu.memory[0x418]
            end
            al = cpu.memory[0x417]
            cpu.regs[1] = bor(lshift(ah, 8), al)
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
        if self.lshift and keycode[2] >= 0x61 and keycode[2] <= 0x7A then
            self.buffer[#self.buffer+1] = {keycode[1] - 32, keycode[2]}
        else
            self.buffer[#self.buffer+1] = {keycode[1], keycode[2]}
        end
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
        self.key_queue[i][1] = 0
        self.key_queue[i][2] = 0
    end

    for i = 1, #self.char_queue, 1 do
        self.char_queue[i] = nil
    end

    for i = 1, #self.buffer, 1 do
        self.buffer[i] = nil
    end

    self.speaker_enebled = false
    self.lshift = false
end

function keyboard.new(machine)
    local self = {
        machine = machine,
        cpu = machine.components.cpu,
        update = update,
        send_key = send_key,
        reset = reset,
        lshift = false,
        key_queue = {[0] = {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}},
        key_queue_start = 0,
        key_queue_end = 0,
        control_reg = 3,
        data_reg = 0,
        configuration_reg = 0x6C,
        status_reg = 0,
        status = 0x10,
        speaker_enebled = false,
        char_queue = {},
        buffer = {},
    }

    local timer = 0
    local lastkey = 0
    local key_matrix = {}
    self.cpu.memory[0x471] = 0 -- Break key check
    self.cpu.memory[0x496] = 0 -- Keyboard mode/type
    self.cpu.memory[0x497] = 0 -- Keyboard LED flags
    self.cpu.memory[0x417] = 0 -- Keyboard flags 1
    self.cpu.memory[0x418] = 0 -- Keyboard flags 2
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
                    send(self, ascii, code)
                else
                    timer = timer + 1
                end
            else
                send(self, ascii, code)
                key_matrix[code] = true
            end
            lastkey = code
        end
    end)

    events.on("retro_computers:input_manager.key_up", function(char, ascii, code)
        if machine.is_focused then
            -- logger:debug("Keyboard XT: Key %d realesed", code)
            send(self, ascii,  bor(0x80, code))
            key_matrix[code] = false
            timer = 0
        end
    end)

    return self
end

return keyboard