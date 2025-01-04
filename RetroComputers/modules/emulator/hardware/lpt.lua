-- LPT (https://wiki.osdev.org/Parallel_port)

local logger = require("retro_computers:logger")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local function init_port(self, base, cpu)
    self.ports[base] = {nil, 0, 0}
    local port = self.ports[base]

    cpu:port_set(base, function(_, _, val) -- Data Register
        if val then
            logger:debug("LPT: %03X: Write %d to Data register", base, val)
            if port[1] ~= nil then
                if port[1].write then
                    port[1]:write(val)
                    return
                end
            end
            port[2] = val
        else
            logger:debug("LPT: %03X: Read Data register", base)
            if self.ports[base][1] then
                if self.ports[base][1].read then
                    return band(self.ports[base][1]:read(val), 0xFF)
                end
            end
            return self.ports[base][2]
        end
    end)
    cpu:port_set(base + 1, function(_, _, val) -- Status Register
        if not val then
            logger:debug("LPT: %03X: Read Status register", base)
            if self.ports[base] then
                if self.ports[base].read_status then
                    return band(self.ports[base].read_status(), 0xFF)
                end
            end
            return 0xDF
        end
    end)
    cpu:port_set(base + 2, function(_, _, val) -- Control Register
        if val then
            logger:debug("LPT: %03X: Write %d to Control register", base, val)
            if self.ports[base] then
                if self.ports[base].write_control then
                    self.ports[base]:write_control(val)
                    return
                end
            end
            self.ports[base][3] = val
        else
            logger:debug("LPT: %03X: Read Control register", base)
            if self.ports[base] then
                if self.ports[base].read_control then
                    return band(self.ports[base]:read_control(val), 0xFF)
                end
            end
            return bor(bor(0xE0, self.ports[base][3]), 0)
        end
    end)
end

local function get_port_handler(self, port)
    return self.ports[port][1]
end

local function set_port_handler(self, port, handler)
    self.ports[port][1] = handler
end

local function reset(self)
    for _, port in pairs(self.ports) do
        port[2] = 0
        port[3] = 0
    end
end

local lpt = {}

function lpt.new(cpu)
    local self = {
        get_port_handler = get_port_handler,
        set_port_handler = set_port_handler,
        reset = reset,
        ports = {}
    }

    init_port(self, 0x378, cpu) -- LPT 1
    init_port(self, 0x278, cpu) -- LPT 2
    init_port(self, 0x3BC, cpu) -- LPT 3

    return self
end

return lpt