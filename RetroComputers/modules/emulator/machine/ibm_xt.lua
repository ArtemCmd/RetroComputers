local logger = require("retro_computers:logger")
local drive_manager = require("retro_computers:emulator/drive_manager")
local vmmanager = require("retro_computers:emulator/vmmanager")
local bit_converter = require("core:bit_converter")

local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local RAM = {}

function RAM.new(machine)
    local self = {}
    local ram_640k = {}
    local ram_rom = {}

    setmetatable(self, {
        __index = function(t, key)
            if (key < 0xA0000) then
                return ram_640k[key + 1] or 0
            elseif (key >= machine.components.videocard.start_addr) and (key <= machine.components.videocard.end_addr) then
                return machine.components.videocard:vram_read(key)
            elseif (key >= 0xF0000 and key < 0x100000) then
                return ram_rom[band(key, 0xFFFFF) - 0xF0000] or 0x00
            else
                return 0x00
            end
        end,
        __newindex = function(t, key, value)
            if (key < 0xA0000) then
                ram_640k[key + 1] = value
            elseif (key >= machine.components.videocard.start_addr) and (key <= machine.components.videocard.end_addr) then
                machine.components.videocard:vram_write(key, value)
            elseif (key >= 0xF0000 and key < 0x100000) then
                ram_rom[band(key, 0xFFFFF) - 0xF0000] = value
            end
        end
    })

    rawset(self, "r16", function(ram, key)
        if key < 0x9FFFF then
            return bor((ram_640k[key + 1] or 0), lshift((ram_640k[key + 2] or 0), 8))
        else
            return bor(ram[key], lshift(ram[key + 1], 8))
        end
    end)

    rawset(self, "w16", function(ram, key, value)
        if key < 0x9FFFF then
            ram_640k[key + 1] = band(value, 0xFF)
            ram_640k[key + 2] = rshift(value, 8)
        else
            ram[key] = band(value, 0xFF)
            ram[key + 1] = rshift(value, 8)
        end
    end)

    rawset(self, "w32", function(ram, key, value)
        ram[key] = band(value, 0xFF)
        ram[key + 1] = band(rshift(value, 8), 0xFF)
        ram[key + 2] = band(rshift(value, 16), 0xFF)
        ram[key + 3] = rshift(value, 24)
    end)

    rawset(self, "r32", function(ram, key)
        return bor(bor(bor(ram[key], lshift(ram[key + 1], 8)), lshift(ram[key + 2], 16)), lshift(ram[key + 3], 32))
    end)

    rawset(self, "reset", function(mem)
        for i = 0, 0x100000, 1 do
            mem[i] = 0
        end
    end)

    rawset(self, "save", function(mem, stream)
        stream:write_bytes(bit_converter.uint32_to_bytes(1048576)) -- Chunk lenght
        for i = 0, 1048575, 1 do
            stream:write(self[i] or 0)
        end
    end)

    rawset(self, "load", function(mem, data)
        for i = 0, 1048575, 1 do
            mem[i] = data[i + 1]
        end
    end)

    return self
end

local cpu = require("retro_computers:emulator/hardware/processors/i8086")
local pit = require("retro_computers:emulator/hardware/i8253")
local pic = require("retro_computers:emulator/hardware/i8259")
local cga = require("retro_computers:emulator/hardware/videocards/cga")
local disks = require("retro_computers:emulator/disks")
local keyboard = require("retro_computers:emulator/hardware/keyboards/keyboard_xt")
local serial = require("retro_computers:emulator/hardware/serial")
local dma = require("retro_computers:emulator/hardware/i8237")
-- local fdc = require("retro_computers:emulator/hardware/floppy/fdc")
local printer = require("retro_computers:emulator/printer/dave_printer")
local lpt = require("retro_computers:emulator/hardware/lpt")
local display = require("retro_computers:emulator/display")
local postcard = require("retro_computers:emulator/hardware/other/postcard")
local dave_bios = require("retro_computers:emulator/dave_bios")

local machine = {}

local function insert_floppy(self, floppy, id)
    if self.enabled then
        self.components.disks:insert_disk(self.components.cpu, floppy.filename, floppy.readonly, id)
    end
    self.floppy_to_load[id] = floppy
end

local function eject_floppy(self, id)
    -- logger:debug("IBM XT: Eject floppy %d", id)
    if self.components.disks.drives[id] then
        self.components.disks:eject_drive(id)
    end
    self.floppy_to_load[id] = nil
end

local function start(self)
    if not self.enabled then
        logger:info("IBM XT: Starting")

        self.speaker_id = audio.play_sound_2d("computer/running", 1.0, 1.0, nil, true)

        self:reset()

        -- BIOS TEST
        -- bios-xt.bin 0xFC000, 0xFE000
        -- local rom = file.read_bytes("retro_computers:modules/emulator/roms/ibmxt/bios-xt.bin")
        -- -- local rom2 = file.read_bytes("retro_computers:modules/emulator/roms/ibmxt/5000027.u19")
        -- for i = 0, #rom - 1, 1 do
        --     self.components.cpu.memory[0xFC000 + i] = rom[i + 1]
        -- end
        -- -- for i = 0, #rom - 1, 1 do
        -- --     self.components.cpu.memory[0xF0000 + i] = rom2[i + 1]
        -- -- end
        -- self.components.cpu:set_ip(0xFFFF, 0)

        self.components.cpu.flags = 0x0202
        self.bios:start()

        local hdd_path = vmmanager.get_machine_path(self.id) .. "disks/hdd.hdf"
        if not file.exists(hdd_path) then
            local hdd_folder_path = vmmanager.get_machine_path(self.id) .. "disks/"
            if not file.exists(hdd_folder_path) then
                file.mkdir(hdd_folder_path)
            end
            drive_manager.create_hard_disk(hdd_path, 306, 4, 17, 512, "hdf")
        end

        self.components.disks:insert_disk(self.components.cpu, hdd_path, false, 0x80)

        for id, floppy in pairs(self.floppy_to_load) do
            self.components.disks:insert_disk(self.components.cpu, floppy.filename, floppy.readonly, id)
        end

        if self.floppy_to_load[0] then
            self.components.disks:boot_drive(self.components.cpu, 0x00)
        else
            self.components.disks:boot_drive(self.components.cpu, 0x80)
        end

        self.enabled = true
    end
end

local function step(self)
    self.clock = os.clock()
    self.components.keyboard:update()
    self.components.videocard:update()
    self.components.pit:update()
end

local function handle_ibm(self)
    self.execute = self.components.cpu:run_one(false)
    if (self.execute == -1) and (os.clock() - self.clock) >= 0.05 then
        self.execute = true
        step(self)
    elseif (band(self.opcode, 0x1FF) == 0) and (os.clock() - self.clock) >= 0.05 then
        self.opcode = 0
        step(self)
    end
    self.opcode = self.opcode + 1
end

local function update(self)
    if self.enabled then
        for _ = 1, 5000 do
            handle_ibm(self)
        end
    end
end

local function shutdown(self)
    if self.enabled then
        self.enabled = false

        audio.stop(self.speaker_id)
        self:reset()
    end
end

local function save(self)
    local machine_info = {
        loaded_drives = {}
    }

    for id, drive in pairs(self.floppy_to_load) do
        machine_info.loaded_drives[#machine_info.loaded_drives+1] = {drive.name, id}
    end
    file.write(vmmanager.get_machine_path(self.id) .. "machine.json", json.tostring(machine_info, false))

    local drives = self.components.disks.drives
    for _, drive in pairs(drives) do
        if drive.edited then
            drive.handler:flush()
        end
    end
end

local function reset(self)
    self.components.memory:reset()
    self.components.display:reset()
    self.components.cpu:reset()
    self.components.videocard:reset()
    self.components.videocard:update()
    self.components.keyboard:reset()
    self.components.disks:reset(self.components.memory)
    self.components.serial:reset()
    self.components.lpt:reset()
end

local function on_load_state(self)
    local hdd_path = vmmanager.get_machine_path(self.id) .. "disks/hdd.hdf"

    self.components.disks:insert_disk(self.components.cpu, hdd_path, false, 0x80)

    for id, floppy in pairs(self.floppy_to_load) do
        self.components.disks:insert_disk(self.components.cpu, floppy.filename, floppy.readonly, id)
    end

    self.speaker_id = audio.play_sound_2d("computer/running", 1.0, 1.0, nil, true)
end

local function on_machine_delete(self)
    audio.stop(self.speaker_id)

    for id, _ in pairs(self.floppy_to_load) do
        self.floppy_to_load[id] = nil
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
        floppy_to_load = {},
        enabled = false,
        is_focused = false,
        clock = os.clock(),
        opcode = 0,
        speaker_id = -1,
        execute = true,
        components = {},
        start = start,
        update = update,
        shutdown = shutdown,
        save = save,
        reset = reset,
        insert_floppy = insert_floppy,
        eject_floppy = eject_floppy,
        on_load_state = on_load_state,
        on_machine_delete = on_machine_delete
    }

    self.components.memory = RAM.new(self)
    self.components.cpu = cpu.new(self.components.memory)
    self.components.pic = pic.new(self.components.cpu)
    self.components.pit = pit.new(self.components.cpu)
    self.components.keyboard = keyboard.new(self)
    self.components.display = display.new(self)
    self.components.videocard = cga.new(self.components.cpu, self.components.display)
    self.components.dma = dma.new(self.components.cpu)
    self.components.serial = serial.new(self.components.cpu)
    self.components.disks = disks.new(self.components.cpu)
    self.components.lpt = lpt.new(self.components.cpu)
    -- self.components.fdc = fdc.new(self.components.cpu)
    self.components.postcard = postcard.new(self.components.cpu)
    self.bios = dave_bios.new(self.components.cpu, self.components.memory)
    printer.new(self.components.lpt)
    setmetatable(self, {})

    local path = vmmanager.get_machine_path(self.id) .. "machine.json"
    if file.exists(path) then
        local saved = json.parse(file.read(path))
        saved.loaded_drives = saved.loaded_drives or {}
        for _, floppy_data in pairs(saved.loaded_drives) do
            local floppy = drive_manager.get_floppy(floppy_data[1])
            if floppy then
                insert_floppy(self, floppy, floppy_data[2])
            end
        end
    end

    return self
end

return machine