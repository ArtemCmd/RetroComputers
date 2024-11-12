-- TODO: Add all ascii codes

local logger = require("retro_computers:logger")
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor
local is_pressed = input.is_pressed

local charqueue = {}
local buffer = {}
local keycodes = {
    ["space"] = {ascii = 32, code = 57},
    ["backspace"] = {ascii = 8, code = 14},
    ["tab"] = {ascii = 9, code = 15},
    ["enter"] = {ascii = 13, code = 28},
    ["esc"] = {ascii = 27, code = 1},
    ["caps-lock"] = {ascii = 20, code = 0x3A},

    ["q"] = {ascii = 113, code = 16},
    ["w"] = {ascii = 119, code = 17},
    ["e"] = {ascii = 101, code = 18},
    ["r"] = {ascii = 114, code = 19},
    ["t"] = {ascii = 116, code = 20},
    ["y"] = {ascii = 121, code = 21},
    ["u"] = {ascii = 117, code = 22},
    ["i"] = {ascii = 105, code = 23},
    ["o"] = {ascii = 111, code = 24},
    ["p"] = {ascii = 112, code = 25},

    ["a"] = {ascii = 97, code = 30},
    ["s"] = {ascii = 115, code = 31},
    ["d"] = {ascii = 100, code = 32},
    ["f"] = {ascii = 102, code = 33},
    ["g"] = {ascii = 103, code = 34},
    ["h"] = {ascii = 104, code = 35},
    ["j"] = {ascii = 106, code = 36},
    ["k"] = {ascii = 107, code = 37},
    ["l"] = {ascii = 108, code = 38},
    [";"] = {ascii = 58, code = 0x27},
    ["\\"] = {ascii = 92, code = 0x2B},

    ["z"] = {ascii = 122, code = 44},
    ["x"] = {ascii = 120, code = 45},
    ["c"] = {ascii = 99, code = 46},
    ["v"] = {ascii = 118, code = 47},
    ["b"] = {ascii = 98, code = 48},
    ["n"] = {ascii = 110, code = 49},
    ["m"] = {ascii = 109, code = 50},
    [","] = {ascii = 188, code = 51},
    ["."] = {ascii = 46, code = 52},
    ["/"] = {ascii = 47, code = 53},

    ["1"] = {ascii = 49, code = 2},
    ["2"] = {ascii = 50, code = 3},
    ["3"] = {ascii = 51, code = 4},
    ["4"] = {ascii = 52, code = 5},
    ["5"] = {ascii = 53, code = 6},
    ["6"] = {ascii = 54, code = 7},
    ["7"] = {ascii = 55, code = 8},
    ["8"] = {ascii = 56, code = 9},
    ["9"] = {ascii = 57, code = 10},
    ["0"] = {ascii = 48, code = 11},
    ["-"] = {ascii = 189, code = 0x0C},

    ["left-shift"] = {ascii = 0x2a, code = 0x2A},
    ["f1"] = {ascii = 189, code = 0x3b},

    ["left"] = {ascii = 75, code = 0x4b},
    ["right"] = {ascii = 77, code = 0x4d},
    ["up"] = {ascii = 72, code = 0x48},
    ["down"] = {ascii = 80, code = 0x50},
    ["["] = {ascii = 0, code = 0x1A},
    ["]"] = {ascii = 0, code = 0x1B},
    ["*"] = {ascii = 0, code = 0x37},

    ["left-ctrl"] = {ascii = 65, code = 0x1D},
    ["left-alt"] = {ascii = 18, code = 0x38},
    ["delete"] = {ascii = 46, code = 83},
    ["kovichky"] = {ascii = 92, code = 0x28},
    ["="] = {ascii = 92, code = 0x0D}
}

local status = 0x10
local speaker_enebled = 0
local port_data = 0x03
local reg = 0

local function send(self, char, code)
    table.insert(charqueue, {code, char})
    self.cpu:emit_interrupt(9, false)
end

local matrix = {}
local function update_keys(self)
    local bufkey = buffer[1]
    for value, key in pairs(keycodes) do
        if (is_pressed("key:" .. value) and self.machine.is_focused) or (bufkey == key.code and key.pressed ~= true) then
            -- logger:debug("Keybooard XT: Key %d pressed=%s", key.code, key.pressed)
            key.pressed = true
            table.remove(buffer, 1)
        else
            key.pressed = false
        end

        if key.pressed and not matrix[key.code] then
            matrix[key.code] = true
            send(self, key.ascii, key.code)
            -- logger:debug("Keyboard XT: Key %d pressed", key.code)
        elseif not key.pressed and matrix[key.code] then
            matrix[key.code] = false
            send(self, key.ascii,  bor(0x80, key.code))
            -- logger:debug("Keyboard XT: Key %d realesed", key.code)
        end
    end
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
    update_keys(self)
	self.cpu.memory[0x417] = get_keys_status(self, {"left-shift", "nil", "nil", "nil", "nil", "nil", "caps-lock", "nil"}) -- Shift, Ctrl, Alt, ScrollLock, NumLock, CapsLock, Insert
	-- self.cpu.memory[0x418] = get_keys_status(self, {"nil", "nil", "nil", "nil", "nil", "nil", "nil", "nil"}) -- lShift + Ctrl, lShift + Alt, Sysreq, Pause, ScrollLock, NumLock, CapsLock, Insert
end

-- Keyboard ports
local function port_60(cpu, port, val)
	if val then

	else
        -- logger:debug("Keyboard XT: Port 60: Reading key.")
        if #charqueue > 0 then
			local v = table.remove(charqueue, 1)
			return v[1]
		end
        return 0xFF
	end
end

local function port_61(cpu, port, val)
	if val then
		port_data = val
        speaker_enebled = band(val, 2)
        if speaker_enebled then
            logger:debug("Keyboard XT: Speaker enebled")
        end
	else
        return port_data
	end
end

local function port_64(cpu, port,val)
	if val then
		reg = 1
	else
        local ret = bor(status, lshift(reg, 3))
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
            local bios, ascii = char[1], char[2]

            if bios < 0x7F then
                cpu:clear_flag(6)
                cpu.regs[1] = bor(lshift(band(bios, 0xFF), 8), band(ascii, 0xFF))
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
            local ascii, bios = charqueue[1][2], charqueue[1][1]
            if bios == nil then
                --cpu_set_flag(6)
                return true
            else
                cpu:clear_flag(6)
                cpu.regs[1] = bor(lshift(band(bios, 0xFF), 8), band(ascii, 0xFF))
                return true
            end
        else
            return true
        end
	elseif ah == 0x02 then -- Read Keyboard Shift Status
		al = cpu.memory[0x417]
		cpu.regs[1] = bor(lshift(ah, 8), al)
		return true
    else
		cpu:set_flag(0)
        return false
	end
end

local function send_key(self, key)
    local code = keycodes[key] or {ascii = 0, code = 57}
    buffer[#buffer + 1] = code.code
end

local keyboard = {}

function keyboard.new(machine)
    local instance = {
        machine = machine,
        cpu = machine.cpu,
        update = update,
        send_key = send_key
    }

    instance.cpu.memory[0x471] = 0 -- Break key check
    instance.cpu.memory[0x496] = 0 -- Keyboard mode/type
    instance.cpu.memory[0x497] = 0 -- Keyboard LED flags
    instance.cpu.memory[0x417] = 0 -- Keyboard flags 1
    instance.cpu.memory[0x418] = 0 -- Keyboard flags 2
    instance.cpu:port_set(0x60, port_60)
    instance.cpu:port_set(0x61, port_61)
    instance.cpu:port_set(0x64, port_64)
    instance.cpu:register_interrupt_handler(0x9, int_9)
    instance.cpu:register_interrupt_handler(0x16, int_16)
    return instance
end

return keyboard