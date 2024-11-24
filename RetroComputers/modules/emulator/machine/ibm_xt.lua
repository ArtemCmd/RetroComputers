local logger = require("retro_computers:logger")
local vmmanager = require("retro_computers:emulator/vmmanager")
local drive_manager = require("retro_computers:emulator/drive_manager")

local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor
local ram_640k = {}
local ram_rom = {}

local function get_save_path(id)
    local path =  "world:data/retro_computers/machines/"
    if file.exists("world:data") then
        if not file.exists(path .. id) then
            file.mkdir(path .. id)
        end
    end
    return path .. id .. "/"
end

local RAM = {}

function RAM.new(machine)
    local instance = {}
    setmetatable(instance, {
        __index = function(t, key)
            if (key < 0xA0000) then
                return ram_640k[key + 1] or 0
            elseif (key < 0xC0000) then
                return machine.components.videocard.vram_read(key)
            elseif (key >= 0xF0000 and key < 0x100000) then
                return ram_rom[band(key, 0xFFFFF) - 0xF0000] or 0xFF
            else
                return 0xFF
            end
        end,
        __newindex = function(t, key, value)
            if (key < 0xA0000) then
                ram_640k[key + 1] = value
            elseif (key < 0xC0000) then
                machine.components.videocard.vram_write(key, value)
            elseif (key >= 0xF0000 and key < 0x100000) then
                ram_rom[band(key, 0xFFFFF) - 0xF0000] = value
            end
        end
    })
    rawset(instance, "r16", function(ram, key)
        if key < 0x9FFFF then
            return bor((ram_640k[key + 1] or 0), lshift((ram_640k[key + 2] or 0), 8))
        else
            return bor(ram[key], lshift(ram[key + 1], 8))
        end
    end)
    rawset(instance, "w16", function(ram, key, value)
        if key < 0x9FFFF then
            ram_640k[key + 1] = band(value, 0xFF)
            ram_640k[key + 2] = rshift(value, 8)
        else
            ram[key] = band(value, 0xFF)
            ram[key + 1] = rshift(value, 8)
        end
    end)

    rawset(instance, "w32", function(ram, key, value)
        ram[key] = band(value, 0xFF)
        ram[key + 1] = band(rshift(value, 8), 0xFF)
        ram[key + 2] = band(rshift(value, 16), 0xFF)
        ram[key + 3] = rshift(value, 24)
    end)
    rawset(instance, "r32", function(ram, key)
        return bor(bor(bor(ram[key], lshift(ram[key + 1], 8)), lshift(ram[key + 2], 16)), lshift(ram[key + 3], 32))
    end)
    return instance
end

local cpu = require("retro_computers:emulator/hardware/processors/i8086")
local pit = require("retro_computers:emulator/hardware/i8253")
local pic = require("retro_computers:emulator/hardware/i8259")
local rtc = require("retro_computers:emulator/hardware/rtc")
local cga = require("retro_computers:emulator/hardware/videocards/cga")
local disks = require("retro_computers:emulator/disks")
local keyboard = require("retro_computers:emulator/hardware/keyboards/keyboard_xt")
local serial = require("retro_computers:emulator/serial")
local dma = require("retro_computers:emulator/hardware/i8237")
-- local fdc = require("retro_computers:emulator/hardware/floppys/fdc")
local printer = require("retro_computers:emulator/printer")
local lpt = require("retro_computers:emulator/lpt")

-- BIOS 
local function int_11(cpu)
    cpu.regs[1] = cpu.memory:r16(0x410)
    return true
end

local function int_12(cpu)
	cpu.regs[1] = cpu.memory:r16(0x413)
	return true
end

local function int_15(cpu, ax,ah,al)
    if ah == 0x53 then -- APM
        if al == 0x00 then
            cpu.regs[1] = bor(0x01, rshift(ah, 8))
            cpu.regs[1] = bor(0x000, band(cpu.regs[1], 0xFF))
            cpu.regs[3] = bor(0x504, band(cpu.regs[3], 0xFF))
            cpu.regs[2] = 0
            return true
        elseif al == 0x01 then
            cpu:set_flag(1)
            return true
        elseif al == 0x07 then
            local id = cpu.regs[4]
            local status = cpu.regs[2]
            logger:debug("APM Setting device %s to %s", id, status)
            if id == 0x0001 then
                if status == 0x0003 then
                    local machine = vmmanager.get_machine(1)
                    machine:shutdown()
                end
            end
            cpu:set_flag(1)
            return true
        elseif al == 0x08 then
            local version = cpu.regs[4]
            local status = cpu.regs[2]
            logger:debug("APM Setting Version: %s, %s", status, version)
            cpu:set_flag(1)
            return true
        end
    end
    logger:warning("Unknown interrupt: 15h %02X", ah)
    cpu.regs[1] = bor(0x8600, band(cpu.regs[1], 0xFF))
    cpu:set_flag(0)
	return true
end

local machine = {}
local floppy_to_load = {}

local function insert_floppy(floppy, id)
    floppy_to_load[id] = floppy
end

local function start(self)
    if not self.enebled then
        logger:info("IBM XT: Starting")

        self.components.cpu.flags = 0x0202
        -- BDA 
        local equipment = bor(0x0061, lshift(1, 6))
        self.components.cpu.memory:w16(0x410, equipment)
        self.components.cpu.memory:w16(0x413, 640) -- Memory size
        self.components.cpu.memory[0x400] = 0xFF
        self.components.cpu.memory[0x408] = 0xFF

        self.components.cpu:register_interrupt_handler(0x11, int_11)
        self.components.cpu:register_interrupt_handler(0x12, int_12)
        self.components.cpu:register_interrupt_handler(0x15, int_15)
        self.components.cpu.memory[0xFFFFE] = 0xFE
        self.components.videocard.set_mode(self.components.cpu, 3, true)

        self.components.cpu:port_set(0x80, function (cpu, port, val) -- Debug port
            if val then

            else
                return 0xff
            end
        end)
        -- insert_disk(cpu, path, drive_id)
        -- disk_boot(cpu, drive_id)
        -- Drive ids:
        -- A(floppy) - 0x00
        -- B(floppy) - 0x01
        -- C(hard disk) - 0x80
        -- D(hard disk) - 0x81
        for id, floppy in pairs(floppy_to_load) do
            self.components.disks.insert_disk(self.components.cpu, floppy.filename, id)
        end
        self.components.disks.boot_drive(self.components.cpu, 0x00)

        -- disks.insert_disk(self.cpu, "retro_computers:modules/emulator/hard_disks/xenix8086.img", 0x80)
        self.enebled = true
    end
end

local clock = os.clock()

local function step(self, cv)
    clock = cv
    self.components.keyboard:update()
    self.components.videocard.update()
    cv = os.clock()
    clock = cv
end

local execute = true
local opc = 0
local function handle_ibm(self)
    if execute == true then
        execute = self.components.cpu:run_one(false, true)
        if execute == -1 then
            step(self, os.clock())
            execute = true
        elseif (band(opc, 0x1FF) == 0) and (os.clock() - clock) >= 0.05 then
            step(self, os.clock())
        end
        opc = opc + 1
    end
end

local function update(self)
    if self.enebled then
        for _ = 1, 10000 do
            handle_ibm(self)
        end
    end
end

local function shutdown(self)
    if self.enebled then
        self.enebled = false
        for i = 0, 0x100000 do
            self.components.cpu.memory[i] = 0
        end
        self.display.cursor_x = 0
        self.display.cursor_y = 0
        self.components.cpu:reset()
        self.components.videocard:reset()
        self.components.videocard:update()
    end
end

local function save(self)
    local machine = {
        loaded_drives = {}
    }

    for id, drive in pairs(floppy_to_load) do
        machine.loaded_drives[#machine.loaded_drives+1] = {drive.name, id}
    end
    file.write(get_save_path(self.id) .. "machine.json", json.tostring(machine, false))

    local drives = self.components.disks.get_drives()
    for _, drive in pairs(drives) do
        if drive.edited then
            drive.handler:flush()
        end
    end
end

function machine.new(id)
    local machine_path =  "world:data/retro_computers/machines/" .. id
    if file.exists("world:data") then
        if not file.exists(machine_path .. id) then
            file.mkdir(machine_path .. id)
        end
    end

    local self = {
        id = id,
        start = start,
        update = update,
        shutdown = shutdown,
        save = save,
        insert_floppy = insert_floppy,
        enebled = false,
        is_focused = false,
        display = {
            buffer = {},
            cursor_x = 0,
            cursor_y = 0,
            width = 80,
            height = 25,
            mode = 0,
            update = function() end
        },
        components = {}
    }
    self.components.memory = RAM.new(self)
    self.components.cpu = cpu.new(self.components.memory)
    self.components.pic = pic.new(self.components.cpu)
    self.components.pit = pit.new(self.components.cpu)
    self.components.keyboard = keyboard.new(self)
    self.components.videocard = cga.new(self.components.cpu, self.display)
    self.components.rtc = rtc.new(self.components.cpu)
    self.components.dma = dma.new(self.components.cpu)
    self.components.serial = serial.new(self.components.cpu)
    self.components.disks = disks.new(self.components.cpu)
    self.components.lpt = lpt.new(self.components.cpu)
    printer.new(self.components.cpu)
    setmetatable(self, {})

    local path = get_save_path(self.id) .. "machine.json"
    if file.exists(path) then
        local saved = json.parse(file.read(path))
        saved.loaded_drives = saved.loaded_drives or {}
        for _, floppy_data in pairs(saved.loaded_drives) do
            local floppy = drive_manager.get_floppy(floppy_data[1])
            if floppy then
                insert_floppy(floppy, floppy_data[2])
            end
        end
    end
    return self
end

return machine