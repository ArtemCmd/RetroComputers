-- local logger = require("retro_computers:logger")
local input_manager = require("retro_computers:emulator/input_manager")

local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor
local is_pressed = input.is_pressed
local charqueue = {}
local buffer = {}
local status = 0x10
local speaker_enebled = false
local control_reg = 0x03
local status_reg = 0

local function send(self, char, code)
    charqueue[#charqueue+1] = {code, char}
    self.cpu:emit_interrupt(9, false)
end

local function get_keys_status(self, ks)
	local keys = 0
	for i, k in ipairs(ks) do
        if is_pressed("key:" .. k) and self.machine.is_focused then
			keys = bor(keys, lshift(1, (i - 1)))
		end
	end
	return keys
end

local function update(self)
    if #buffer > 0 then
        local key =  table.remove(buffer, 1)
        send(self, key[1], key[2])
    end
	self.cpu.memory[0x417] = get_keys_status(self, {"left-shift", "nil", "nil", "nil", "nil", "nil", "caps-lock", "nil"}) -- Shift, Ctrl, Alt, ScrollLock, NumLock, CapsLock, Insert
	-- self.cpu.memory[0x418] = get_keys_status(self, {"nil", "nil", "nil", "nil", "nil", "nil", "nil", "nil"}) -- lShift + Ctrl, lShift + Alt, Sysreq, Pause, ScrollLock, NumLock, CapsLock, Insert
end

-- Keyboard ports
local function port_60(cpu, port, val)
	if not val then
        if #charqueue > 0 then
			local key = table.remove(charqueue, 1)
			return key[1]
		end
        return 0xFF
	end
end

local function port_61(cpu, port, val)
	if val then
		control_reg = val
        speaker_enebled = (band(val, 3) == 3)
        if speaker_enebled then
            audio.play_sound_2d("computer/beep", 1.0, 1.0)
        end
	else
        return control_reg
	end
end

local function port_64(cpu, port,val)
	if val then
		status_reg = 1
	else
        local ret = bor(status, lshift(status_reg, 3))
		if #charqueue > 0 then
			status = bxor(status, 3)
		else
			status = band(status, 0xFC)
		end
		return ret
	end
end

-- Keybooard interrupts
local function int_9(cpu, ax,ah,al)
    return true
end

local function int_16(cpu, ax,ah,al)
	if ah == 0x00 then -- Read Character
        if #charqueue > 0 then
            local char =  table.remove(charqueue, 1)
            local scancode, ascii = char[1], char[2]

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
        if #charqueue > 0 then
            local ascii, scancode = charqueue[1][2], charqueue[1][1]
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
        local cx = cpu.regs[2]
		local scancode = band(rshift(cx, 8), 0xFF)
        local ascii =  band(cx, 0xFF)
        buffer[#buffer+1] = {ascii, scancode}
		return true
    elseif ah == 0x05 then -- Send char to keyboard buffer
		al = cpu.memory[0x417]
		cpu.regs[1] = bor(lshift(ah, 8), al)
		return true
    else
		cpu:set_flag(0)
        return false
	end
end

local function send_key(self, key)
    local keycode = input_manager.get_keycode(key) or {0, 57}
    buffer[#buffer+1] = keycode
end

local keyboard = {}

function keyboard.new(machine)
    local self = {
        machine = machine,
        cpu = machine.cpu,
        update = update,
        send_key = send_key
    }

    local timer = 0
    local key_matrix = {}
    self.cpu.memory[0x471] = 0 -- Break key check
    self.cpu.memory[0x496] = 0 -- Keyboard mode/type
    self.cpu.memory[0x497] = 0 -- Keyboard LED flags
    self.cpu.memory[0x417] = 0 -- Keyboard flags 1
    self.cpu.memory[0x418] = 0 -- Keyboard flags 2
    self.cpu:port_set(0x60, port_60)
    self.cpu:port_set(0x61, port_61)
    self.cpu:port_set(0x64, port_64)
    self.cpu:register_interrupt_handler(0x9, int_9)
    self.cpu:register_interrupt_handler(0x16, int_16)

    events.on("im_key_down",  function(char, ascii, code)
        if machine.is_focused then
            if key_matrix[code] == true then
                if timer > 2 then
                    send(self, ascii, code)
                    timer = 0
                else
                    timer = timer + 1
                end
            else
                send(self, ascii, code)
                key_matrix[code] = true
            end
            -- logger:debug("Keyboard XT: Key %d pressed", code)
        end
    end)

    events.on("im_key_up", function(char, ascii, code)
        if machine.is_focused then
            send(self, ascii,  bor(0x80, code))
            key_matrix[code] = false
            timer = 0
            -- logger:debug("Keyboard XT: Key %d realesed", code)
        end
    end)

    return self
end

return keyboard