-- FDC (Floppy Disk Controller)

-- v razrabotke (tam zloshno prosto)
local logger = require 'retro_computers:logger'
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local controller = {}

local function port_3F0(self)
    return function(cpu, port, value)
        if not value then
            return 0xFF
        end
    end
end

local function port_3F1(self)
    return function(cpu, port, value)
        if not value then
            return 0xFF
        end
    end
end

local function port_3F2(self)
    return function(cpu, port, value)
        if value then
            logger:debug("FDC: Write %d to port 3F2", value)
            if (band(value, 8) ~= 8) and (band(self.dor, 8) == 8) then
                cpu:emit_interrupt(0x0E, false)
            end
            self.dor = value
        else
            return self.dor
        end
    end
end

local function port_3F3(self)
    return function(cpu, port, value)
        if not value then
            return 0xFF
        end
    end
end

local function port_3F4(self)
    return function(cpu, port, value)
        if not value then
            return 0xFF
        end
    end
end

local function port_3F5(self)
    return function(cpu, port, value)
        if not value then
            return 0xFF
        end
    end
end

local function port_3F6(self)
    return function(cpu, port, value)
        if not value then
            return 0xFF
        end
    end
end

local function port_3F7(self)
    return function(cpu, port, value)
        if not value then
            return 0xFF
        end
    end
end

function controller.new(cpu)
    local self = {
        handler = {},
        sra = 0, -- Status Register A
        srb = 0, -- Status Register B
        dor = 0, -- Digital Output Register
        tdr = 0, -- Tape Drive Register
        msr = 0, -- Main Status Register
        dsr = 0, -- Datarate Select Register
        df = 0,  -- Data FIFO
        dig = 0, -- Digital Input Register
        ccr = 0, -- Configuration Control Register
        status = 0
    }
    cpu:port_set(0x3F0, port_3F0(self))
    cpu:port_set(0x3F1, port_3F1(self))
    cpu:port_set(0x3F2, port_3F2(self))
    cpu:port_set(0x3F3, port_3F3(self))
    cpu:port_set(0x3F4, port_3F4(self))
    cpu:port_set(0x3F5, port_3F5(self))
    cpu:port_set(0x3F6, port_3F6(self))
    cpu:port_set(0x3F7, port_3F7(self))
    return self
end

return controller