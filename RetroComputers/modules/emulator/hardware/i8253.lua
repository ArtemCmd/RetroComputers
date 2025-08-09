-- =====================================================================================================================================================================
-- Programmable Interval Timer (PIT) emulation.
-- =====================================================================================================================================================================

local logger = require("dave_logger:logger")("RetroComputers")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local pit = {}

local PIT_FREQ = 1193182

local CHANNEL_MODE_TERMINAL_COUNT = 0 -- Interrupt On Terminal Count
local CHANNEL_MODE_ONE_SHOT = 1       -- Hardware Re-triggerable One-shot
local CHANNEL_MODE_RATE = 2           -- Rate Generator
local CHANNEL_MODE_SQUARE_WAVE = 3    -- Square Wave Generator
local CHANNEL_MODE_SSTROBE = 4        -- Software Triggered Strobe
local CHANNEL_MODE_HSTROBE = 5        -- Hardware Triggered Strobe

local function create_channel(self, channel_num)
    self.channels[channel_num] = {
        clock = 0,
        count = 0,
        reload = 0,
        load = 0xFFFF,
        mode = 0,
        read_mode = 0,
        write_mode = 0,
        rlatch = false,
        thit = true,
        gate = false,
        out = false,
        new_count = false,
        latched = false,
        initial = false,
        enabled = false,
        disabled = false,
        running = false
    }
end

local function get_channel_count(self, channel)
    if not ((channel.mode == CHANNEL_MODE_SQUARE_WAVE) and (not channel.gate)) then
        local clock = os.clock()
        local read = 0x10000 - math.floor((clock - self.clock) * PIT_FREQ)

        if channel.mode == CHANNEL_MODE_RATE then
            read = read + 1
        end

        if read < 0 then
            channel.clock = time.uptime()
            read = 0
        end

        if read > 0x10000 then
            read = 0x10000
        end

        if channel.mode == CHANNEL_MODE_SQUARE_WAVE then
            read = lshift(read, 1)
        end

        return band(read, 0xFFFF)
    end

    if channel.mode == CHANNEL_MODE_RATE then
        return band(channel.count + 1, 0xFFFF)
    end

    return band(channel.count, 0xFFFF)
end

local function disable_channel(self, channel)
    channel.count = get_channel_count(self, channel)

    if channel.mode == CHANNEL_MODE_RATE then
        channel.count = channel.count - 1
    end
end

local function out_channel(channel, out)
    if channel.out_handler then
        channel.out_handler(out, channel.out)
    end

    channel.out = out
end

local channel_modes = {
    [CHANNEL_MODE_TERMINAL_COUNT] = function(channel, count)
        channel.count = count
        channel.thit = false
        channel.enabled = channel.gate

        out_channel(channel, false)
    end,
    [CHANNEL_MODE_ONE_SHOT] = function(channel, count)
        channel.enabled = true
    end,
    [CHANNEL_MODE_RATE] = function(channel, count)
        if channel.initial then
            channel.count = count - 1
            channel.thit = false
            out_channel(channel, true)
        end

        channel.enabled = channel.gate
    end,
    [CHANNEL_MODE_SQUARE_WAVE] = function(channel, count)
        if channel.initial then
            channel.count = count
            channel.thit = false

            out_channel(channel, true)
        end

        channel.enabled = channel.gate
    end,
    [CHANNEL_MODE_SSTROBE] = function(channel, count)
        if (not channel.thit) and (not channel.initial) then
            channel.new_count = true
        else
            channel.count = count
            channel.thit = false

            out_channel(channel, false)
        end

        channel.enabled = channel.gate
    end,
    [CHANNEL_MODE_HSTROBE] = function(channel, count)
        channel.enabled = true
    end
}

local function channel_load(self, channel)
    local count = channel.load

    if count == 0 then
        count = 0x10000
    end

    channel.new_count = false
    channel.disabled = false

    channel_modes[channel.mode](channel, count)

    if channel.load_func then
        channel.load_func(channel.mode, count)
    end

    channel.initial = false
    channel.running = channel.enabled and (not channel.disabled)
    channel.clock = time.uptime()

    if not channel.running then
        disable_channel(self, channel)
    end
end

local read_modes = {
    [0x00] = function(channel)
        channel.read_mode = 3
        channel.latched = false
        channel.rlatch = true

        return band(rshift(channel.reload, 8), 0xFF)
    end,
    [0x01] = function(channel)
        channel.latched = false
        channel.rlatch = true

        return band(channel.reload, 0xFF)
    end,
    [0x02] = function(channel)
        channel.latched = false
        channel.rlatch = true

        return band(rshift(channel.reload, 8), 0xFF)
    end,
    [0x03] = function(channel)
        if band(channel.mode, 0x80) ~= 0 then
            channel.mode = band(channel.mode, 0x07)
        else
            channel.read_mode = 0x00
        end

        return band(channel.reload, 0xFF)
    end
}

local write_modes = {
    [0x00] = function(self, channel, val)
        channel.load = bor(band(channel.load, 0x00FF), lshift(val, 8))
        channel.write_mode = 0x03

        channel_load(self, channel)
    end,
    [0x01] = function(self,channel, val)
        channel.load = val
        channel_load(self, channel)
    end,
    [0x02] = function(self, channel, val)
        channel.load = lshift(val, 8)
        channel_load(self, channel)
    end,
    [0x03] = function(self, channel, val)
        channel.load = bor(band(channel.load, 0xFF00), val)
        channel.write_mode = 0x00
    end
}

local function port_out_channel(self, channel)
    return function(cpu, port, val)
        write_modes[channel.write_mode](self, channel, val)
    end
end

local function port_channel_in(self, channel)
    return function(cpu, port)
        if channel.rlatch and (not channel.latched) then
            channel.rlatch = false
            channel.reload = get_channel_count(self, channel)
        end

        return read_modes[channel.read_mode](channel)
    end
end

local function port_control_out(self)
    return function(cpu, port, val)
        local channel_num = rshift(val, 6)
        local channel = self.channels[channel_num]

        if band(val, 0x30) == 0 then
            channel.reload = get_channel_count(self, channel)
            channel.read_mode = 3
            channel.latched = true
            channel.rlatch = false
        else
            channel.read_mode = band(rshift(val, 4), 0x03)
            channel.write_mode = channel.read_mode
            channel.mode = band(rshift(val, 1), 0x07)

            if channel.mode > 5 then
                channel.mode = band(channel.mode, 0x03)
            end

            if channel.read_mode == 0 then
                channel.read_mode = 3
                channel.reload = get_channel_count(self, channel)
            end

            channel.rlatch = true
            channel.initial = true
            channel.disabled = true

            out_channel(channel, channel.mode ~= 0)
        end

        channel.thit = false
    end
end

local function port_control_in(self)
    return function(cpu, port)
        return 0x00
    end
end

local function update(self)
    self.clock = os.clock()

    for i = 0, 2, 1 do
        local channel = self.channels[i]

        if channel.disabled then
            channel.count = band(channel.count + 0xFFFF, 0xFFFF)
        else
            local count = channel.load

            if count == 0 then
                count = 0x10000
            end

            if (channel.mode == CHANNEL_MODE_TERMINAL_COUNT) or (channel.mode == CHANNEL_MODE_ONE_SHOT) then
                if not channel.thit then
                    out_channel(channel, true)
                end

                channel.thit = true
                channel.count = band(channel.count + 0xFFFF, 0xFFFF)
            elseif channel.mode == CHANNEL_MODE_RATE then
                channel.count = band(channel.count + count, 0xFFFF)

                out_channel(channel, false)
                out_channel(channel, true)
            elseif channel.mode == CHANNEL_MODE_SQUARE_WAVE then
                if channel.out then
                    out_channel(channel, false)
                    channel.count = channel.count + rshift(count, 1)
                else
                    out_channel(channel, true)
                    channel.count = rshift(count + 1, 1)
                    channel.count = channel.count + rshift(count, 1)
                end
            elseif channel.mode == CHANNEL_MODE_SSTROBE then
                if not channel.thit then
                    out_channel(channel, false)
                    out_channel(channel, true)
                end

                if channel.new_count then
                    channel.new_count = false
                    channel.count = band(channel.count + count, 0xFFFF)
                else
                    channel.thit = true
                    channel.count = band(channel.count + 0xFFFF, 0xFFFF)
                end
            elseif channel.mode == CHANNEL_MODE_HSTROBE then
                if not channel.thit then
                    out_channel(channel, false)
                    out_channel(channel, true)
                end

                channel.thit = true
                channel.count = band(channel.count + 0xFFFF, 0xFFFF)
            end

            channel.running = channel.enabled and (not channel.disabled)

            if not channel.running then
                disable_channel(self, channel)
            end
        end
    end
end

local function set_channel_gate(self, channel_num, gate)
    local channel = self.channels[channel_num]

    if channel.disabled then
        channel.gate = gate
        return
    end

    local count = channel.load
    local mode = channel.mode

    if count == 0 then
        count = 0x10000
    end

    if (mode == CHANNEL_MODE_TERMINAL_COUNT) or (mode == CHANNEL_MODE_SSTROBE) then
        channel.gate = gate
    elseif (mode == CHANNEL_MODE_ONE_SHOT) or (mode == CHANNEL_MODE_HSTROBE) then
        if gate and (not channel.gate) then
            channel.count = count
            channel.thit = false
            channel.enabled = true

            out_channel(channel, false)
        end
    elseif mode == CHANNEL_MODE_RATE then
        if gate and (not channel.gate) then
            channel.count = count - 1
            channel.thit = false

            out_channel(channel, true)
        end

        channel.enabled = gate
    elseif mode == CHANNEL_MODE_SQUARE_WAVE then
        if gate and (not channel.gate) then
            channel.count = count
            channel.thit = false
            channel.new_count = band(count, 0x01) ~= 0

            out_channel(channel, true)
        end

        channel.enabled = gate
    end

    channel.gate = gate
    channel.running = channel.enabled and (not channel.disabled)

    if not channel.running then
       disable_channel(self, channel)
    end
end

local function set_channel_out_handler(self, channel_num, func)
    local channel = self.channels[channel_num]

    if channel then
        channel.out_handler = func
    end
end

local function set_channel_load_handler(self, channel_num, func)
    local channel = self.channels[channel_num]

    if channel then
        channel.load_func = func
    end
end

function pit.new(cpu, base_port)
    local self = {
        cpu = cpu,
        clock = 0,
        channels = {},
        update = update,
        set_channel_out_handler = set_channel_out_handler,
        set_channel_load_handler = set_channel_load_handler,
        set_channel_gate = set_channel_gate,
    }

    create_channel(self, 0)
    create_channel(self, 1)
    create_channel(self, 2)

    local cpu_io = cpu:get_io()

    cpu_io:set_port(base_port, port_out_channel(self, self.channels[0]), port_channel_in(self, self.channels[0]))
    cpu_io:set_port(base_port + 1, port_out_channel(self, self.channels[1]), port_channel_in(self, self.channels[1]))
    cpu_io:set_port(base_port + 2, port_out_channel(self, self.channels[2]), port_channel_in(self, self.channels[1]))
    cpu_io:set_port(base_port + 3, port_control_out(self), port_control_in(self))

    self.channels[0].gate = true
    self.channels[1].gate = true

    return self
end

return pit
