-- =====================================================================================================================================================================
-- Programmable Interrupt Controller (PIC) emulation.
-- =====================================================================================================================================================================

local logger = require("dave_logger:logger")("RetroComputers")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local pic = {}

local STATE_NONE = 0
local STATE_ICW2 = 1
local STATE_ICW3 = 2
local STATE_ICW4 = 3

local ICW1_ICW4	= 0x01
local ICW1_NEED_ICW4 = 0x01
local ICW1_LEVEL_TRIGGERED = 0x08
local ICW4_i86_MODE = 0x01
local OCW_ICW1 = 0x10
local OCW_OCW3 = 0x08
local OCW3_SPECIAL_MASK_MODE = 0x40
local OCW3_POLL_ACTION = 0x04

local function get_interrupt_ir(self)
    local result = -1

    for i = 0, 7, 1 do
        local ir = band(i + self.priority, 0x07)
        local mask = lshift(1, ir)

        if band(self.isr, mask) ~= 0 then
            break
        elseif (self.state == STATE_NONE) and (band(band(self.irr, bnot(self.imr)), mask) ~= 0) then
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
        local ir = band(i + self.priority, 0x07)
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

local function acknowledge(self)
    local interrupt = band(self.interrupt, 0x07)
    local mask = lshift(1, interrupt)

    self.isr = bor(self.isr, mask)

    if band(self.icw1, ICW1_LEVEL_TRIGGERED) == 0 then
       self.irr = band(self.irr, bnot(mask))
    end
end

local function action(self, irq, eoi, rotate)
    if irq ~= 0xFF then
        if eoi then
            self.isr = band(self.isr, bnot(lshift(1, irq)))
        end

        if rotate then
            self.priority = band(irq + 1, 0x07)
        end

        update_pending(self)
    end
end

local function eoi(self) -- End Of Interrupt
    if band(self.icw4, 0x02) ~= 0 then
        local irq = get_interrupt_is(self)
        action(self, irq, true, self.auto_rotate)
    end
end

local function irq_read(self, phase)
    local interrupt = band(self.interrupt, 0x07)
    local i86_mode = band(self.icw4, ICW4_i86_MODE) ~= 0

    if phase == 0 then
        self.interrupt = bor(self.interrupt, 0x20)

        acknowledge(self)

        if i86_mode then
            return 0xFF
        end

        return 0xCD
    elseif i86_mode then
        self.int_pending = false
        eoi(self)
        return interrupt + band(self.icw2, 0xF8)
    elseif phase == 1 then
        if band(self.icw1, 0x04) ~= 0 then
            return lshift(interrupt, 2) + band(self.icw1, 0xE0)
        end

        return lshift(interrupt, 3) + band(self.icw1, 0xC0)
    elseif phase == 2 then
        self.int_pending = false
        eoi(self)
        return self.icw2
    end

    return 0x00
end

local function port_command_out(self)
    return function(cpu, port, val)
        if band(val, OCW_ICW1) ~= 0 then
            self.icw1 = val
            self.icw2 = 0
            self.icw3 = 0

            if band(self.icw1, ICW1_NEED_ICW4) == 0 then
                self.icw4 = 0x00
            end

            self.ocw2 = 0
            self.ocw3 = 0
            self.irr = 0
            self.imr = 0
            self.isr = 0
            self.ack_bytes = 0
            self.priority = 0
            self.interrupt = 0x17
            self.state = STATE_ICW2
            self.auto_rotate = false
            self.special_mode = false
            self.int_pending = false

            update_pending(self)
        elseif band(val, OCW_OCW3) ~= 0 then
            self.ocw3 = val

            if band(self.ocw3, OCW3_POLL_ACTION) ~= 0 then
                self.interrupt = bor(self.interrupt, 0x20)
            end

            if band(self.ocw3, OCW3_SPECIAL_MASK_MODE) ~= 0 then
                self.special_mode = band(self.ocw3, 0x20) ~= 0
            end
        else
            self.ocw2 = val

            if band(self.ocw2, 0x60) ~= 0 then
                local irq

                if band(self.ocw2, 0x40) ~= 0 then
                    irq = band(self.ocw2, 0x07)
                else
                    irq = get_interrupt_is(self)
                end

                action(self, irq, band(self.ocw2, 0x20) ~= 0, band(self.ocw2, 0x80) ~= 0)
            else
                self.auto_rotate = band(self.ocw2, 0x80) ~= 0
            end
        end
    end
end

local function port_command_in(self)
    return function(cpu, port)
        if band(self.ocw3, 0x03) == 0x03 then
            return self.isr
        end

        return self.irr
    end
end

local function port_data_out(self)
    return function(cpu, port, val)
        if self.state == STATE_NONE then
            self.imr = val
            update_pending(self)
        elseif self.state == STATE_ICW2 then
            self.icw2 = val

            if band(self.icw1, ICW1_ICW4) ~= 0 then
                self.state = STATE_ICW4
            else
                self.state = STATE_NONE
            end
        elseif self.state == STATE_ICW4 then
            self.icw4 = val
            self.state = STATE_NONE
        end
    end
end

local function port_data_in(self)
    return function(cpu, port)
        return self.imr
    end
end

local function irq_ack(self)
    local ret = irq_read(self, self.ack_bytes)

    if band(self.icw4, ICW4_i86_MODE) ~= 0 then
        self.ack_bytes = band(self.ack_bytes + 1, 0x01)
    else
        self.ack_bytes = (self.ack_bytes + 1) % 3
    end

    if self.ack_bytes == 0 then
        self.interrupt = 0x17
        update_pending(self)
    end

    return ret
end

local function request_interrupt(self, intr)
    local mask = lshift(1, intr)
    self.irr = bor(self.irr, mask)
    update_pending(self)
end

local function clear_interrupt(self, intr)
    local mask = lshift(1, intr)
    self.irr = band(self.irr, bnot(mask))
    update_pending(self)
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
    self.state = STATE_NONE
    self.priority = 0
    self.ack_bytes = 0
    self.interrupt = 0x17
    self.int_pending = false
    self.special_mode = false
    self.auto_rotate = false
end

function pic.new(cpu, base_port)
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
        state = STATE_NONE,
        priority = 0,
        ack_bytes = 0,
        interrupt = 0x17,
        int_pending = false,
        special_mode = false,
        auto_rotate = false,
        update = update_pending,
        irq_ack = irq_ack,
        request_interrupt = request_interrupt,
        clear_interrupt = clear_interrupt,
        reset = reset
    }

    local cpu_io = cpu:get_io()

    cpu_io:set_port(base_port, port_command_out(self), port_command_in(self))
    cpu_io:set_port(base_port + 1, port_data_out(self), port_data_in(self))

    return self
end

return pic
