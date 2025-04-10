-- DMA
-- Channels:
-- 0 - DRAM refresh
-- 1 - Free
-- 2 - Floppy Disk Controller
-- 3 - Free

local logger = require("retro_computers:logger")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local function reset_channel(self, channel_num)
    local channel = self.channels[channel_num]

    channel.curr_addr = 0
    channel.base_addr = 0
    channel.base_count = 0
    channel.curr_count = 0
    channel.mode = 0
    channel.page = 0
end

local function init_channel(self, channel)
    self.channels[channel] = {
        curr_addr = 0,
        base_addr = 0,
        base_count = 0,
        curr_count = 0,
        mode = 0,
        page = 0
    }
end

local function channel_read(self, channel_num)
    local channel = self.channels[channel_num]
    local channel_mask = lshift(1, channel_num)

    if not self.enabled then
        return 0x200
    end

    if band(self.mask_reg, channel_mask) ~= 0 then
        return 0x200
    end

    if band(channel.mode, 0xC) ~= 0x08 then
        return 0x200
    end

    local temp = self.memory[channel.curr_addr]

    if band(channel.mode, 0x20) ~= 0 then
        channel.curr_addr = bor(band(channel.curr_addr, 0xFF0000), band(channel.curr_addr - 1, 0xFFFF))
    else
        channel.curr_addr = bor(band(channel.curr_addr, 0xFF0000), band(channel.curr_addr + 1, 0xFFFF))
    end

    self.request_reg = bor(self.request_reg, channel_mask)
    channel.curr_count = channel.curr_count - 1

    if channel.curr_count < 0 then
        temp = bor(temp, 0x100)

        if band(channel.mode, 0x10) ~= 0 then
            channel.curr_count = channel.base_count
            channel.curr_addr = channel.base_addr
        else
            self.mask_reg = bor(self.mask_reg, channel_mask)
        end

        self.status_reg = bor(self.status_reg, channel_mask)
    end

    return temp
end

local function channel_write(self, channel_num, val)
    local channel = self.channels[channel_num]
    local channel_mask = lshift(1, channel_num)

    if not self.enabled then
        return 0x200
    end

    if band(self.mask_reg, channel_mask) ~= 0 then
        return 0x200
    end

    if band(channel.mode, 0xC) ~= 0x04 then
        return 0x200
    end

    self.memory[channel.curr_addr] = band(val, 0xFF)

    if band(channel.mode, 0x20) ~= 0 then
        channel.curr_addr = bor(band(channel.curr_addr, 0xFF0000), band(channel.curr_addr - 1, 0xFFFF))
    else
        channel.curr_addr = bor(band(channel.curr_addr, 0xFF0000), band(channel.curr_addr + 1, 0xFFFF))
    end

    self.request_reg = bor(self.request_reg, channel_mask)
    channel.curr_count = channel.curr_count - 1

    if channel.curr_count < 0 then
        if band(channel.mode, 0x10) ~= 0 then
            channel.curr_count = channel.base_count
            channel.curr_addr = channel.base_addr
        else
            self.mask_reg = bor(self.mask_reg, channel_mask)
        end

        self.status_reg = bor(self.status_reg, channel_mask)
    end

    if band(self.mask_reg, channel_mask) ~= 0 then
        return 0x100
    end

    return 0
end

local function block_transfer(self, channel_num)
    local channel = self.channels[channel_num]

    for i = 0, channel.base_count, 1 do
        local mode = band(channel.mode, 0x8C)

        if mode == 0x84 then
            channel_write(self, channel_num, self.buffer[i])
        elseif mode == 0x88 then
            self.buffer[i] = channel_read(self, channel_num)
        end
    end
end

local function request_service(self, channel_num)
    self.request_reg = bor(self.request_reg, lshift(1, channel_num))
end

local function clear_service(self, channel_num)
    self.request_reg = bor(self.request_reg, bnot(lshift(1, channel_num)))
end

-- Ports
local function port_address_register(self, channel_num)
    local channel = self.channels[channel_num]

    return function(cpu, port, val)
        if val then
            self.flipflop = not self.flipflop

            if self.flipflop then
                channel.base_addr = bor(band(channel.base_addr, 0xFFFF00), val)
            else
                channel.base_addr = bor(band(channel.base_addr, 0xFF00FF), lshift(val, 8))
            end

            channel.curr_addr = channel.base_addr
        else
            self.flipflop = not self.flipflop

            if self.flipflop then
                return band(channel.curr_addr, 0xFF)
            else
                return band(rshift(channel.curr_addr, 8), 0xFF)
            end
        end
    end
end

local function port_count_register(self, channel_num)
    local channel = self.channels[channel_num]

    return function (cpu, port, val)
        if val then
            self.flipflop = not self.flipflop

            if self.flipflop then
                channel.base_count = bor(band(channel.base_count, 0xFF00), val)
            else
                channel.base_count = bor(band(channel.base_count, 0x00FF), lshift(val, 8))
            end

            channel.curr_count = channel.base_count
        else
            self.flipflop = not self.flipflop

            if self.flipflop then
                return band(channel.curr_count, 0xFF)
            else
                return band(rshift(channel.curr_count, 8), 0xFF)
            end
        end
    end
end

local function port_page_register(self, channel_num)
    local channel = self.channels[channel_num]

    return function(cpu, port, val)
        if val then
            channel.page = band(val, 0xF)

            channel.base_addr = bor(band(channel.base_addr, 0xFFFF), lshift(channel.page, 16))
            channel.curr_addr = bor(band(channel.curr_addr, 0xFFFF), lshift(channel.page, 16))
        else
            return channel.page
        end
    end
end

local function port_08(self) -- Command / Status Register
    return function(cpu, port, val)
        if val then
            self.enabled = band(val, 0x04) == 0
        else
            local old_status = self.status_reg
            self.status_reg = band(self.status_reg, bnot(0x0F))
            return bor(band(old_status, 0xF), lshift(self.request_reg, 4))
        end
    end
end

local function port_09(self) -- Request Register
    return function(cpu, port, val)
        if val then
            local channel_num = band(val, 0x03)
            local channel_mask = lshift(1, channel_num)

            if band(val, 0x04) ~= 0 then
                self.request_reg = bor(self.request_reg, channel_mask)
                block_transfer(self, channel_num)
            else
                self.request_reg = band(self.request_reg, bnot(channel_mask))
            end
        else
            return 0xFF
        end
    end
end

local function port_0A(self) -- Single Mask Register
    return function(cpu, port, val)
        if val then
            local channel_num = band(val, 0x03)
            local channel_mask = lshift(1, channel_num)

            if band(val, 0x04) ~= 0 then
                self.mask_reg = bor(self.mask_reg, channel_mask)
            else
                self.mask_reg = band(self.mask_reg, bnot(channel_mask))
            end
        else
            return 0xFF
        end
    end
end

local function port_0B(self) -- Mode Register
    return function(cpu, port, val)
        if val then
            local channel_num = band(val, 0x03)
            local channel = self.channels[channel_num]

            channel.mode = val
        else
            return 0xFF
        end
    end
end

local function port_0C(self) -- Clear Flip-Flop Register
    return function(cpu, port, val)
        if val then
            self.flipflop = false
        else
            return 0xFF
        end
    end
end

local function port_0D(self) -- Master Reset Register / Temporary Register
    return function(cpu, port, val)
        if val then
            self.flipflop = false
            self.mask_reg = bor(self.mask_reg, 0x0F)
            self.request_reg = band(self.request_reg, bnot(0x0F))
        else
            return 0x00
        end
    end
end

local function port_0E(self) -- Clear Mask Register
    return function(cpu, port, val)
        if val then
            self.mask_reg = band(self.mask_reg, 0xF0)
        else
            return 0xFF
        end
    end
end

local function port_0F(self) -- Mask Register
    return function(cpu, port, val)
        if val then
            self.mask_reg = bor(band(self.mask_reg, 0xF0), band(val, 0xF))
        else
            return 0xFF
        end
    end
end

local function reset(self)
    self.master_reg = 0
    self.request_reg = 0
    self.mask_reg = 0
    self.status_reg = 0
    self.enabled = true
    self.flipflop = false

    reset_channel(self, 0)
    reset_channel(self, 1)
    reset_channel(self, 2)
    reset_channel(self, 3)
end

local dma = {}

function dma.new(cpu, memory)
    local self = {
        memory = memory,
        buffer = {},
        channels = {},
        master_reg = 0,
        request_reg = 0,
        status_reg = 0,
        mask_reg = 0,
        flipflop = false,
        enabled = true,
        reset = reset,
        channel_read = channel_read,
        channel_write = channel_write,
        request_service = request_service,
        clear_service = clear_service,
    }

    init_channel(self, 0)
    init_channel(self, 1)
    init_channel(self, 2)
    init_channel(self, 3)

    -- Address registers
    cpu:set_port(0x00, port_address_register(self, 0))
    cpu:set_port(0x02, port_address_register(self, 1))
    cpu:set_port(0x04, port_address_register(self, 2))
    cpu:set_port(0x06, port_address_register(self, 3))

    -- Count reggisters
    cpu:set_port(0x01, port_count_register(self, 0))
    cpu:set_port(0x03, port_count_register(self, 1))
    cpu:set_port(0x05, port_count_register(self, 2))
    cpu:set_port(0x07, port_count_register(self, 3))

    -- Page registers
    cpu:set_port(0x81, port_page_register(self, 2))
    cpu:set_port(0x82, port_page_register(self, 3))
    cpu:set_port(0x83, port_page_register(self, 1))
    cpu:set_port(0x87, port_page_register(self, 0))

    cpu:set_port(0x08, port_08(self))
    cpu:set_port(0x09, port_09(self))
    cpu:set_port(0x0A, port_0A(self))
    cpu:set_port(0x0B, port_0B(self))
    cpu:set_port(0x0C, port_0C(self))
    cpu:set_port(0x0D, port_0D(self))
    cpu:set_port(0x0E, port_0E(self))
    cpu:set_port(0x0F, port_0F(self))

    -- Initilize buffer
    for i = 0, 65535, 1 do
        self.buffer[i] = 0x00
    end

    return self
end

return dma