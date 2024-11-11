-- PIT 8253 (https://wiki.osdev.org/Programmable_Interval_Timer)
-- FIXME
-- REWRITE ME PLS
-- local logger = require("retro_computers:logger")

local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor
local freq = 1.193182
local channels = {}
local curr_t = 0
local last_tick = 0
local access_lohi = false

-- Channel modes
-- 0 - Interrupt On Terminal Count (0_0 chego kakie terminali)
-- 1 - Hardware Re-triggerable One-shot (-_-)
-- 2 - Rate Generator
-- 3 - Square Wave Generator
-- 4 - Software Triggered Strobe
-- 5 - Hardware Triggered Strobe
-- Access modes
-- 0 - Latch count value command
-- 1 - lobyte only
-- 2 - hibyte only
-- 3 - lobyte/hibyte
local function init_channel(channel)
	channels[channel] = {
		mode=3,
		accessmode=3,
		reload=0x10000,
		reload_set_lo=false,
		reload_set_hi=false,
		bcd=false,
		paused=false,
		count=0
	}
end

-- local function decrease_count(channel)
--     if channel.bsd then
--         -- TODO
--     else
--         channel.count = band((channel.count - 1), 0xFFFF)
--     end
-- end

local function pit_tick(self)
	local osc_count = math.floor((curr_t - last_tick) * 1000000 * freq)
	last_tick = curr_t
	for c = 0, 2, 1 do
		local ch=channels[c]
        local trig=0

		local ch_ready = (not ch.paused) and ch.reload_set_lo and ch.reload_set_hi
		if ch.reload == 0 then
			ch.reload = 0x10000
		end
		if (ch.mode == 0 or ch.mode == 4) and ch_ready then
			if ch.count == 0 then ch.count = ch.reload end
			ch.count = ch.count - osc_count
			if ch.count < 1 then
				trig = 1
				ch.count = 0
				ch.paused = true
			end
		elseif (ch.mode == 2 or ch.mode == 3 or ch.mode == 6 or ch.mode == 7) and ch_ready then
			ch.count = ch.count - osc_count
			while ch.count < 0 do
				ch.count = ch.count + ch.reload
				trig = trig + 1
			end
		end
		for i=1,trig do
			if c == 1 then
                -- doirq(0)
				self.cpu:emit_interrupt(0x08, false)
			end
		end
	end
end

local function pit_counter(channel)
    local ch = channels[channel]
    return function (cpu, port, val)
        if val then -- Write
            if ch.accessmode == 1 then
                ch.reload = bor(band(ch.reload, 0xFF00), val)
                ch.reload_set_lo = true
            elseif ch.accessmode == 2 then
                ch.reload = bor(band(ch.reload, 0xFF), lshift(val, 8))
                ch.reload_set_hi = true
            elseif ch.accessmode == 3 then
                access_lohi = not access_lohi
                if access_lohi then
                    ch.reload = bor(band(ch.reload, 0xFF00), val)
                    ch.reload_set_lo = true
                    ch.reload_set_hi = false
                else
                    ch.reload = bor(band(ch.reload, 0xFF), lshift(val, 8))
                    ch.reload_set_hi = true
                end
            end
        else -- Read
            if (ch.accessmode == 3) or (ch.accessmode == 0) then
                access_lohi = not access_lohi
                if access_lohi then
                    return band(ch.count, 0xFF)
                else
                    return band(rshift(ch.count, 8), 0xFF)
                end
            elseif ch.accessmode == 1 then
                return band(ch.count, 0xFF)
            elseif ch.accessmode == 2 then
                return band(rshift(ch.count, 8), 0xFF)
            elseif ch.accessmode == 0 then
                return 0x00 -- TODO
            end
        end
    end
end

local function port_43(cpu, cond, val)
    if val then
        local channel = channels[rshift(val, 6)]
        if channel then
            channel.accessmode = band(rshift(val, 4), 3)
            channel.mode = band(rshift(val, 1), 7)
            channel.bsd = band(val, 1)
            -- logger:debug("i8253: Counter %d setting: accesmode=%d, mode=%d, bsd=%d", rshift(val, 6), channel.accessmode, channel.mode, channel.bsd)
        else
            -- logger:warning("i8253: Unknown channel %d", channel)
        end
    else
        return 0xFF
    end
end

local pit = {}

function pit.new(cpu)
    local instance = {
        cpu = cpu,
        update = pit_tick
    }

    init_channel(0) -- IRQ0
    init_channel(1) -- DRAM
    init_channel(2) -- PC Speaker

    cpu:port_set(0x40, pit_counter(0)) -- Channel data 0
    cpu:port_set(0x41, pit_counter(1)) -- Channel data 1
    cpu:port_set(0x42, pit_counter(2)) -- Channel data 2
    cpu:port_set(0x43, port_43) -- Mode switcher

    channels[1].reload_set_lo = true
    channels[1].reload_set_hi = true

    return instance
end

return pit