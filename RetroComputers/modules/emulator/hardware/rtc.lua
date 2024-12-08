-- RTC (Real Time Clock)

local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor
local timer_midnight = (24 * 3600) * 18.2
local date = os.date("*t")

-- Interrupts
local function int_8(self)
    return function(cpu, ax,ah,al)
        cpu.memory:w32(0x46C, cpu.memory:r32(0x46C) + 1)
        cpu:emit_interrupt(0x1C, false)
        return true
    end
end

local function int_1C(self)
    return function(cpu, ax,ah,al)
        return true
    end
end

local function int_1A(self)
    return function(cpu, ax,ah,al)
        if ah == 0x00 then -- Read RTC
            local midnight = 0
            local timer_ticks = cpu.memory:r32(0x46C)
            while (timer_ticks - timer_midnight) >= self.timer_last_midnight do
                midnight = 1
                self.timer_last_midnight = self.timer_last_midnight + timer_midnight
            end
            cpu.regs[1] = bor(band(cpu.regs[1], 0xFF00), midnight)
            cpu.regs[2] = band(rshift(timer_ticks, 16), 0xFFFF)
            cpu.regs[3] = band(timer_ticks, 0xFFFF)
            return true
        elseif ah == 0x01 then -- Set RTC
            local timer_ticks = bor(cpu.regs[3], lshift(cpu.regs[2], 16))
            cpu.memory:w32(0x46c, timer_ticks)
            self.timer_last_midnight = 0
            while (timer_ticks - timer_midnight) >= self.timer_last_midnight do
                self.timer_last_midnight = self.timer_last_midnight + timer_midnight
            end
            return true
        elseif ah == 0x02 then -- Read TIme
            cpu.regs[2] = bor(lshift(self.bcdhours, 8), band(self.bcdmins, 0xFF))
            cpu.regs[3] = bor(lshift(self.bcdseconds, 8), band(0, 0xFF))
            return true
        elseif ah == 0x03 then -- Set Time
            self. bcdhours = band(cpu.regs[2], 0xFF)
            self.bcdmins = band(cpu.regs[2], 0x00FF)
            self.bcdseconds = band(cpu.regs[3], 0xFF)
            return true
        elseif ah == 0x04 then -- Read Date
            cpu.regs[2] = bor(lshift(1000, 8), band(self.bcdyears, 0xFF))
            cpu.regs[3] = bor(lshift(self.bcdmonths, 8), band(self.bcddays, 0xFF))
            return true
        else
            cpu:set_flag(0)
            return false
        end
    end
end

local rtc = {}

function rtc.new(cpu)
    local self = {
        bcdhours = tonumber(date.hour) or 0,
        bcdmins = tonumber(date.min) or 0,
        bcdseconds = tonumber(date.sec) or 0,
        bcdyears = tonumber(date.year) or 0,
        bcdmonths = tonumber(date.month) or 0,
        bcddays = tonumber(date.day) or 0,
        timer_last_midnight = 0
    }
    cpu:register_interrupt_handler(0x08, int_8(self))
    cpu:register_interrupt_handler(0x1C, int_1C(self))
    cpu:register_interrupt_handler(0x1A, int_1A(self))

    cpu.memory:w32(0x46C, math.ceil((date.hour * 3600 + date.min * 60 + date.sec) * 18.2))
    return self
end

return rtc