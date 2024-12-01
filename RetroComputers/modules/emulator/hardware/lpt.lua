local logger = require("retro_computers:logger")
local lpt = {}
local band, bor = bit.band, bit.bor

local function init_port(self, base, cpu)
    self.ports[base] = {nil, 0, 0}
    cpu:port_set(base, function(cpu, port, val) -- Data Register
        if val then
            logger:debug("LPT %03X: Write %d to Data register", base, val)
            if self.ports[base][1] then
                if self.ports[base][1].write then
                    self.ports[base][1]:write(val)
                    return
                end
            end
            self.ports[base][2] = val
        else
            logger:debug("LPT %03X: Read Data register", base)
            if self.ports[base][1] then
                if self.ports[base][1].read then
                    return self.ports[base][1]:read(val)
                end
            end
            return self.ports[base][2]
        end
    end)
    cpu:port_set(base + 1, function(cpu, port, val) -- Status Register
        if not val then
            logger:debug("LPT %03X: Read Status register", base)
            if self.ports[base] then
                if self.ports[base].read_status then
                    return self.ports[base].read_status()
                end
            end
            return 0xDF
        end
    end)
    cpu:port_set(base + 2, function(cpu, port, val) -- Control Register
        if val then
            logger:debug("LPT %03X: Write %d to Control register", base, val)
            if self.ports[base] then
                if self.ports[base].write_control then
                    self.ports[base]:write_control(val)
                    return
                end
            end
            self.ports[base][3] = val
        else
            logger:debug("LPT %03X: Read Control register", base)
            if self.ports[base] then
                if self.ports[base].read_control then
                    return self.ports[base]:read_control(val)
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

function lpt.new(cpu)
    local self = {
        get_port_handler = get_port_handler,
        set_port_handler = set_port_handler,
        ports = {}
    }

    init_port(self, 0x378, cpu) -- LPT 1
    init_port(self, 0x278, cpu) -- LPT 2
    return self
end

return lpt