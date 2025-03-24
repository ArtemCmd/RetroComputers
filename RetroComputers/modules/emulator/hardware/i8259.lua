-- PIC
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

local logger = require("retro_computers:logger")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local function get_interrupt_ir(self)
    local result = -1

    for i = 0, 7, 1 do
        local ir = band(i + self.priority, 0x07)
        local mask = lshift(1, ir)

        if band(self.isr, mask) ~= 0 then
            break
        elseif (self.icw_index == 0) and (band(band(self.irr, bnot(self.imr)), mask) ~= 0) then
            result = ir
            break
        end
    end

    if result == -1 then
        self.interrupt = 0x17
    else
        self.interrupt = result
    end

    return result
end

local function get_interrupt_is(self)
    for i = 0, 7, 1 do
        local ir = band(i + self.priority, 7)
        local mask = lshift(1, ir)

        if (band(self.isr, mask) ~= 0) and ((not self.special_mode) or (band(self.imr, mask) == 0)) then
            return ir
        end
    end

    return 0xFF
end

local function update_pending(self)
    if band(self.interrupt, 0x20) == 0 then
        self.int_pending = get_interrupt_ir(self) ~= -1
    end
end

local function ack(self)
    local interrupt = band(self.interrupt, 0x07)
    local mask = lshift(1, interrupt)

    self.isr = bor(self.isr, mask)
    self.irr = band(self.irr, bnot(mask))
end

local function action(self, irq, eoi, rotate)
    if irq ~= 0xFF then
        local b = lshift(1, irq)

        if eoi then
            self.isr = band(self.isr, bnot(b))
        end

        if rotate then
            self.priority = band(irq + 1, 7)
        end

        update_pending(self)
    end
end

local function eoi(self)
    if band(self.icw4, 2) ~= 0 then
        local irq = get_interrupt_is(self)
        action(self, irq, true, self.auto_rotate)
    end
end

local function irq_read(self, phase)
    local interrupt = band(self.interrupt, 0x07)
    local i86_mode = band(self.icw4, 0x01) ~= 0
    local ret = 0x00

    if phase == 0 then
        self.interrupt = bor(self.interrupt, 0x20)

        ack(self)

        if i86_mode then
            ret = 0xFF
        else
            ret = 0xCD
        end
    elseif i86_mode then
        self.int_pending = false
        ret = interrupt + band(self.icw2, 0xF8)
        eoi(self)
    elseif phase == 1 then
        if band(self.icw1, 0x04) ~= 0 then
            ret = lshift(interrupt, 2) + band(self.icw1, 0xE0)
        else
            ret = lshift(interrupt, 3) + band(self.icw1, 0xC0)
        end
    elseif phase == 2 then
        self.int_pending = false
        ret = self.icw2
        eoi(self)
    end

    return ret
end

local function port_20(self)
    return function(cpu, port, val)
        if val then
            if band(val, 0x10) == 0x10 then
                self.icw1 = val
                self.icw2 = 0
                self.icw3 = 0

                if band(self.icw1, 0x01) == 0 then
                    self.icw4 = 0x00
                end

                self.ocw2 = 0
                self.ocw3 = 0
                self.iir = 0
                self.imr = 0
                self.isr = 0
                self.icw_index = 2
                self.ack_bytes = 0
                self.priority = 0
                self.int_pending = false
                self.interrupt = 0x17
                self.auto_rotate = false
                self.special_mode = false

                update_pending(self)

                -- logger.debug("PIC: ICW 4 = %s, Cascading = %s, CALL Address Interval = %s, Edge Triggered Mode = %s, Initialization Bit = %s", band(val, 0x01) == 0x01, band(val, 0x02) == 0x02, band(val, 0x04) == 0x04, band(val, 0x08) == 0x08, band(val, 0x10) == 0x10)
            elseif band(val, 0x08) == 0x08 then
                self.ocw3 = val

                if band(self.ocw3, 0x04) ~= 0 then
                    self.interrupt = bor(self.interrupt, 0x20)
                end

                if band(self.ocw3, 0x40) ~= 0 then
                    self.special_mode = band(self.ocw3, 0x20) ~= 0
                end
            else
                self.ocw2 = val

                if band(self.ocw2, 0x60) ~= 0 then
                    local irq = 0xFF

                    if band(self.ocw2, 0x07) ~= 0 then
                        irq = band(self.ocw2, 0x07)
                    else
                        irq = get_interrupt_is(self)
                    end

                    action(self, irq, band(self.ocw2, 0x20) ~= 0, band(self.ocw2, 0x80) ~= 0)
                else
                    self.auto_rotate = band(self.ocw2, 0x80) ~= 0
                end
            end
        else
            if band(self.ocw3, 0x03) == 0x03 then
                return self.isr
            else
                return self.iir
            end
        end
    end
end

local function port_21(self)
    return function(cpu, port, val)
        if val then
            if self.icw_index == 0 then
                self.imr = val
            elseif self.icw_index == 2 then
                self.icw2 = val

                if band(self.icw1, 0x01) == 0x01 then
                    self.icw_index = 4
                else
                    self.icw_index = 0
                end

                -- logger.debug("PIC: Base IRQ Address = %02X", val)
            elseif self.icw_index == 3 then
                self.icw3 = val

                if band(self.icw1, 0x01) == 0x01 then
                    self.icw_index = 4
                else
                    self.icw_index = 0
                end

                -- logger.debug("PIC: Communicating IRQ Lines = %02X", val)
            elseif self.icw_index == 4 then
                self.icw4 = val
                self.icw_index = 0

                -- logger.debug("PIC: 80x86 = %s, Auto EOI = %s, Master Buffer = %s, SFNM = %s", band(val, 0x01) == 0x01, band(val, 0x02) == 0x02, band(val, 0x04) == 0x04, band(val, 0x08) == 0x08)
            end
        else
            return self.imr
        end
    end
end

local function irq_ack(self)
    local ret = irq_read(self, self.ack_bytes)

    if band(self.icw4, 0x01) ~= 0 then
        self.ack_bytes = (self.ack_bytes + 1) % 2
    else
        self.ack_bytes = (self.ack_bytes + 1) % 3
    end

    if self.ack_bytes == 0 then
        self.interrupt = 0x17
        update_pending(self)
    end

    return ret
end

local function interrupt(self, num, set)
    for i = 0, 7, 1 do
        local mask = lshift(1, i)
        local raise = band(num, mask)

        if band(self.icw3, mask) ~= 0 then
            if raise ~= 0 then
                num = band(num, bnot(mask))
            end
        end
    end

    if num ~= 0 then
        if set then
            self.irr = bor(self.irr, num)
        else
            self.irr = band(self.irr, bnot(num))
        end

        update_pending(self)
    end
end

local function reset(self)
    self.icw1 = 0
    self.icw2 = 0
    self.icw3 = 0
    self.icw4 = 0
    self.ocw2 = 0
    self.ocw3 = 0
    self.irr = 0
    self.imr = 0
    self.isr = 0
    self.icw_index = 0
    self.priority = 0
    self.ack_bytes = 0
    self.interrupt = 0x17
    self.int_pending = false
    self.special_mode = false
    self.auto_rotate = false
end

local pic = {}

function pic.new(cpu)
    local self = {
        icw1 = 0,
        icw2 = 0,
        icw3 = 0,
        icw4 = 0,
        ocw2 = 0,
        ocw3 = 0,
        irr = 0,
        imr = 0,
        isr = 0,
        icw_index = 0,
        priority = 0,
        ack_bytes = 0,
        interrupt = 0x17,
        int_pending = false,
        special_mode = false,
        auto_rotate = false,
        update = update_pending,
        irq_ack = irq_ack,
        request_interrupt = interrupt,
        reset = reset
    }

    cpu:set_port(0x20, port_20(self)) -- Command
    cpu:set_port(0x21, port_21(self)) -- Data

    return self
end

return pic