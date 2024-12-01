-- PIT 8253 (https://wiki.osdev.org/Programmable_Interval_Timer)
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
		bcd = false,
		count = 0,
        latch = false,
        latched = 0,
        gate = false,
        state = 0,
        incompleted = false,
        newcount = false,
        lcounter = 0
	}
end

local function decrease_count(channel)
    -- if channel.bsd then
    --     -- TODO
    -- else
    channel.count = band((channel.count - 1), 0xFFFF)
    -- end
end

local function channel_update_state(channel)
    local mode  = band(channel.mode, 3)
    if channel.incomplete or (mode == 0) or (channel.state == 0) then
        channel.incomplete = false
        if mode == 1 then
            channel.state = 5
        else
            channel.state = 1
        end
    end
end

local function channel_update_count(channel)
    if channel.reload > 0 then
        channel.count = channel.reload
    else
        channel.count = 0x10000
    end

    if band(channel.reload, 1) >= 1 then
        channel.newcount = true
    else
        channel.newcount = false
    end

    if band(channel.write_mode, 0x80) == 0x80 then
        channel.incomplete = true
    else
        channel.incomplete = false
    end
end

local function channel_update(self, channel_num)
    local ch = self.channels[channel_num]
    if band(ch.state, 0x03) == 0x01 then
        channel_update_count(ch)
        ch.state = ch.state + 1
    else
        if ch.mode == 0 then -- Interrupt On Terminal Count
            if ch.state == 2 then
                if ch.gate and (ch.count >= 1) then
                    decrease_count(ch)
                    if ch.count < 1 then
                        ch.state = 3
                    end
                end
            elseif ch.state == 3 then
                decrease_count(ch)
            end
        elseif ch.mode == 1 then -- Hardware Re-triggerable One-shot
            if ch.state == 2 then
                if ch.count >= 1 then
                    decrease_count(ch)
                    if ch.count < 1 then
                        ch.state = 3
                    end
                end
            elseif (ch.state == 3) or (ch.state == 6) then
                decrease_count(ch)
            end
        elseif (ch.mode == 2) or (ch.mode == 6) then -- Rate Generator
            if ch.state == 3 then
                channel_update_count(ch)
                ch.state = 2
            elseif ch.state == 2 then
                if ch.gate and (ch.count >= 2) then
                    decrease_count(ch)
                    if ch.count < 2 then
                        ch.state = 3
                    end
                end
            end
        elseif (ch.mode == 3) or (ch.mode == 7) then -- Square Wave Generator
            if ch.state == 2 then
                if ch.gate == false then
                    return
                elseif ch.count >= 0 then
                    if ch.newcount then
                        ch.count = ch.count - 1
                    else
                        ch.count = ch.count - 2
                    end

                    if ch.count < 0 then
                        channel_update_count(ch)
                        ch.state = 3
                    elseif ch.newcount then
                        ch.newcount = false
                    end
                end
            elseif ch.state == 3 then
                if ch.gate == false then
                    return
                elseif ch.count >= 0 then
                    if ch.newcount then
                        ch.count = ch.count - 3
                    else
                        ch.count = ch.count - 2
                    end
                    if ch.count < 0 then
                        channel_update_count(ch)
                        ch.state = 2
                    elseif ch.newcount then
                        ch.newcount = false
                    end
                end
            end
        elseif (ch.mode == 4) or (ch.mode == 5) then -- Hardware Triggered Strobe / Software Triggered Strobe
            if ch.gate and (ch.mode == 5) then
                if (ch.state == 0) or (ch.state == 6) then
                    decrease_count(ch)
                elseif ch.state == 2 then
                    if ch.count >= 1 then
                        decrease_count(ch)
                        if ch.count < 1 then
                            ch.state = 3
                        end
                    end
                elseif ch.state == 3 then
                    ch.state = 0
                end
            end
        end
    end

    -- if channel_num == 0 then
    --     -- self.cpu:emit_interrupt(0x08, false)
    -- end
end

local function pit_tick(self)
    for x = 1, 300, 1 do
        for i = 0, 2, 1 do
            local channel = self.channels[i]
            if channel.latch then
                channel_update_state(channel)
                channel.latch = false
            elseif (channel.latch == false) then
                channel_update(self, i)
            end
        end
    end
end

local function port_init(self, channel)
    local ch = self.channels[channel]
    return function (cpu, port, val)
        if val then -- Write
            if ch.write_mode == 1 then
                ch.reload = bor(band(ch.reload, 0xFF00), val)
            elseif ch.write_mode == 2 then
                ch.reload = bor(band(ch.reload, 0x00FF), lshift(val, 8))
            elseif (ch.write_mode == 3) or (ch.write_mode == 0x83) then
                if band(ch.write_mode, 0x80) then
                    ch.reload = bor(band(ch.reload, 0xFF), lshift(val, 8))
                else
                    ch.reload = bor(band(ch.reload, 0xFF00), val)
                end

                if band(ch.write_mode, 0x80) then
                    ch.write_mode = band(ch.write_mode, -129)
                else
                    ch.write_mode = bor(ch.write_mode, 0x80)
                end
            end
            ch.latch = true
        else -- Read
            if ch.latched > 0 then
                local ret = 0xFF
                if band(ch.read_mode, 0x80) > 0 then
                    ret = rshift(ch.lcounter, 8)
                    ch.read_mode = band(ch.read_mode, bnot(0x80))
                else
                    ret = ch.lcounter
                    ch.read_mode = bor(ch.read_mode, 0x80)
                end

                ch.latched = ch.latched - 1
                return ret
            else
                local count  = 0
                if ch.state == 1 then
                    count = ch.reload
                else
                    count = ch.count
                end

                if (ch.read_mode == 0) or (ch.read_mode == 0x80) then
                    return 0x00
                elseif ch.read_mode == 1 then
                    return band(count, 0xFF)
                elseif ch.read_mode == 2 then
                    return band(rshift(count, 8), 0xFF)
                elseif (ch.read_mode == 3) or (ch.read_mode == 0x83) then
                    self.access_lohi = not self.access_lohi
                    if band(ch.wm, 0x80) == 0x80 then
                        return bnot(band(count, 0xFF))
                    else
                        if band(ch.read_mode, 0x80) == 0x80 then
                            return band(rshift(count, 8), 0xFF)
                        end
                        return band(count, 0xFF)
                    end

                    if band(ch.read_mode, 0x80) == 0x80 then
                        ch.read_mode = band(channel.read_mode, bnot(0x80))
                    else
                        ch.read_mode = bor(channel.read_mode, 0x80)
                    end
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
            if channel_num < 3 then
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
                    -- logger:debug("i8253: Channel %d: Access mode = %d, Latched Counter = %d", channel_num, channel.read_mode, channel.lcounter)
                else
                    channel.read_mode = band(rshift(val, 4), 3)
                    channel.write_mode = channel.read_mode
                    channel.mode = band(rshift(val, 1), 7)
                    channel.bsd = (band(val, 1) == 1)
                    channel.state = 0
                    if channel.latched > 0 then
                        channel.lcounter = channel.lcounter - 1
                    end
                    logger:debug("i8253: Channel %d: Setting: Access mode = %d, Operating mode = %d, BSD = %s", channel_num, channel.read_mode, channel.mode, channel.bsd)
                end
            end
        else
            return 0x00
        end
    end
end

local pit = {}

function pit.new(cpu)
    local self = {
        cpu = cpu,
        update = pit_tick,
        channels = {},
    }

    create_channel(self, 0) -- IRQ0
    create_channel(self, 1) -- DRAM
    create_channel(self, 2) -- PC Speaker

    cpu:port_set(0x40, port_init(self, 0)) -- Channel data 0
    cpu:port_set(0x41, port_init(self, 1)) -- Channel data 1
    cpu:port_set(0x42, port_init(self, 2)) -- Channel data 2
    cpu:port_set(0x43, port_43(self)) -- Mode switcher

    self.channels[0].gate = true
    self.channels[1].gate = true
    self.channels[2].gate = false
    return self
end

return pit