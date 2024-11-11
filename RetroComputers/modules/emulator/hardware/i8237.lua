-- DMA (https://www.lo-tech.co.uk/wiki/8237_DMA_Controller)
-- FIXME
-- local logger = require("retro_computers:logger")

local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor
local channels = {}
local flipflop = false
local mask = 0x00
local master_reg = 0

local function init_channel(channel)
    channels[channel] = {
        curr_addr = 0,
        base_addr = 0,
        mode = 0,
        count = 0,
        cycles = 0,
        page = 0
    }
end

local function port_address_register(channel)
    local ch = channels[channel]
    return function (cpu, port, val)
        if val then
            if flipflop then
                ch.base_addr = bor(band(ch.base_addrm, 0xffffff00), val)
            else
                ch.base_addr = bor(band(ch.base_addrm, 0xffff00ff), lshift(val, 8))
            end
            ch.curr_addr = ch.base_addr
            -- logger:debug("i8237: Set address register to %d", ch.curr_addr)
        else
            if flipflop then
                return band(ch.curr_addr, 0xFF)
            else
                return band(rshift(ch.curr_addr, 8), 0xFF)
            end
        end
    end
end

local function port_count_register(channel)
    local ch = channels[channel]
    return function (cpu, port, val)
        if val then
            ch.base_addr = bor(band(ch.base_addrm, 0xffffff00), val)
            ch.curr_addr = ch.base_addr
            -- logger:debug("i8237: Set address register to %d", ch.curr_addr)
        else
            return band(ch.curr_addr, 0xFF)
        end
    end
end

local function port_0B(cpu, port, val)
    if val then
        channels[band(val, 3)].mode = val
    else
        return 0xFF
    end
end

local function port_0C(cpu, port, val)
    if val then
        flipflop = false
    else
        return 0xFF
    end
end

local function port_0D(cpu, port, val)
    if val then
        flipflop = false
        master_reg = bor(master_reg, 0xF)
    else
        return 0xFF
    end
end

local function port_0E(cpu, port, val)
    if val then
        mask = band(mask, 0xF0)
    else
        return 0xFF
    end
end

local function port_0F(cpu, port, val)
    if val then
        mask = bor(band(mask, 0xF0), band(val, 0xF))
    else
        return 0xFF
    end
end

local function port_81(cpu, port, val)
    local channel = channels[2]
    channel.page = band(val, 0xF)
    channel.base_addr = bor(band(channel.base_addr, 0xFFFF), lshift(channel.page, 16))
    channel.curr_addr = bor(band(channel.curr_addr, 0xFFFF), lshift(channel.page, 16))
end

local function port_82(cpu, port, val)
    local channel = channels[2]
    channel.page = band(val, 0xF)
    channel.base_addr = bor(band(channel.base_addr, 0xFFFF), lshift(channel.page, 16))
    channel.curr_addr = bor(band(channel.curr_addr, 0xFFFF), lshift(channel.page, 16))
end

local function port_83(cpu, port, val)
    local channel = channels[1]
    channel.page = band(val, 0xF)
    channel.base_addr = bor(band(channel.base_addr, 0xFFFF), lshift(channel.page, 16))
    channel.curr_addr = bor(band(channel.curr_addr, 0xFFFF), lshift(channel.page, 16))
end

local dma = {}

function dma.new(cpu)
    -- DMA channels
    -- 0 - DRAM refresh
    -- 1 - Free
    -- 2 - Floppy Disk Controller
    -- 3 - Free
    -- 4 - Cascading
    -- 5 - Free
    -- 6 - Free
    -- 7 - Free
    init_channel(0)
    init_channel(1)
    init_channel(2)
    init_channel(3)
    init_channel(4)
    init_channel(5)
    init_channel(6)
    init_channel(7)

    cpu:port_set(port_address_register(0))
    cpu:port_set(port_address_register(2))
    cpu:port_set(port_address_register(4))
    cpu:port_set(port_address_register(6))

    cpu:port_set(port_count_register(1))
    cpu:port_set(port_count_register(3))
    cpu:port_set(port_count_register(5))
    cpu:port_set(port_count_register(7))

    cpu:port_set(0x81, port_81)
    cpu:port_set(0x82, port_82)
    cpu:port_set(0x83, port_83)

    cpu:port_set(0x0B, port_0B) -- Mode Register
    cpu:port_set(0x0C, port_0C) -- Clear Flip-Flop Register
    cpu:port_set(0x0D, port_0D) -- Master Reset Register
    cpu:port_set(0x0E, port_0E) -- Master Enable Register
    cpu:port_set(0x0F, port_0F) -- Master Mask Register
end

return dma