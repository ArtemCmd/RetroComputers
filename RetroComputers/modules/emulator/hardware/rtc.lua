-- RTC (Real Time Clock)
-- FIXME

local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor
local timer_last_midnight = 0
local timer_midnight = (24 * 3600) * 18.2
local date = os.date("*t")
local bcdhours = tonumber(date.hour) or 0
local bcdmins = tonumber(date.min) or 0
local bcdseconds = tonumber(date.sec) or 0
local bcdyears = tonumber(date.year) or 0
local bcdmonths = tonumber(date.month) or 0
local bcddays = tonumber(date.day) or 0

-- Interrupts
local function int_8(cpu, ax,ah,al)
	cpu.memory:w32(0x46C, cpu.memory:r32(0x46C) + 1)
	cpu:emit_interrupt(0x1C, false)
	return true
end

local function int_1C(cpu, ax,ah,al)
	return true
end

local function int_1A(cpu, ax,ah,al)
	if ah == 0x00 then -- Read RTC
		local midnight = 0
		local timer_ticks = cpu.memory:r32(0x46C)
		while (timer_ticks - timer_midnight) >= timer_last_midnight do
			midnight = 1
			timer_last_midnight = timer_last_midnight + timer_midnight
		end
		cpu.regs[1] = bor(band(cpu.regs[1], 0xFF00), midnight)
		cpu.regs[2] = band(rshift(timer_ticks, 16), 0xFFFF)
		cpu.regs[3] = band(timer_ticks, 0xFFFF)
		return true
	elseif ah == 0x01 then -- Set RTC
		local timer_ticks = bor(cpu.regs[3], lshift(cpu.regs[2], 16))
		cpu.memory:w32(0x46c, timer_ticks)
		timer_last_midnight = 0
		while (timer_ticks - timer_midnight) >= timer_last_midnight do
			timer_last_midnight = timer_last_midnight + timer_midnight
		end
		return true
	elseif ah == 0x02 then -- Read TIme
		cpu.regs[2] = bor(lshift(bcdhours, 8), band(bcdmins, 0xFF))
        cpu.regs[3] = bor(lshift(bcdseconds, 8), band(0, 0xFF))
		return true
    elseif ah == 0x03 then -- Set Time
        bcdhours = band(cpu.regs[2], 0xFF)
        bcdmins = band(cpu.regs[2], 0x00FF)
        bcdseconds = band(cpu.regs[3], 0xFF)
		return true
    elseif ah == 0x04 then -- Read Date
		cpu.regs[2] = bor(lshift(1000, 8), band(bcdyears, 0xFF))
        cpu.regs[3] = bor(lshift(bcdmonths, 8), band(bcddays, 0xFF))
		return true
    else
		cpu:set_flag(0)
        return false
	end
end

local rtc = {}

function rtc.new(cpu)
    cpu:register_interrupt_handler(0x08, int_8)
    cpu:register_interrupt_handler(0x1C, int_1C)
    cpu:register_interrupt_handler(0x1A, int_1A)

    cpu.memory:w32(0x46C, math.ceil((date.hour * 3600 + date.min * 60 + date.sec) * 18.2))
end

return rtc