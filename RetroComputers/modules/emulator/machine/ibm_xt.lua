local logger = require("dave_logger:logger")("RetroComputers")
local config = require("retro_computers:config")
local drive_manager = require("retro_computers:emulator/drive_manager")
local vmmanager = require("retro_computers:emulator/vmmanager")
local event = require("retro_computers:emulator/events")
local hdd_hdf = require("retro_computers:emulator/hardware/disk/hdd_hdf")
local common = require("retro_computers:emulator/machine/machine")

local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local machine = {
    EVENTS = {
        START = 1,
        STOP = 2,
        LOAD_STATE = 3,
        DELETE = 4
    }
}

local MEMORY_MAP_SHIFT = 12
local MEMORY_MAP_SIZE = 0x1000 -- 4 KB

local videocards = {
    ["mda"] = "retro_computers:emulator/hardware/video/mda",
    ["hercules"] = "retro_computers:emulator/hardware/video/hercules",
    ["cga"] = "retro_computers:emulator/hardware/video/cga",
    ["ega"] = "retro_computers:emulator/hardware/video/ega"
}

local function start(self)
    if not self.enabled then
        self:reset()

        -- Setup HDD
        local hdd_path = vmmanager.get_machine_path(self.id, "hdd1.hdf")

        if not file.exists(hdd_path) then
            hdd_hdf.create(hdd_path, 615, 4, 17, 512)
        end

        -- Load disks
        for id, floppy in pairs(self.floppy) do
            self.devices.fdc:insert_drive(id, floppy.path, floppy.readonly)
        end

        self.devices.hdc:insert_drive(0, hdd_path)

        -- Initialize devices
        for _, device in pairs(self.devices) do
            if device.initialize then
                device:initialize()
            end
        end

        -- Load BIOS
        -- 0xFC000, 0xFE000, 0xF8000, 0xF0000
        local roms = config.machine.ibm_xt.rom

        for i = 1, #roms, 1 do
            local rom = roms[i]
            local path = string.format("retro_computers:modules/emulator/roms/ibmxt/%s", rom.filename)

            self.devices.memory:load_rom(rom.addr, path)
        end

        self.enabled = true
        self.events:emit(machine.EVENTS.START)
    end
end

local function update(self)
    if self.enabled then
        local devices = self.devices

        devices.keyboard:update()
        devices.hdc:update()
        devices.pit:update()
        devices.pic:update()
        devices.fdc:update()
        devices.videocard:update()

        for _= 1, 3000, 1 do
            devices.cpu:step()
        end
    end
end

local function stop(self)
    if self.enabled then
        self.enabled = false
        self:reset()
        self.events:emit(machine.EVENTS.STOP)
    end
end

local function insert_floppy(self, floppy, id)
    if self.enabled then
        self.devices.fdc:insert_drive(id, floppy.path, floppy.readonly)
    end

    self.floppy[id] = floppy
end

local function eject_floppy(self, id)
    self.devices.fdc:eject_drive(id)
    self.floppy[id] = nil
end

local function save(self)
    local data = {
        drives = {}
    }

    for id, drive in pairs(self.floppy) do
        table.insert(data.drives, 1, {drive.name, id})
    end

    file.write(vmmanager.get_machine_path(self.id) .. "machine.json", json.tostring(data, false))

    for _, device in pairs(self.devices) do
        if device.save then
            device:save()
        end
    end
end

local function reset(self)
    for _, component in pairs(self.devices) do
        if component.reset then
            component:reset()
        end
    end
end

local function on_load_state(self)
    self.events:emit(machine.EVENTS.LOAD_STATE)
end

local function on_machine_delete(self)
    self.events:emit(machine.EVENTS.DELETE)
end

local function memory_read8(self, addr)
    if addr < 0xA0000 then
        return self.ram_base[addr]
    else
        local mapping = self.mappings[rshift(addr, MEMORY_MAP_SHIFT)]

        if mapping then
            return mapping.read(mapping.arg0, addr)
        end

        return 0x00
    end
end

local function memory_write8(self, addr, val)
   if addr < 0xA0000 then
        self.ram_base[addr] = val
        return
    else
        local mapping = self.mappings[rshift(addr, MEMORY_MAP_SHIFT)]

        if mapping then
            mapping.write(mapping.arg0, addr, val)
        end
    end
end

local function memory_set_mapping(self, addr, size, read_func, write_func, arg0)
    assert((size % MEMORY_MAP_SIZE) == 0)

    local segments = size / MEMORY_MAP_SIZE
    local mem = {
        read = read_func,
        write = write_func,
        arg0 = arg0
    }

    for i = 0, segments - 1, 1 do
        self.mappings[rshift(addr, MEMORY_MAP_SHIFT) + i] = mem
    end
end

local function memory_remove_mapping(self, addr, size)
    assert((size % MEMORY_MAP_SIZE) == 0)

    local segments = size / MEMORY_MAP_SIZE

    for i = 0, segments - 1, 1 do
        self.mappings[rshift(addr, MEMORY_MAP_SHIFT) + i] = nil
    end
end

function machine.new(id)
    local self = {
        devices = {},
        enabled = false,
        is_focused = false,
        id = id,
        floppy = {},
        events = event.new(),
        EVENTS = machine.EVENTS,
        start = start,
        stop = stop,
        update = update,
        save = save,
        reset = reset,
        insert_floppy = insert_floppy,
        eject_floppy = eject_floppy,
        on_load_state = on_load_state,
        on_machine_delete = on_machine_delete
    }

    setmetatable(self, common)

    self.devices.memory = require("retro_computers:emulator/hardware/memory").new(0x100000)

    local memory = self.devices.memory

    memory.mappings = {}
    memory.ram_base = {}
    memory.ram_rom = {}

    memory.read8 = memory_read8
    memory.write8 = memory_write8
    memory.set_mapping = memory_set_mapping
    memory.remove_mapping = memory_remove_mapping

    self.devices.cpu = require("retro_computers:emulator/hardware/cpu/i8088").new(self.devices.memory)
    self.devices.pic = require("retro_computers:emulator/hardware/i8259").new(self.devices.cpu, 0x20)
    self.devices.pit = require("retro_computers:emulator/hardware/i8253").new(self.devices.cpu, 0x40)
    self.devices.screen = require("retro_computers:emulator/screen").new(self)
    self.devices.videocard = require(videocards[config.machine.ibm_xt.video] or videocards["cga"]).new(self.devices.cpu, self.devices.memory, self.devices.screen)
    self.devices.dma = require("retro_computers:emulator/hardware/i8237").new(self.devices.cpu, self.devices.memory)
    self.devices.lpt = require("retro_computers:emulator/hardware/lpt").new(self.devices.cpu, self.devices.pic)
    self.devices.fdc = require("retro_computers:emulator/hardware/floppy/fdc").new(self.devices.cpu, self.devices.pic, self.devices.dma)
    self.devices.hdc = require("retro_computers:emulator/hardware/disk/st506").new(self.devices.cpu, self.devices.memory, self.devices.pic, self.devices.dma)
    self.devices.pc_speaker = require("retro_computers:emulator/hardware/sound/pc_speaker").new(self.devices.pit, self.devices.keyboard)
    self.devices.keyboard = require("retro_computers:emulator/hardware/keyboard/keyboard_xt").new(self.devices.cpu, self.devices.pic, self.devices.pit, self.devices.pc_speaker, self.devices.videocard, 2, 0x60, self)
    self.devices.mouse = require("retro_computers:emulator/hardware/mouse/mouse_bus").new(self.devices.cpu, self.devices.pic, 0x23C, 4)

    if config.machine.ibm_xt.post_card then
        self.devices.postcard = require("retro_computers:emulator/hardware/postcard").new(self.devices.cpu, 0x80)
    end

    self.devices.cpu.pic = self.devices.pic
    self.devices.cpu:set_reset_vector(0xFFFF, 0x0000)

    memory:set_mapping(0xF0000, 0x10000, -- BIOS
        function(_, addr)
            return memory.ram_rom[band(addr, 0x0FFFF)]
        end,
        function(_, addr, val)
            memory.ram_rom[band(addr, 0x0FFFF)] = val
        end
    )

    -- IRQ 0 (Interrupt 08h)
    self.devices.pit:set_channel_out_handler(0, function(out, old_out)
        if out and (not old_out) then
            self.devices.pic:request_interrupt(0)
        end

        if not out then
            self.devices.pic:clear_interrupt(0)
        end
    end)

    -- DMA Refresh
    -- self.devices.pit:set_channel_out_handler(1, function(out, old_out)
    --     if out and (not old_out) then
    --         self.devices.dma:channel_read(0)
    --     end
    -- end)

    local path = vmmanager.get_machine_path(self.id, "machine.json")

    if file.exists(path) then
        local data = json.parse(file.read(path))

        if data.drives then
            for i = 1, #data.drives, 1 do
                local floppy_data = data.drives[i]
                local floppy = drive_manager.get_floppy(floppy_data[1])

                if floppy then
                    insert_floppy(self, floppy, floppy_data[2])
                end
            end
        end
    end

    return self
end

return machine
