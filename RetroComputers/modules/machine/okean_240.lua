local logger = require("dave_logger:logger")("RetroComputers")
local common = require("retro_computers:machine/machine")

local emu_api = require("emulator:api/v1/api")
local device_manager = emu_api.device_manager

local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local machine = {}

local BIOS_ROM = file.read_bytes("retro_computers:roms/okean240/bios.bin", false)

local TPS = 20
local CPU_FREQ = 2400000
local CYCLES_PER_TICK = CPU_FREQ / TPS

local MEMORY_MAP_SHIFT = 14
local MEMORY_MAP_MASK = 0x3FFF

local MEMORY_MAP_NORM = 0x00
local MEMORY_MAP_VIDEO1 = 0x01
local MEMORY_MAP_VIDEO = 0x10
local MEMORY_MAP_INIT = 0x20
local MEMORY_MAP_EXT_RAM_1 = 0x02
local MEMORY_MAP_EXT_RAM_2 = 0x03
local MEMORY_MAP_EXT_RAM_3 = 0x12

local memory_maps = {
    [MEMORY_MAP_INIT] = function(self)
        local mem = self.devices.memory

        mem.mappings[0] = mem.ram_os
        mem.mappings[1] = mem.ram_os
        mem.mappings[2] = mem.ram_os
        mem.mappings[3] = mem.ram_os
    end,
    [MEMORY_MAP_NORM] = function(self)
        local mem = self.devices.memory

        mem.mappings[0] = mem.ram_1
        mem.mappings[1] = mem.ram_2
        mem.mappings[2] = mem.ram_3
        mem.mappings[3] = mem.ram_os
    end,
    [MEMORY_MAP_VIDEO] = function(self)
        local mem = self.devices.memory

        mem.mappings[0] = mem.ram_1
        mem.mappings[1] = mem.ram_2
        mem.mappings[2] = mem.ram_3
        mem.mappings[3] = self.devices.videocard:get_vram()
    end,
    [MEMORY_MAP_VIDEO1] = function(self)
        local mem = self.devices.memory

        mem.mappings[0] = mem.ram_3
        mem.mappings[1] = self.devices.videocard:get_vram()
        mem.mappings[2] = mem.ram_3
        mem.mappings[3] = mem.ram_os
    end,
    [MEMORY_MAP_EXT_RAM_1] = function(self)
        local mem = self.devices.memory

        mem.mappings[0] = mem.ram_ext_1
        mem.mappings[1] = mem.ram_ext_2
        mem.mappings[2] = mem.ram_ext_3
        mem.mappings[3] = mem.ram_os
    end,
    [MEMORY_MAP_EXT_RAM_2] = function(self)
        local mem = self.devices.memory

        mem.mappings[0] = mem.ram_ext_3
        mem.mappings[1] = mem.ram_ext_4
        mem.mappings[2] = mem.ram_ext_3
        mem.mappings[3] = mem.ram_os
    end,
    [MEMORY_MAP_EXT_RAM_3] = function(self)
        local mem = self.devices.memory

        mem.mappings[0] = mem.ram_ext_3
        mem.mappings[1] = mem.ram_ext_4
        mem.mappings[2] = mem.ram_ext_3
        mem.mappings[3] = mem.ram_os
    end
}

local function set_memory_map(self, type)
    local map = memory_maps[band(type, 0x37)]

    if map then
        map(self)
    else
        logger:error("Okean240: Invalid memory map: 0x%02X", type)
        memory_maps[MEMORY_MAP_INIT](self)
    end
end

local function create_memory_block()
    local ram = {}

    for i = 0, 16383, 1 do
        ram[i] = 0x00
    end

    return ram
end

local function write_memory_block(ram, offset, data)
    for i = 0, #data - 1, 1 do
        ram[offset + i] = data[i + 1]
    end
end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- PPI 1
------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function port_b_read(self)
    return function(handler, val)
        return bor(
            lshift(self.devices.tdc:read_bit(0), 2),
            lshift(self.devices.tdc:get_high(), 3)
        )
    end
end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- PPI 2
------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function port_a_write(self)
    return function(handler, val)
        self.devices.videocard.vertical_offset = val
    end
end

local function port_b_write(self)
    return function(handler, val)
        set_memory_map(self, val)
    end
end

local function port_c_write(self)
    return function(handler, val)
        self.devices.videocard.horizontal_scroll = band(val, 0x07)
    end
end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- PPI 3
------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function ppi_3_port_b_write(self)
    return function(handler, val)
        self.devices.videocard:update_mode(val)
    end
end

local function ppi_3_port_c_write(self)
    return function(handler, val)
        self.devices.pc_speaker.enabled = band(val, 0x08) ~= 0
        self.devices.pc_speaker.gated = self.devices.pc_speaker.enabled
        self.devices.pit:set_channel_gate(2, self.devices.pc_speaker.gated)
        self.devices.pc_speaker:update()
    end
end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function start(self)
    if not self.enabled then
        self:reset()

        set_memory_map(self, MEMORY_MAP_INIT)
        write_memory_block(self.devices.memory.ram_os, 0x0000, BIOS_ROM)

        self.enabled = true
    end
end

local function stop(self)
    if self.enabled then
        self.enabled = false
        self:reset()
    end
end

local function update(self)
    if self.enabled then
        self.devices.cpu:execute(CYCLES_PER_TICK)
    end
end

local function memory_read8(self, addr)
    return self.mappings[rshift(addr, MEMORY_MAP_SHIFT)][band(addr, MEMORY_MAP_MASK)]
end

local function memory_write8(self, addr, val)
    self.mappings[rshift(addr, MEMORY_MAP_SHIFT)][band(addr, MEMORY_MAP_MASK)] = val
end

function machine.new(machine_id)
    local self = {
        devices = {},
        key_matrix = {},
        id = machine_id,
        target_time = 0,
        enabled = false,
        is_focused = false,
        start = start,
        stop = stop,
        update = update
    }

    setmetatable(self, common)

    self.devices.memory = device_manager.create("memory", 64 * 1024)
    self.devices.cpu = device_manager.create("i8080", self.devices.memory, 5)
    self.devices.pic = device_manager.create("i8259", self.devices.cpu, 0x80)
    self.devices.pit = device_manager.create("i8253", self.devices.cpu, 0x60)
    self.devices.screen = device_manager.create("screen")
    self.devices.videocard = device_manager.create("okean", self.devices.cpu, self.devices.screen)
    self.devices.keyboard = device_manager.create("keyboard_okean", self.devices.cpu, self.devices.pic, self)
    self.devices.pc_speaker = device_manager.create("pc_speaker", self.devices.pit, self.devices.cpu)
    self.devices.ppi_1 = device_manager.create("i8255", self.devices.cpu, 0x40)
    self.devices.ppi_2 = device_manager.create("i8255", self.devices.cpu, 0xC0)
    self.devices.ppi_3 = device_manager.create("i8255", self.devices.cpu, 0xE0)

    -- Setup memory
    local memory = self.devices.memory

    memory.ram_1 = create_memory_block()
    memory.ram_2 = create_memory_block()
    memory.ram_3 = create_memory_block()
    memory.ram_ext_1 = create_memory_block()
    memory.ram_ext_2 = create_memory_block()
    memory.ram_ext_3 = create_memory_block()
    memory.ram_os = create_memory_block()
    memory.mappings = {
        [0] = memory.ram_os,
        [1] = memory.ram_os,
        [2] = memory.ram_os,
        [3] = memory.ram_os
    }

    memory.read8 = memory_read8
    memory.write8 = memory_write8

    -- Setup PPI DD17
    self.devices.ppi_2:set_handler({
        port_a_write = port_a_write(self),
        port_b_write = port_b_write(self),
        port_c_write = port_c_write(self)
    })

    -- Setup PPI DD67
    self.devices.ppi_3:set_handler({
        port_b_write = ppi_3_port_b_write(self),
        port_c_write = ppi_3_port_c_write(self)
    })

    -- Setup CPU
    local cpu = self.devices.cpu

    cpu:set_reset_vector(0xE000)
    cpu:get_scheduler().USEC = CPU_FREQ / 1000000

    -- Setup PIT
    self.devices.pit:set_channel_out_handler(0, function(out, old_out)
        if out and (not old_out) then
            self.devices.pic:request_interrupt(4)
        end

        if not out then
            self.devices.pic:clear_interrupt(4)
        end
    end)

    self.devices.keyboard:set_clock()
    self.devices.pc_speaker:set_clock()
    self.devices.pit:set_clock(12)
    self.devices.videocard:set_clock()

    return self
end

return machine
