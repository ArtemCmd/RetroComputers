local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor
local logger = require("dave_logger:logger")("RetroComputers")
local filesystem = require("retro_computers:emulator/filesystem")
local common = require("retro_computers:emulator/machine/machine")

local machine = {}

local MONITOR_ROM = filesystem.open("retro_computers:modules/emulator/roms/okean240/MONITOR.BIN", "r", true):read_bytes()
local OS_ROM = filesystem.open("retro_computers:modules/emulator/roms/okean240/CPM80.BIN", "r", true):read_bytes()

local TPS = 20
local CPU_FREQ = 2400000
local CYCLES_PER_TICK = CPU_FREQ / TPS

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

local function port_C1_out(self)
    return function(cpu, port, val)
        set_memory_map(self, val)
    end
end

local function start(self)
    if not self.enabled then
        self:reset()

        set_memory_map(self, MEMORY_MAP_INIT)

        write_memory_block(self.devices.memory.ram_os, 0x2000, MONITOR_ROM)
        write_memory_block(self.devices.memory.ram_os, 0x0000, OS_ROM)

        self.enabled = true
    end
end

local function stop(self)
    if self.enabled then
        self.enabled = false
        self:reset()
    end
end

local function reset(self)
    for _, device in pairs(self.devices) do
        if device.reset then
            device:reset()
        end
    end
end

local function update(self)
    if self.enabled then
        self.devices.videocard:update()
        self.devices.pic:update()
        self.devices.pit:update()
        self.devices.keyboard:update()
        self.devices.cpu.cycles = 0

        while (self.devices.cpu.cycles < CYCLES_PER_TICK) and (not self.devices.cpu.halted) do
            self.devices.cpu:step()
        end
    end
end

local function memory_read8(self, addr)
    local map = self.mappings[rshift(addr, 14)]

    if map then
       return map[band(addr, 0x3FFF)]
    end

    return 0xFF
end

local function memory_write8(self, addr, val)
    local map = self.mappings[rshift(addr, 14)]

    if map then
       map[band(addr, 0x3FFF)] = val
    end
end

function machine.new(machine_id)
    local self = {
        devices = {},
        enabled = false,
        is_focused = false,
        id = machine_id,
        start = start,
        stop = stop,
        update = update,
        reset = reset
    }

    setmetatable(self, common)

    self.devices.memory = require("retro_computers:emulator/hardware/memory").new(128 * 1024)
    self.devices.cpu = require("retro_computers:emulator/hardware/cpu/i8080").new(self.devices.memory)
    self.devices.pic = require("retro_computers:emulator/hardware/i8259").new(self.devices.cpu, 0x80)
    self.devices.pit = require("retro_computers:emulator/hardware/i8253").new(self.devices.cpu, 0x60)
    self.devices.screen = require("retro_computers:emulator/screen").new()
    self.devices.pc_speaker = require("retro_computers:emulator/hardware/sound/pc_speaker").new(self.devices.pit)
    self.devices.videocard = require("retro_computers:emulator/hardware/video/okean").new(self.devices.cpu, self.devices.screen)
    self.devices.keyboard = require("retro_computers:emulator/hardware/keyboard/keyboard_okean").new(self.devices.cpu, self.devices.pic, self)

    -- Setup memory
    local memory = self.devices.memory

    memory.mappings = {}
    memory.ram_1 = create_memory_block()
    memory.ram_2 = create_memory_block()
    memory.ram_3 = create_memory_block()
    memory.ram_ext_1 = create_memory_block()
    memory.ram_ext_2 = create_memory_block()
    memory.ram_ext_3 = create_memory_block()
    memory.ram_os = create_memory_block()

    memory.read8 = memory_read8
    memory.write8 = memory_write8


    -- Setup CPU
    local cpu = self.devices.cpu

    cpu:get_io():set_port_out(0xC1, port_C1_out(self))
    cpu:set_reset_vector(0xE000)

    -- Setup PIT
    self.devices.pit:set_channel_out_handler(0, function(out, old_out)
        if out and (not old_out) then
            self.devices.pic:request_interrupt(4)
        end

        if not out then
            self.devices.pic:clear_interrupt(4)
        end
    end)

    return self
end

return machine
