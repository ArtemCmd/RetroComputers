local io_ports = {}

local function get_port_out(self, port)
    return self.out_ports[port]
end

local function set_port_out(self, port, func)
    self.out_ports[port] = func
end

local function get_port_in(self, port)
    return self.in_ports[port]
end

local function set_port_in(self, port, func)
    self.in_ports[port] = func
end

local function set_port_out_range(self, start_port, end_port, func)
    for i = start_port, end_port, 1 do
        self.out_ports[i] = func
    end
end

local function set_port_in_range(self, start_port, end_port, func)
    for i = start_port, end_port, 1 do
        self.in_ports[i] = func
    end
end

local function get_port(self, port)
    return self.out_ports[port], self.in_port[port]
end

local function set_port(self, port, func_out, func_in)
    self.in_ports[port] = func_in
    self.out_ports[port] = func_out
end

local function in_port(self, port)
    local func = self.in_ports[port]

    if func then
        return func(self.cpu, port)
    end

    return 0xFF
end

local function out_port(self, port, val)
    local func = self.out_ports[port]

    if func then
        func(self.cpu, port, val)
    end
end

function io_ports.new(cpu)
    local self = {
        cpu = cpu,
        in_ports = {},
        out_ports = {},
        get_port_in = get_port_in,
        get_port_out = get_port_out,
        set_port_in = set_port_in,
        set_port_out = set_port_out,
        set_port_in_range = set_port_in_range,
        set_port_out_range = set_port_out_range,
        in_port = in_port,
        out_port = out_port,
        get_port = get_port,
        set_port = set_port
    }

    return self
end

return io_ports
