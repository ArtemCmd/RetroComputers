local logger = require("dave_logger:logger")("RetroComputers")
local common = require("retro_computers:machine/machine")
local config = require("retro_computers:config")
local util = require("retro_computers:util")
local drive_manager = require("retro_computers:drive_manager")
local vmmanager = require("retro_computers:vmmanager")

local emu_api = require("emulator:api/v1/api")
local device_manager = emu_api.device_manager

local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local machine = {}

local MEMORY_MAP_SHIFT = 12
local MEMORY_MAP_SIZE = 0x1000 -- 4 KB

local TPS = config.misc.tps

local MAIN_FREQ = 14318184
local CPU_FREQ = 4772728
local PIT_FREQ = 1193182

local CPU_CLOCK = 157500000.0 / 11.0
local PIT_CLOCK = CPU_CLOCK / PIT_FREQ
local CGA_CLOCK = CPU_CLOCK / (157500000.0 / 88.0)
local MDA_CLOCK = math.floor(CPU_CLOCK / (16257000.0 / 9.0))

local TIMER_USEC = math.floor(CPU_CLOCK / 1000000.0)
local CYCLES_PER_TICK = CPU_FREQ / TPS

local LPT_PORTS = {0x378}
local LPT_IRQS = {7}

local SERIAL_PORTS = {0x3F8}
local SERIAL_IRQS = {4}

local function parse_geometry(str)
    local result = {}
    local pos = 1

    for i = 1, #str, 1 do
        if string.sub(str, i, i) == "/" then
            result[#result+1] = tonumber(string.sub(str, pos, i - 1), 10)
            pos = i + 1
        elseif i == #str then
            result[#result+1] = tonumber(string.sub(str, pos, i), 10)
        end
    end

    return result
end

local HDD_GEOMETRY = {
    parse_geometry(config.machine.ibm_xt.hdc.hdd[1].geometry),
    parse_geometry(config.machine.ibm_xt.hdc.hdd[2].geometry)
}

local FDC_DRIVE_VOLUME = 5.0
local FDC_DRIVE_HANDLER = {
    start_motor = function(self, drive_id)
        if not self.host then
            return
        end

        audio.play_sound("computer/fdd_start", self.host.x, self.host.y, self.host.z, FDC_DRIVE_VOLUME, 1.0, "regular", false)

        local scheduler = self.devices.cpu.scheduler
        local timer = scheduler:add(function()
            self.host.motor_loop[drive_id] = audio.play_sound("computer/fdd_loop", self.host.x, self.host.y, self.host.z, FDC_DRIVE_VOLUME, 1.0, "regular", true)
        end, nil, false)

        timer:set_delay(3 * CPU_FREQ)
    end,
    stop_motor = function(self, drive_id)
        if not self.host then
            return
        end

        audio.stop(self.host.motor_loop[drive_id])
        audio.play_sound("computer/fdd_stop", self.host.x, self.host.y, self.host.z, FDC_DRIVE_VOLUME, 1.0, "regular", false)
    end
}
FDC_DRIVE_HANDLER.__index = FDC_DRIVE_HANDLER

local function create_hdd(self, index)
    local hdd_path = vmmanager.get_machine_path(self.id, string.format("hdd%d.hdf", index + 1))

    if not file.exists(hdd_path) then
        local geometry = HDD_GEOMETRY[index + 1]
        emu_api.file_formats.hdf.create(hdd_path, geometry[1], geometry[2], geometry[3], 512, true)
    end

    return hdd_path
end

local function start(self)
    if not self.enabled then
        self:reset()

        -- Setup HDD
        for i = 0, math.min(config.machine.ibm_xt.hdc.hdd_count, 2) - 1, 1 do
            local success, message = pcall(self.devices.hdc.insert_drive, self.devices.hdc, i, create_hdd(self, i))

            if not success then
                logger:error("IBM PC/XT: Failed to load disk image: %s", message)
            end
        end

        -- Initialize devices
        for _, device in pairs(self.devices) do
            if device.initialize then
                device:initialize()
            end
        end

        -- Load ROMS
        -- 0xFC000, 0xFE000, 0xF8000, 0xF0000
        util.load_roms("ibm_xt", self.devices.memory)

        self.enabled = true
        events.emit("retro_computers:machine.started", self)
    end
end

local function update(self)
    if self.enabled then
        self.devices.cpu:execute(CYCLES_PER_TICK)
    end
end

local function stop(self)
    if self.enabled then
        self.enabled = false
        self:reset()
        events.emit("retro_computers:machine.stopped", self)
    end
end

local function insert_floppy(self, floppy, id)
    self.devices.fdc:insert_drive(id, floppy.path, floppy.readonly)
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

local function on_load_state(self)
    events.emit("retro_computers:machine.loaded", self)
end

local function on_delete(self)
    events.emit("retro_computers:machine.deleted", self)
end

local function memory_read8(self, addr)
    if addr < 0xA0000 then
        return self.ram_base[addr]
    end

    local read = self.read_maps[rshift(addr, MEMORY_MAP_SHIFT)]

    if read then
        return read(self.maps_arg[rshift(addr, MEMORY_MAP_SHIFT)], addr)
    end

    return 0x00
end

local function memory_write8(self, addr, val)
   if addr < 0xA0000 then
        self.ram_base[addr] = val
        return
    end

    local write = self.write_maps[rshift(addr, MEMORY_MAP_SHIFT)]

    if write then
        write(self.maps_arg[rshift(addr, MEMORY_MAP_SHIFT)], addr, val)
    end
end

local function memory_add_mapping(self, addr, size, read_func, write_func, arg0)
    assert((size % MEMORY_MAP_SIZE) == 0)

    for i = 0, (size / MEMORY_MAP_SIZE) - 1, 1 do
        self.read_maps[rshift(addr, MEMORY_MAP_SHIFT) + i] = read_func
        self.write_maps[rshift(addr, MEMORY_MAP_SHIFT) + i] = write_func
        self.maps_arg[rshift(addr, MEMORY_MAP_SHIFT) + i] = arg0
    end
end

local function memory_remove_mapping(self, addr, size)
    assert((size % MEMORY_MAP_SIZE) == 0)

    for i = 0, (size / MEMORY_MAP_SIZE) - 1, 1 do
        self.read_maps[rshift(addr, MEMORY_MAP_SHIFT) + i] = nil
        self.write_maps[rshift(addr, MEMORY_MAP_SHIFT) + i] = nil
        self.maps_arg[rshift(addr, MEMORY_MAP_SHIFT) + i] = nil
    end
end

function machine.new(id)
    local self = {
        devices = {},
        floppy = {},
        enabled = false,
        is_focused = false,
        id = id,
        start = start,
        stop = stop,
        update = update,
        save = save,
        insert_floppy = insert_floppy,
        eject_floppy = eject_floppy,
        on_load_state = on_load_state,
        on_delete = on_delete
    }

    setmetatable(self, common)

    -- Setup devices
    self.devices.memory = device_manager.create("memory", 0x100000)  -- 1 MiB

    local memory = self.devices.memory

    memory.mappings = {}
    memory.ram_base = {}
    memory.ram_rom = {}
    memory.read_maps = {}
    memory.write_maps = {}
    memory.maps_arg = {}

    memory.read8 = memory_read8
    memory.write8 = memory_write8
    memory.add_mapping = memory_add_mapping
    memory.remove_mapping = memory_remove_mapping

    memory:add_mapping(0xF0000, 0x10000, -- BIOS
        function(_, addr)
            return memory.ram_rom[band(addr, 0x0FFFF)]
        end,
        function(_, addr, val)
            memory.ram_rom[band(addr, 0x0FFFF)] = val
        end
    )

    self.devices.cpu = device_manager.create("i8088", self.devices.memory)
    self.devices.pic = device_manager.create("i8259", self.devices.cpu, 0x20)
    self.devices.pit = device_manager.create("i8253", self.devices.cpu, 0x40)
    self.devices.dma = device_manager.create("i8237", self.devices.cpu, self.devices.memory)
    self.devices.fdc = device_manager.create("fdc", self.devices.cpu, self.devices.pic, self.devices.dma)
    self.devices.hdc = device_manager.create(config.machine.ibm_xt.hdc.controller, self.devices.cpu, self.devices.memory, self.devices.pic, self.devices.dma)
    self.devices.lpt = device_manager.create("lpt", self.devices.cpu, self.devices.pic, LPT_PORTS, LPT_IRQS)
    self.devices.pc_speaker = device_manager.create("pc_speaker", self.devices.pit, self.devices.cpu)
    self.devices.mouse = device_manager.create("mouse_bus", self.devices.cpu, self.devices.pic, 0x23C, 4)
    self.devices.screen = device_manager.create("screen")
    self.devices.videocard = device_manager.create(config.machine.ibm_xt.video, self.devices.cpu, self.devices.memory, self.devices.screen)
    self.devices.keyboard = device_manager.create("keyboard_xt", self.devices.cpu, self.devices.pic, self.devices.pit, self.devices.pc_speaker, self.devices.videocard, 2, 0x60, self)
    self.devices.serial = device_manager.create("serial", self.devices.cpu, self.devices.pic, SERIAL_PORTS, SERIAL_IRQS)

    if config.machine.ibm_xt.postcard then
        self.devices.postcard = device_manager.create("postcard", self.devices.cpu, 0x80)
    end

    self.devices.network = device_manager.create("wd8003", self.devices.cpu, self.devices.memory, self.devices.pic)

    -- CPU:
    self.devices.cpu.pic = self.devices.pic
    self.devices.cpu:set_reset_vector(0xFFFF, 0x0000)
    self.devices.cpu.scheduler.USEC = TIMER_USEC
    self.devices.cpu.scheduler.NANOSECOND = TIMER_USEC

    self.devices.cpu:get_io():set_port_out(0xA0, function(_, cpu, val) -- NMI
        self.devices.cpu:set_nmi(band(val, 0x80) ~= 0)
    end)

    -- PIT:
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
    self.devices.pit:set_channel_out_handler(1, function(out, old_out)
        if out and (not old_out) then
            self.devices.dma:channel_read(0)
        end
    end)

    local handler = setmetatable({arg = self}, FDC_DRIVE_HANDLER)

    self.devices.fdc:set_drive_callbacks(0, handler)
    self.devices.fdc:set_drive_callbacks(1, handler)

    self.devices.cpu:set_clock(CPU_CLOCK)
    self.devices.keyboard:set_clock()
    self.devices.pc_speaker:set_clock()
    self.devices.pit:set_clock(PIT_CLOCK)
    self.devices.fdc:set_clock()

    if self.devices.hdc.set_clock then
        self.devices.hdc:set_clock()
    end

    if self.devices.videocard.set_clock then
        local config_video = config.machine.ibm_xt.video
        local video_clock

        if config_video == "cga" then
            video_clock = CGA_CLOCK
        elseif config_video == "mda" then
            video_clock = MDA_CLOCK
        end

        self.devices.videocard:set_clock(video_clock)
    end

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
