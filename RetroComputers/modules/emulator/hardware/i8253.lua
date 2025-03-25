-- PIT 8253
-- Channel modes
-- 0 - Interrupt On Terminal Count
-- 1 - Hardware Re-triggerable One-shot
-- 2 - Rate Generator
-- 3 - Square Wave Generator
-- 4 - Software Triggered Strobe
-- 5 - Hardware Triggered Strobe
-- Access modes
-- 0 - Latch count value command
-- 1 - lobyte only
-- 2 - hibyte only
-- 3 - lobyte/hibyte

local logger = require("retro_computers:logger")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local function create_channel(self, channel)
	self.channels[channel] = {
		mode = 0,
        read_mode = 0,
        write_mode = 0,
		reload = 0xFFFF,
		count = 0,
        latched = 0,
        state = 0,
        lcounter = 0,
        handler = nil,
        load_handler = nil,
        incompleted = false,
        newcount = false,
        gate = false,
        latch = false,
        bcd = false,
        out = false
	}
end

local function reset_channel(self, channel_num)
	local channel = self.channels[channel_num]

    channel.mode = 0
    channel.read_mode = 0
    channel.write_mode = 0
    channel.reload = 0xFFFF
    channel.count = 0
    channel.latched = 0
    channel.state = 0
    channel.lcounter = 0
    channel.incompleted = false
    channel.newcount = false
    channel.latch = false
    channel.bcd = false
    channel.gate = false
    channel.out = false
end

local function channel_out(channel, set)
    if channel.handler then
        channel.handler(channel, set, channel.out)
    end

    channel.out = set
end

local function channel_load(channel)
    channel.latch = true

    if channel.load_handler then
        local count = channel.reload

        if count == 0 then
            count = 0x10000
        end

        channel.load_handler(channel.mode, count)
    end
end

local function decrease_count(channel)
    if channel.bcd then
        local units = band(channel.count, 0xF) - 1
        local tens = lshift(band(channel.count, 0xF0), 4)
        local hundreds = lshift(band(channel.count, 0xF00), 8)
        local thousands = lshift(band(channel.count, 0xF000), 12)

        if units < 0 then
            units = 9
            tens = tens - 1

            if tens < 0 then
                tens = 9
                hundreds = hundreds - 1

                if hundreds < 0 then
                    hundreds = 9
                    thousands = thousands - 1

                    if thousands < 0 then
                        units = 9
                        tens = 9
                        hundreds = 9
                        thousands = 9
                    end
                end
            end
        end

        channel.count = bor(rshift(thousands, 12), bor(rshift(hundreds, 8), bor(rshift(tens, 4), units)))
    else
        channel.count = band(channel.count - 1, 0xFFFF)
    end
end

local function channel_update_state(channel)
    local mode  = band(channel.mode, 0x03)

    if channel.incomplete or (mode == 0) or (channel.state == 0) then
        if mode == 1 then
            channel.state = 5
        else
            channel.state = 1
        end
    end

    channel.incomplete = false
end

local function channel_update_count(channel)
    if channel.reload ~= 0 then
        channel.count = channel.reload
    else
        channel.count = 0x10000
    end

    channel.newcount = band(channel.count, 0x01) == 0x01
    channel.incomplete = band(channel.write_mode, 0x80) ~= 0
end

local function channel_update(self, channel_num)
    local channel = self.channels[channel_num]

    if band(channel.state, 0x03) == 0x01 then
        channel_update_count(channel)
        channel.state = channel.state + 1

        if (band(channel.mode, 0x07) == 0x01) and (channel.state == 2) then
            channel_out(ch, false)
        end
    else
        if channel.mode == 0 then -- Interrupt On Terminal Count
            if channel.state == 2 then
                if channel.gate and (channel.count >= 1) then
                    decrease_count(channel)

                    if channel.count < 1 then
                        channel.state = 3
                        channel_out(channel, true)
                    end
                end
            elseif channel.state == 3 then
                decrease_count(channel)
            end

            return
        elseif channel.mode == 1 then -- Hardware Re-triggerable One-shot
            if channel.state == 2 then
                if channel.count >= 1 then
                    decrease_count(channel)

                    if channel.count < 1 then
                        channel.state = 3
                        channel_out(channel, true)
                    end
                end
            elseif (channel.state == 3) or (channel.state == 6) then
                decrease_count(channel)
            end

            return
        elseif (channel.mode == 2) or (channel.mode == 6) then -- Rate Generator
            if channel.state == 3 then
                channel_update_count(channel)
                channel.state = 2
                channel_out(channel, true)
            elseif channel.state == 2 then
                if channel.gate and (channel.count >= 2) then
                    decrease_count(channel)

                    if channel.count < 2 then
                        channel.state = 3
                        channel_out(channel, false)
                    end
                end
            end

            return
        elseif (channel.mode == 3) or (channel.mode == 7) then -- Square Wave Generator
            if not channel.gate then
                return
            end

            if channel.state == 2 then
                if channel.count >= 0 then
                    if channel.bcd then
                        decrease_count(channel)

                        if channel.newcount then
                            decrease_count(channel)
                        end
                    else
                        if channel.newcount then
                            channel.count = channel.count - 1
                        else
                            channel.count = channel.count - 2
                        end
                    end

                    if channel.count < 0 then
                        channel_out(channel, false)
                        channel_update_count(channel)
                        channel.state = 3
                    elseif channel.newcount then
                        channel.newcount = false
                    end
                end

                return
            elseif channel.state == 3 then
                if channel.count >= 0 then
                    if channel.bcd then
                        decrease_count(channel)
                        decrease_count(channel)

                        if channel.newcount then
                            decrease_count(channel)
                        end
                    else
                        if channel.newcount then
                            channel.count = channel.count - 3
                        else
                            channel.count = channel.count - 2
                        end
                    end

                    if channel.count < 0 then
                        channel_out(channel, true)
                        channel_update_count(channel)
                        channel.state = 2
                    elseif channel.newcount then
                        channel.newcount = false
                    end
                end

                return
            end
        elseif (channel.mode == 4) or (channel.mode == 5) then -- Hardware Triggered Strobe / Software Triggered Strobe
            if channel.gate or (channel.mode == 5) then
                if (channel.state == 0) or (channel.state == 6) then
                    decrease_count(channel)
                    return
                elseif channel.state == 2 then
                    if channel.count >= 1 then
                        decrease_count(channel)

                        if channel.count < 1 then
                            channel.state = 3
                            channel_out(channel, false)
                        end
                    end

                    return
                elseif channel.state == 3 then
                    channel.state = 0
                    channel_out(channel, true)
                    return
                end
            end
        end
    end
end

local function pit_tick(self)
    for i = 0, 2, 1 do
        local channel = self.channels[i]

        if channel.latch then
            channel_update_state(channel)
            channel.latch = false
        else
            channel_update(self, i)
        end
    end
end

local function port_init(self, channel_num)
    local channel = self.channels[channel_num]

    return function (cpu, port, val)
        if val then -- Write
            if channel.write_mode == 1 then
                channel.reload = bor(band(channel.reload, 0xFF00), val)
                channel_load(channel)

                if channel.mode == 0 then
                    channel_out(channel, 0)
                end
            elseif channel.write_mode == 2 then
                channel.reload = bor(band(channel.reload, 0x00FF), lshift(val, 8))
                channel_load(channel)

                if channel.mode == 0 then
                    channel_out(channel, 0)
                end
            elseif (channel.write_mode == 3) or (channel.write_mode == 0x83) then
                if band(channel.write_mode, 0x80) ~= 0 then
                    channel.reload = bor(band(channel.reload, 0x00FF), lshift(val, 8))
                    channel_load(channel)
                else
                    channel.reload = bor(band(channel.reload, 0xFF00), val)

                    if channel.mode == 0 then
                        channel.state = 0
                        channel_out(channel, 0)
                    end
                end

                if band(channel.write_mode, 0x80) ~= 0 then
                    channel.write_mode = band(channel.write_mode, bnot(0x80))
                else
                    channel.write_mode = bor(channel.write_mode, 0x80)
                end
            end

            -- logger.debug("PIT: Channel %d: Write 0x%02X, Latch = %s, Reload = 0x%04X", channel, val, tostring(channel.latch), channel.reload)
        else -- Read
            if channel.latched > 0 then
                local ret = channel.lcounter

                if band(channel.read_mode, 0x80) ~= 0 then
                    ret = rshift(ret, 8)
                    channel.read_mode = band(channel.read_mode, bnot(0x80))
                else
                    channel.read_mode = bor(channel.read_mode, 0x80)
                end

                channel.latched = channel.latched - 1

                return ret
            else
                local count = channel.count

                if channel.state == 1 then
                    count = channel.reload
                end

                if (channel.read_mode == 0) or (channel.read_mode == 0x80) then
                    return 0x00
                elseif channel.read_mode == 1 then
                    return band(count, 0xFF)
                elseif channel.read_mode == 2 then
                    return rshift(count, 8)
                elseif (channel.read_mode == 3) or (channel.read_mode == 0x83) then
                    local ret = 0

                    if band(channel.write_mode, 0x80) == 0x80 then
                        ret = bnot(band(channel.reload, 0xFF))
                    else
                        if band(channel.read_mode, 0x80) == 0x80 then
                            ret = band(rshift(count, 8), 0xFF)
                        else
                            ret = band(count, 0xFF)
                        end
                    end

                    if band(channel.read_mode, 0x80) == 0x80 then
                        channel.read_mode = band(channel.read_mode, bnot(0x80))
                    else
                        channel.read_mode = bor(channel.read_mode, 0x80)
                    end

                    return ret
                end
            end

            return 0xFF
        end
    end
end

local function port_43(self)
    return function(cpu, port, val)
        if val then
            local channel_num = rshift(val, 6)
            local channel = self.channels[channel_num]

            if band(val, 0x30) == 0 then
                local count = channel.count

                if channel.latch or (channel.state == 1) then
                    count = channel.reload
                end

                if channel.mode == 1 then
                    channel.lcounter = bor(band(lshift(count, 8), 0xFF00), band(count, 0xFF))
                    channel.latched = 1
                elseif channel.mode == 2 then
                    channel.lcounter = bor(band(count, 0xFF00), band(rshift(count, 8), 0xFF))
                    channel.latched = 1
                elseif channel.mode == 3 then
                    channel.lcounter = band(count, 0xFFFF)
                    channel.latched = 2
                end

                -- logger.debug("PIT: Latched bytes = %d, Latched counter = 0x%04X", channel.latched, channel.lcounter)
            else
                channel.read_mode = band(rshift(val, 4), 3)
                channel.write_mode = channel.read_mode
                channel.mode = band(rshift(val, 1), 7)
                channel.bcd = band(val, 1) == 1
                channel.state = 0

                if channel.mode > 5 then
                    channel.mode = band(channel.mode, 0x03)
                end

                channel_out(channel, channel.mode > 0)

                if channel.latched > 0 then
                    channel.lcounter = channel.lcounter - 1
                end

                -- logger.debug("i8253: Channel %d: Setting: Access mode = %d, Operating mode = %d, BSD = %s. Count = %04X", channel_num, channel.read_mode, channel.mode, channel.bcd, channel.count)
            end
        else
            return 0x00
        end
    end
end

local function reset(self)
    reset_channel(self, 0)
    reset_channel(self, 1)
    reset_channel(self, 2)

    self.channels[0].gate = true
    self.channels[1].gate = true
end

local function get_channel_handler(self, num)
    local channel = self.channels[num]

    if channel then
        return channel.handler
    end
end

local function set_channel_handler(self, num, handler)
    local channel = self.channels[num]

    if channel then
        channel.handler = handler
    end
end

local function set_channel_load_handler(self, num, handler)
    local channel = self.channels[num]

    if channel then
        channel.load_handler = handler
    end
end

local function set_channel_gate(self, num, set)
    local channel = self.channels[num]

    if channel then
        local mode = band(channel.mode, 0x03)

        if mode > 0 then
            if (not channel.gate) and set then
                if band(mode, 0x01) ~= 0 then
                    if mode ~= 1 then
                        channel_out(channel, true)
                    end

                    channel.state = 1
                elseif mode == 2 then
                    channel.state = 3
                end
            elseif channel.gate and (not set) then
                if band(mode, 0x02) ~= 0 then
                    channel_out(channel, true)
                end
            end
        end

        channel.gate = set
    end
end

local pit = {}

function pit.new(cpu)
    local self = {
        channels = {},
        get_channel_handler = get_channel_handler,
        set_channel_handler = set_channel_handler,
        set_channel_load_handler = set_channel_load_handler,
        set_channel_gate = set_channel_gate,
        update = pit_tick,
        reset = reset
    }

    create_channel(self, 0) -- IRQ0
    create_channel(self, 1) -- DRAM
    create_channel(self, 2) -- PC Speaker

    cpu:set_port(0x40, port_init(self, 0)) -- Channel data 0
    cpu:set_port(0x41, port_init(self, 1)) -- Channel data 1
    cpu:set_port(0x42, port_init(self, 2)) -- Channel data 2
    cpu:set_port(0x43, port_43(self)) -- Mode switcher

    self.channels[0].gate = true
    self.channels[1].gate = true

    return self
end

return pit