local logger = require("retro_computers:logger")
local config = require("retro_computers:config")
local filesystem = require("retro_computers:emulator/filesystem")
local drive_manager = require("retro_computers:emulator/drive_manager")
local vmmanager = require("retro_computers:emulator/vmmanager")
local hdd_hdf = require("retro_computers:emulator/hardware/disk/hdd_hdf")
local cpu = require("retro_computers:emulator/hardware/cpu/i8086")
local pit = require("retro_computers:emulator/hardware/i8253")
local pic = require("retro_computers:emulator/hardware/i8259")
local keyboard = require("retro_computers:emulator/hardware/keyboard/keyboard_xt")
local dma = require("retro_computers:emulator/hardware/i8237")
local lpt = require("retro_computers:emulator/hardware/lpt")
local display = require("retro_computers:emulator/display")
local postcard = require("retro_computers:emulator/hardware/other/postcard")
local fdc = require("retro_computers:emulator/hardware/floppy/fdc")
local pc_speaker = require("retro_computers:emulator/hardware/sound/pc_speaker")
local hdc = require("retro_computers:emulator/hardware/disk/st506")
local cga = require("retro_computers:emulator/hardware/video/cga")
local hercules = require("retro_computers:emulator/hardware/video/hercules")
local mda = require("retro_computers:emulator/hardware/video/mda")

local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local videocards = {
    ["mda"] = mda,
    ["hercules"] = hercules,
    ["cga"] = cga
}

local RAM = {}
function RAM.new(machine)
    local self = {}
    local ram_base = {}
    local ram_rom = {}
    local ram_hdc = {}

    setmetatable(self, {
        __index = function(t, key)
            if key < 0xA0000 then
                return ram_base[key] or 0x00
            elseif (key >= machine.components.videocard.vram_start) and (key <= machine.components.videocard.vram_end) then
                return machine.components.videocard:vram_read(key)
            elseif (key >= 0xC8000) and (key < 0xCA000) then
                return ram_hdc[key - 0xC8000]
            elseif (key >= 0xF0000) and (key < 0x100000) then
                return ram_rom[band(key, 0x0FFFF)]
            end

            return 0x00
        end,
        __newindex = function(t, key, value)
            if key < 0xA0000 then
                ram_base[key] = value
            elseif (key >= machine.components.videocard.vram_start) and (key <= machine.components.videocard.vram_end) then
                machine.components.videocard:vram_write(key, value)
            elseif (key >= 0xC8000) and (key < 0xCA000) then
                ram_hdc[key - 0xC8000] = value
            elseif (key >= 0xF0000) and (key < 0x100000) then
                ram_rom[band(key, 0x0FFFF)] = value
            end
        end
    })

    rawset(self, "r16", function(ram, key)
        if key < 0x9FFFF then
            return bor(ram_base[key], lshift(ram_base[key + 1], 8))
        else
            return bor(ram[key], lshift(ram[key + 1], 8))
        end
    end)

    rawset(self, "w16", function(ram, key, value)
        if key < 0x9FFFF then
            ram_base[key] = band(value, 0xFF)
            ram_base[key + 1] = rshift(value, 8)
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

    rawset(self, "save_state", function(mem, stream)
        stream:write_uint32(1048576)

        for i = 0, 1048575, 1 do
            stream:write(self[i] or 0)
        end
    end)

    rawset(self, "load_state", function(mem, data)
        for i = 0, 1048575, 1 do
            mem[i] = data[i + 1]
        end
    end)

    return self
end

local function insert_floppy(self, floppy, id)
    if self.enabled then
        self.components.fdc:insert_drive(id, floppy.path, floppy.readonly)
    end

    self.floppy[id] = floppy
end

local function eject_floppy(self, id)
    self.components.fdc:eject_drive(id)
    self.floppy[id] = nil
end

local function get_id(self)
    return self.id
end

local function call_event(self, id)
    if self.handler then
        self.handler(self, id)
    end
end

local function start(self)
    if not self.enabled then
        logger.info("IBM XT: Starting")
        self:reset()

        -- Setup HDD
        local hdd_folder_path = vmmanager.get_machine_path(self.id) .. "disks/"
        local hdd_path = hdd_folder_path ..  "hdd.hdf"

        if not file.exists(hdd_folder_path) then
            file.mkdir(hdd_folder_path)
        end

        if not file.exists(hdd_path) then
            hdd_hdf.new(hdd_path, 615, 4, 17, 512)
        end

        -- Load disks
        for id, floppy in pairs(self.floppy) do
            self.components.fdc:insert_drive(id, floppy.path, floppy.readonly)
        end

        self.components.hdc:insert_drive(0, hdd_path)

        -- Load BIOS extensions
        self.components.hdc:initialize()

        -- Load BIOS
        -- 0xFC000, 0xFE000, 0xF8000, 0xF0000
        local roms = config.ibm_xt.rom

        for i = 1, #roms, 1 do
            local rom = roms[i]
            local path = "retro_computers:modules/emulator/roms/ibmxt/" .. rom.filename

            if file.exists(path) then
                local stream = filesystem.open(path, false)

                if stream then
                    local bytes = stream:get_buffer()

                    for j = 0, #bytes - 1, 1 do
                        self.components.memory[rom.addr + j] = bytes[j + 1]
                    end
                end
            else
                logger.error("IBM XT: ROM \"%S\" not found", rom.filename)
            end
        end

        self.components.cpu:set_ip(0xFFFF, 0x0000)
        self.enabled = true

        call_event(self, 0)
    end
end

local function update(self)
    if self.enabled then
        local components = self.components

        for _ = 1, 3000, 1 do
            components.cpu:step()
            components.pit:update()
            components.pic:update()
        end

        components.keyboard:update()
        components.fdc:update()
        components.hdc:update()
        components.videocard:update()

        if components.display3d then
            components.display3d:update()
        end
    end
end

local function shutdown(self)
    if self.enabled then
        self.enabled = false
        self:reset()
        call_event(self, 1)
    end
end

local function save(self)
    local data = {
        drives = {}
    }

    for id, drive in pairs(self.floppy) do
        table.insert(data.drives, 1, {drive.name, id})
    end

    file.write(vmmanager.get_machine_path(self.id) .. "machine.json", json.tostring(data, false))

    for _, component in pairs(self.components) do
        if rawget(component, "save") then
            component:save()
        end
    end
end

local function reset(self)
    for _, component in pairs(self.components) do
        if component.reset then
            component:reset()
        end
    end
end

local function get_component(self, name)
    return self.components[name]
end

local function set_component(self, name, component)
    self.components[name] = component
end

local function get_event_handler(self)
    return self.handler
end

local function set_event_handler(self, handler)
    self.handler = handler
end

local function on_load_state(self)
    call_event(self, 2)
end

local function on_machine_delete(self)
    call_event(self, 3)
end

local machine = {
    EVENTS = {
        START = 0,
        STOP = 1,
        LOAD_STATE = 2,
        DELETE = 3
    }
}

function machine.new(id)
    local self = {
        components = {},
        floppy = {},
        id = id,
        enabled = false,
        is_focused = false,
        get_id = get_id,
        start = start,
        shutdown = shutdown,
        update = update,
        save = save,
        get_event_handler = get_event_handler,
        set_event_handler = set_event_handler,
        reset = reset,
        get_component = get_component,
        set_component = set_component,
        insert_floppy = insert_floppy,
        eject_floppy = eject_floppy,
        on_load_state = on_load_state,
        on_machine_delete = on_machine_delete
    }

    self.components.memory = RAM.new(self)
    self.components.cpu = cpu.new(self.components.memory)
    self.components.pic = pic.new(self.components.cpu)
    self.components.pit = pit.new(self.components.cpu)
    self.components.display = display.new(self)

    local videocard = videocards[config.ibm_xt.video]

    if not videocard then
        videocard = cga
        logger.error("IBM XT: Unknown videocard \"%s\"", config.ibm_xt.video)
    end

    self.components.videocard = videocard.new(self.components.cpu, self.components.display)

    self.components.dma = dma.new(self.components.cpu, self.components.memory)
    self.components.lpt = lpt.new(self.components.cpu)
    self.components.fdc = fdc.new(self.components.cpu, self.components.pic, self.components.dma)
    self.components.hdc = hdc.new(self.components.cpu, self.components.memory, self.components.pic, self.components.dma)
    self.components.pc_speaker = pc_speaker.new(self.components.pit, self.components.keyboard)
    self.components.keyboard = keyboard.new(self, self.components.cpu, self.components.pic, self.components.pit, self.components.pc_speaker, self.components.videocard, 2)
    self.components.cpu.pic = self.components.pic

    if config.post_card then
        self.components.postcard = postcard.new(self.components.cpu)
    end

    -- IRQ 0 (Interrupt 08h)
    self.components.pit:set_channel_handler(0, function(channel, set, old_set)
        if set and (not old_set) then
            self.components.pic:request_interrupt(1, true)
        end

        if not set then
            self.components.pic:request_interrupt(1, false)
        end
    end)

    -- DMA Refresh
    -- self.components.pit:set_channel_handler(1, function(channel, set, old_set)
    --     if set and (not old_set) then
    --         self.components.dma:channel_read(0)
    --     end
    -- end)

    local path = vmmanager.get_machine_path(self.id) .. "machine.json"

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