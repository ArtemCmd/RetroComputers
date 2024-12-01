-- 8259 PIC
-- FIXME

-- Standart ISA IRQs:
-- 0 - Timer
-- 1 - Keyboard
-- 2 - Cascade
-- 3 - COM2
-- 4 - COM1
-- 5 - LPT2
-- 6 - Floppy disk
-- 7 - LPT1
-- 8 - RTC
-- 9 - Free
-- 10 - Free
-- 11 - Free
-- 12 - PS2 Mouse
-- 13 - FPU / Coprocessor / Inter-processor
-- 14 - Primary ATA Hard Disk
-- 15 - Secondary ATA Hard Disk

-- local logger = require("retro_computers:logger")
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local icwstep = 0
local icw = {[0] = 0, 0, 0, 0}
local readmode = 0

local imr = 0 -- Interrupt Mask Register
local isr = 0 -- In-Service Register
local irr = 0 -- Interrupt Request Register

local function port_20(cpu, port, val)
    if val then
        if band(val, 0x10) then
            icwstep = 1
            imr = 0
            icw[icwstep] = val
            icwstep = icwstep + 1
        else
            if band(val, 0x98) == 8 then
                readmode = band(val, 2)
            end
            if band(val, 0x20) then
                for i = 0, 7, 1 do
                    if band(rshift(isr, 1), 1) then
                        isr = bxor(isr, lshift(1, i))
                    end
                end
            end
        end
    else
        if readmode then
            return irr
        else
            return isr
        end
    end
end

local function port_21(cpu, port, val)
    if val then
        if icwstep == 3 and band(icw[1], 2) then
            icwstep = 4
        end
        if icwstep < 5 then
            icw[icwstep] = val
            icwstep = icwstep + 1
        else
            imr = val
        end
    else
        return imr
    end
end

local pic = {}

function pic.new(cpu)
    cpu:port_set(0x20, port_20) -- PIC Command
    cpu:port_set(0x21, port_21) -- PIC Data
end

return pic