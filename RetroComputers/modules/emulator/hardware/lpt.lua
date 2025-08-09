-- =====================================================================================================================================================================
-- Line Print Terminal (LPT) emulation.
-- =====================================================================================================================================================================

local logger = require("dave_logger:logger")("RetroComputers")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local lpt = {}
local port_irqs = {7, 5}

local function port_data_register_out(self)
    return function(cpu, port, val)
        if self.handler then
            if self.handler.write_data then
                self.handler:write_data(val)
            end
        end

        self.data_reg = val
    end
end

local function port_data_register_in(self)
    return function(cpu, port)
        if self.handler then
            if self.handler.read_data then
                return self.handler:read_data(val)
            end
        end

        return self.data_reg
    end
end

local function port_status_register_in(self)
    return function(cpu, port)
        if self.handler then
            if self.handler.read_status then
                return bor(self.handler:read_status(), 0x07)
            end
        end

        return 0xD7
    end
end

local function port_control_register_out(self)
    return function(cpu, port, val)
        if self.handler then
            if self.handler.write_control then
                self:write_control(val)
            end
        end

        self.control_reg = val
        self.enable_irq = band(val, 0x10) ~= 0

        if not self.enable_irq then
            self.pic:clear_interrupt(self.irq)
        end
    end
end

local function port_control_register_in(self)
    return function(cpu, port)
        if self.handler then
            if self.handler.read_control then
                return bor(band(self.handler:read_control(), 0xEF), self.enable_irq and 0x10 or 0x00)
            end
        end

        return bor(bor(0xE0, self.control_reg), self.enable_irq and 0x10 or 0x00)
    end
end

local function init_port(self, port_num, base, cpu_io)
    local port = {
        pic = self.pic,
        handler = nil,
        data_reg = 0x00,
        control_reg = 0x00,
        irq = port_irqs[port_num],
        enable_irq = true
    }

    cpu_io:set_port(base, port_data_register_out(port), port_data_register_in(port))
    cpu_io:set_port_in(base + 1, port_status_register_in(port))
    cpu_io:set_port(base + 2, port_control_register_out(port), port_control_register_in(port))

    self.ports[port_num] = port
end

local function get_port_handler(self, port)
    return self.ports[port].handler
end

local function set_port_handler(self, port, handler)
    self.ports[port].handler = handler
end

local function reset(self)
    for i = 1, #self.ports, 1 do
        local port = self.ports[i]

        port.data_reg = 0x00
        port.control_reg = 0x00
        port.enable_irq = true
    end
end

function lpt.new(cpu, pic)
    local self = {
        pic = pic,
        ports = {},
        get_port_handler = get_port_handler,
        set_port_handler = set_port_handler,
        reset = reset
    }

    local cpu_io = cpu:get_io()

    init_port(self, 1, 0x378, cpu_io) -- LPT 1
    init_port(self, 2, 0x278, cpu_io) -- LPT 2

    return self
end

return lpt
