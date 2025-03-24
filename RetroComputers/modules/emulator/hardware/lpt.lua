local logger = require("retro_computers:logger")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot
local port_address = {0x378, 0x278, 0x3BC}

local function init_port(self, base, cpu)
    self.ports[base] = {nil, 0, 0, false}
    local port = self.ports[base]

    cpu:set_port(base, function(_, _, val) -- Data Register
        if val then
            if port[1] ~= nil then
                if port[1].write then
                    port[1]:write(val)
                end
            end

            port[2] = val
        else
            if port[1] then
                if port[1].read then
                    return band(port[1]:read(val), 0xFF)
                end
            end

            return port[2]
        end
    end)
    cpu:set_port(base + 1, function(_, _, val) -- Status Register
        if not val then
            if port[1] ~= nil then
                if port[1].read_status then
                    return band(port[1].read_status(), 0xFF)
                end
            end

            return 0xDF
        end
    end)
    cpu:set_port(base + 2, function(_, _, val) -- Control Register
        if val then
            if port[1] ~= nil then
                if port[1].write_control then
                    port[1]:write_control(val)
                end
            end

            port[3] = val
            port[4] = band(val, 0x10) ~= 0
        else
            if port[1] ~= nil then
                if port[1].read_control then
                    return bor(band(port[1]:read_control(val), 0xFF), port[4] and 0x10 or 0x00)
                end
            end

            return bor(bor(0xE0, port[3]), port[4] and 0x10 or 0x00)
        end
    end)
end

local function get_port_handler(self, port)
    return self.ports[port_address[port]][1]
end

local function set_port_handler(self, port, handler)
    self.ports[port_address[port]][1] = handler
end

local function reset(self)
    for _, port in pairs(self.ports) do
        port[2] = 0
        port[3] = 0
        port[4] = false
    end
end

local lpt = {}

function lpt.new(cpu)
    local self = {
        ports = {},
        enable_irq = false,
        get_port_handler = get_port_handler,
        set_port_handler = set_port_handler,
        reset = reset
    }

    init_port(self, 0x378, cpu) -- LPT 1
    init_port(self, 0x278, cpu) -- LPT 2
    init_port(self, 0x3BC, cpu) -- LPT 3

    return self
end

return lpt