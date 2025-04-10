---@diagnostic disable: undefined-field
local logger = require("retro_computers:logger")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot
local port_irqs = {0x80, 0x20, 0x80}

local function init_port(self, port_num, base, cpu)
    local port = {
        handler = nil,
        data_reg = 0x00,
        control_reg = 0x00,
        irq = port_irqs[port_num],
        enable_irq = true
    }

    cpu:set_port(base, function(_, _, val) -- Data Register
        if val then
            local handler = port.handler

            if handler then
                if handler.write_data then
                    handler:write_data(val)
                end
            end

            port.data_reg = val
        else
            local handler = port.handler

            if handler then
                if handler.read_data then
                    return handler:read_data(val)
                end
            end

            return port.data_reg
        end
    end)

    cpu:set_port(base + 1, function(_, _, val) -- Status Register
        if not val then
            local handler = port.handler

            if handler then
                if handler.read_status then
                    return bor(handler:read_status(), 0x0)
                end
            end

            return 0xD7
        end
    end)
    cpu:set_port(base + 2, function(_, _, val) -- Control Register
        if val then
            local handler = port.handler

            if handler then
                if handler.write_control then
                    handler:write_control(val)
                end
            end

            port.control_reg = val
            port.enable_irq = band(val, 0x10) ~= 0
        else
            local handler = port.handler

            if handler then
                if handler.read_control then
                    return bor(band(handler:read_control(), 0xEF), port.enable_irq and 0x10 or 0x00)
                end
            end

            return bor(bor(0xE0, port.control_reg), port.enable_irq and 0x10 or 0x00)
        end
    end)

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

local lpt = {}

function lpt.new(cpu)
    local self = {
        ports = {},
        get_port_handler = get_port_handler,
        set_port_handler = set_port_handler,
        reset = reset
    }

    init_port(self, 1, 0x378, cpu) -- LPT 1
    init_port(self, 2, 0x278, cpu) -- LPT 2
    init_port(self, 3, 0x3BC, cpu) -- LPT 3

    return self
end

return lpt