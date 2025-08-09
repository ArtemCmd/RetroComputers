-- =====================================================================================================================================================================
-- Microsoft Bus Mouse emulation.
-- =====================================================================================================================================================================

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local mouse = {}

local function port_data_in(self)
    return function(cpu, port)
        local ret
        local reg = band(self.control_reg, 0x60)

        if reg == 0 then -- X Low
            ret = band(self.mouse_x, 0x0F)
            self.mouse_x = band(self.mouse_x, bnot(0x0F))
        elseif reg == 0x20 then -- X High
            ret = rshift(self.mouse_x, 4)
            self.mouse_x = band(self.mouse_x, bnot(0xF0))
        elseif reg == 0x40 then -- Y Low
            ret = band(self.mouse_y, 0x0F)
            self.mouse_y = band(self.mouse_y, bnot(0x0F))
        elseif reg == 0x60 then -- Y High
            ret = rshift(self.mouse_y, 4)
            self.mouse_y = band(self.mouse_y, bnot(0xF0))
        else
            ret = 0xFF
        end

        return bor(ret, lshift(bxor(self.buttons, 0x07), 5))
    end
end

local function port_signature_out(self)
    return function(cpu, port, val)
        self.sig_reg = val
    end
end

local function port_signature_in(self)
    return function(cpu, port)
        return self.sig_reg
    end
end

local function port_control_out(self)
    return function(cpu, port, val)
        self.control_reg = bor(val, 0x0F)
        self.enable_irq = band(val, 0x08) == 0
        self.hold_counter = band(val, 0x80) ~= 0
        self.pic:clear_interrupt(self.irq)
    end
end

local function port_control_in(self)
    return function(cpu, port)
        local ret = self.control_reg

        self.control_reg = bor(self.control_reg, 0x0F)

        if self.enable_irq then
            self.control_reg = bor(band(self.control_reg, bnot(self.irq_mask)), band(math.random(0, 255), self.irq_mask))
        end

        return ret
    end
end

local function port_config_out(self)
    return function(cpu, port, val)
        if band(val, 0x80) ~= 0 then
            self.config_reg = val
            self.enabled = true
            self.control_reg = band(0x0F, bnot(self.irq_mask))
        else
            local bit = lshift(1, band(rshift(val, 1), 0x07))

            if band(val, 0x01) ~= 0 then
                self.control_reg = bor(self.control_reg, bit)
            else
                self.control_reg = band(self.control_reg, bnot(bit))
            end
        end
    end
end

local function port_config_in(self)
    return function(cpu, port)
        if self.enabled then
            return band(bor(self.control_reg, 0x0F), bnot(self.irq_mask))
        end

        return 0xFF
    end
end

local function reset(self)
    self.control_reg = 0x0F
    self.sig_reg = 0x00
    self.config_reg = 0x9B
    self.mouse_x = 0x00
    self.mouse_y = 0x00
    self.buttons = 0x00
    self.enabled = false
    self.enable_irq = false
    self.hold_counter = false
end

function mouse.new(cpu, pic, base_addr, irq)
    local self = {
        pic = pic,
        control_reg = 0x0F,
        sig_reg = 0x00,
        config_reg = 0x9B,
        mouse_x = 0,
        mouse_y = 0,
        buttons = 0,
        irq = irq or 5,
        irq_mask = rshift(lshift(1, 5), irq or 5),
        enabled = false,
        enable_irq = false,
        hold_counter = false,
        reset = reset
    }

    local addr = base_addr or 0x23C
    local cpu_io = cpu:get_io()

    cpu_io:set_port_in(addr, port_data_in(self))
    cpu_io:set_port(addr + 1, port_signature_out(self), port_signature_in(self))
    cpu_io:set_port(addr + 2, port_control_out(self), port_control_in(self))
    cpu_io:set_port(addr + 3, port_config_out(self), port_config_in(self))

    events.on("retro_computers:input_manager.mouse_state_changed", function(delta_x, delta_y, left_pressed, middle_pressed, right_pressed)
        if not self.enabled then
            return
        end

        if not self.hold_counter then
            self.mouse_x = band(delta_x, 0xFF)
            self.mouse_y = band(delta_y, 0xFF)
            self.buttons = 0x00

            if left_pressed then
                self.buttons = bor(self.buttons, 0x04)
            end

            if right_pressed then
                self.buttons = bor(self.buttons, 0x01)
            end
        end

        self.pic:request_interrupt(self.irq)
    end)

    return self
end

return mouse
