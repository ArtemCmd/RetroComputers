-- =====================================================================================================================================================================
-- IBM PC-XT Fixed Disk controller emulation.
-- =====================================================================================================================================================================

local logger = require("dave_logger:logger")("RetroComputers")
local filesystem = require("retro_computers:emulator/filesystem")
local hdf = require("retro_computers:emulator/hardware/disk/hdd_hdf")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local controller = {}

local HDC_IRQ = 0x05
local HDC_DMA = 0x03
local HDC_ROM = filesystem.open("retro_computers:modules/emulator/roms/hdd/ibm_xebec_62x0822_1985.bin", "r", true):read_bytes()

local STATUS_IRQ = 0x20
local STATUS_IO = 0x02
local STATUS_BSY = 0x08
local STATUS_CD = 0x04
local STATUS_REQ = 0x01

local STATE_IDLE = 0
local STATE_RECEIVE_COMMAND = 1
local STATE_START_COMMAND = 2
local STATE_RECEIVE_DATA = 3
local STATE_RECEIVED_DATA = 4
local STATE_SEND_DATA = 5
local STATE_SENT_DATA = 6
local STATE_COMPLETION_BYTE = 7

local OPERATION_NONE = 0x00
local OPERATION_READ = 0x01
local OPERATION_WRITE = 0x02

local ERR_BAD_COMMAND = 0x20
local ERR_ILLEGAL_ADDR = 0x21
local ERR_NO_READY = 0x04
local ERR_SEEK_ERROR = 0x15
local ERR_BAD_PARAMETER = 0x22
local ERR_NO_RECOVERY = 0x1F

local file_formats = {
    ["hdf"] = hdf
}

local supported_formats = {
    [0] = {306, 4, 17},
    {612, 4, 17},
    {615, 4, 17},
    {306, 8, 17}
}

local function init_drive(self, num)
    self.drives[num] = {
        cylinders = 0,
        heads = 0,
        sectors = 0,
        cylinder = 0,
        head = 0,
        sector = 0,
        present = false,
        edited = false
    }
end

local function get_chs(self, drive)
    self.error = 0x80
    self.head = band(self.command[1], 0x1F)
    self.sector = band(self.command[2], 0x3F)
    self.cylinder = bor(self.command[3], lshift(band(self.command[2], 0xC0), 2))
    self.count = self.command[4]

    if self.cylinder >= drive.cylinders then
        drive.cylinder = drive.cylinders - 1
        return false
    end

    drive.cylinder = self.cylinder

    return true
end

local function get_sector(self, drive)
    if not drive.present then
        self.last_error = ERR_NO_READY
        return -1
    end

    if self.head >= drive.heads then
        self.last_error = ERR_ILLEGAL_ADDR
        return -1
    end

    if self.sector >= drive.sectors then
        self.last_error = ERR_ILLEGAL_ADDR
        return -1
    end

    return (((self.cylinder * drive.heads) + self.head) * drive.sectors) + self.sector
end

local function next_sector(self, drive)
    self.sector = self.sector + 1

    if self.sector >= drive.sectors then
        self.sector = 0
        self.head = self.head + 1

        if self.head >= drive.heads then
            self.head = 0
            drive.cylinder = drive.cylinder + 1

            if drive.cylinder >= drive.cylinders then
                drive.cylinder = drive.cylinders - 1
            else
                self.cylinder = self.cylinder + 1
            end
        end
    end
end

local function hdc_error(self, code)
    self.completion = bor(self.completion, 0x02)
    self.last_error = code
end

local function command_complete(self)
    self.status = bor(STATUS_BSY, bor(STATUS_IO, bor(STATUS_CD, STATUS_REQ)))
    self.state = STATE_COMPLETION_BYTE

    if self.dma_enabled then
        self.dma:clear_service(HDC_DMA)
    end

    if self.irq_enabled then
        self.status = bor(self.status, STATUS_IRQ)
        self.pic:request_interrupt(HDC_IRQ)
    end
end

-- Operations
local function operation_read(self)
    local drive = self.drives[self.drive_select]
    local addr = get_sector(self, drive)

    if addr == -1 then
        self.operation = OPERATION_NONE
        hdc_error(self, self.last_error)
        command_complete(self)
        return
    end

    local data = drive.handler:read_sector(addr)

    for i = 0, 511, 1 do
        local val = data[i + 1]
        local status = self.dma:channel_write(HDC_DMA, val, false)

        self.buffer[i] = val

        if status == 0x200 then
            self.operation = OPERATION_NONE
            hdc_error(self, ERR_NO_RECOVERY)
            command_complete(self)
            return
        end
    end

    self.count = self.count - 1

    if self.count <= 0 then
        self.operation = OPERATION_NONE
        command_complete(self)
        return
    end

    next_sector(self, drive)

    self.buffer_pos = 0
    self.buffer_count = 512
    self.status = bor(STATUS_BSY, bor(STATUS_IO, STATUS_REQ))
    self.state = STATE_SEND_DATA
end

local function operation_write(self)
    local drive = self.drives[self.drive_select]
    local addr = get_sector(self, drive)

    if addr == -1 then
        self.operation = OPERATION_NONE
        hdc_error(self, ERR_BAD_PARAMETER)
        command_complete(self)
        return
    end

    local sector = {}

    for i = 1, 512, 1 do
        local val = self.dma:channel_read(HDC_DMA, false)

        if band(val, 0x300) == 0x200 then
            hdc_error(self, ERR_NO_RECOVERY)
            command_complete(self)
            return
        end

        sector[i] = band(val, 0xFF)
    end

    drive.handler:write_sector(addr, sector)

    self.count = self.count - 1

    if self.count == 0 then
        self.state = STATE_RECEIVED_DATA
        self.operation = OPERATION_NONE
        self.dma:clear_service(HDC_DMA)
        command_complete(self)
        return
    end

    next_sector(self, drive)

    self.buffer_pos = 0
    self.buffer_count = 512
    self.status = bor(STATUS_BSY, STATUS_REQ)
    self.state = STATE_RECEIVE_DATA
end

local operations = {
    [OPERATION_READ] = operation_read,
    [OPERATION_WRITE] = operation_write
}

local function update_operation(self)
    if self.operation ~= OPERATION_NONE then
        local operation = operations[self.operation]
        operation(self)
    end
end

-- Commands
local function command_test_drive_ready(self)
    local drive = self.drives[self.drive_select]

    if not drive.present then
        hdc_error(self, ERR_NO_READY)
    end

    command_complete(self)
end

local function command_recalibrate_drive(self)
    if self.state == STATE_START_COMMAND then
        local drive = self.drives[self.drive_select]

        if not drive.present then
            hdc_error(self, ERR_NO_READY)
            command_complete(self)
            return
        end

        self.cylinder = 0
        drive.cylinder = 0
        command_complete(self)
    end
end

local function command_verify(self)
    if self.state == STATE_START_COMMAND then
        local drive = self.drives[self.drive_select]

        get_chs(self, drive)

        for _ = 0, self.count, 1 do
            if get_sector(self, drive) == -1 then
                hdc_error(self, self.last_error)
                command_complete(self)
                return
            end

            next_sector(self, drive)
        end

        command_complete(self)
    end
end

local function command_status(self)
    if self.state == STATE_START_COMMAND then
        self.buffer_pos = 0
        self.buffer_count = 4
        self.buffer[0] = bor(self.error, self.last_error)
        self.buffer[1] = bor(lshift(self.drive_select, 5), self.head)
        self.buffer[2] = bor(rshift(band(self.cylinder, 0x300), 2), self.sector)
        self.buffer[3] = band(self.cylinder, 0xFF)
        self.status = bor(STATUS_BSY, bor(STATUS_IO, STATUS_REQ))
        self.last_error = 0x00
        self.state = STATE_SEND_DATA
    elseif self.state == STATE_SENT_DATA then
        command_complete(self)
    end
end

local function command_format_drive(self)
    if self.state == STATE_START_COMMAND then
        local drive = self.drives[self.drive_select]

        get_chs(self, drive)
        local addr = get_sector(self, drive)

        if addr == -1 then
            hdc_error(self, self.last_error)
            command_complete(self)
            return
        end

        drive.handler:format(addr, (drive.cylinders - 1) * drive.heads * drive.sectors)
        drive.edited = true

        command_complete(self)
    end
end

local function command_format_track(self)
    if self.state == STATE_START_COMMAND then
        local drive = self.drives[self.drive_select]

        get_chs(self, drive)
        local addr = get_sector(self, drive)

        if addr == -1 then
            hdc_error(self, self.last_error)
            command_complete(self)
            return
        end

        drive.handler:format(addr, drive.sectors)
        drive.edited = true

        command_complete(self)
    end
end

local function command_read(self)
    if self.state == STATE_START_COMMAND then
        local drive = self.drives[self.drive_select]

        get_chs(self, drive)

        self.buffer_pos = 0
        self.buffer_count = 512
        self.status = bor(STATUS_BSY, bor(STATUS_IO, STATUS_REQ))
        self.state = STATE_SEND_DATA
        self.operation = OPERATION_READ

        if self.dma_enabled then
            self.dma:request_service(HDC_DMA)
        end
    end
end

local function command_write(self)
    if self.state == STATE_START_COMMAND then
        local drive = self.drives[self.drive_select]

        get_chs(self, drive)

        self.buffer_pos = 0
        self.buffer_count = 512
        self.status = bor(STATUS_BSY, bor(STATUS_IO, STATUS_REQ))
        self.state = STATE_RECEIVE_DATA
        self.operation = OPERATION_WRITE

        if self.dma_enabled then
            self.dma:request_service(HDC_DMA)
        end

        drive.edited = true
    end
end

local function command_seek(self)
    local drive = self.drives[self.drive_select]

    if drive.present then
        if not get_chs(self, drive) then
            hdc_error(self, ERR_SEEK_ERROR)
        end
    else
        hdc_error(self, ERR_NO_READY)
    end

    command_complete(self)
end

local function command_specify(self)
    local drive = self.drives[self.drive_select]

    if self.state == STATE_START_COMMAND then
        self.buffer_pos = 0
        self.buffer_count = 8
        self.status = bor(STATUS_BSY, STATUS_REQ)
        self.state = STATE_RECEIVE_DATA
    elseif self.state == STATE_RECEIVED_DATA then
        drive.cylinders = bor(self.buffer[1], lshift(self.buffer[0], 8))
        drive.heads = self.buffer[2]
        command_complete(self)
    end
end

local function command_read_buffer(self)
    if self.state == STATE_START_COMMAND then
        self.buffer_pos = 0
        self.buffer_count = 512
        self.status = bor(STATUS_BSY, bor(STATUS_IO, STATUS_REQ))

        if self.dma_enabled then
            self.dma:request_service(HDC_DMA)
        end

        for _ = 0, 511, 1 do
            self.dma:channel_write(HDC_DMA, self.buffer[self.buffer_pos])
            self.buffer_pos = self.buffer_pos + 1
        end

        self.dma:clear_service(HDC_DMA)
        command_complete(self)
    end
end

local function command_write_buffer(self)
    if self.state == STATE_START_COMMAND then
        self.buffer_pos = 0
        self.buffer_count = 512
        self.status = bor(STATUS_BSY, STATUS_REQ)

        if self.dma_enabled then
            self.dma:request_service(HDC_DMA)
        end

        for _ = 0, 511, 1 do
            local val = band(self.dma:channel_read(HDC_DMA), 0xFF)

            self.buffer[self.buffer_pos] = val
            self.buffer_pos = self.buffer_pos + 1
        end

        self.dma:clear_service(HDC_DMA)
        command_complete(self)
    end
end

local function command_ram_diagnistic(self)
    command_complete(self)
end

local function command_diagnistic(self)
    command_complete(self)
end

local commands = {
    [0x00] = command_test_drive_ready,
    [0x01] = command_recalibrate_drive,
    [0x03] = command_status,
    [0x04] = command_format_drive,
    [0x05] = command_verify,
    [0x06] = command_format_track,
    [0x07] = command_format_track,
    [0x08] = command_read,
    [0x0A] = command_write,
    [0x0B] = command_seek,
    [0x0C] = command_specify,
    [0x0E] = command_read_buffer,
    [0x0F] = command_write_buffer,
    [0xE0] = command_ram_diagnistic,
    [0xE4] = command_diagnistic
}

local function update(self)
    local command_id = self.command[0]
    local command = commands[command_id]

    self.drive_select = band(rshift(self.command[1], 5), 0x01)
    self.completion = rshift(self.drive_select, 5)

    if command_id ~= 3 then
        self.error = 0x00
    end

    if command then
        command(self)
    else
        logger:error("ST506: Unknown command 0x%02X", command_id)
        hdc_error(self, ERR_BAD_COMMAND)
        command_complete(self)
    end
end

-- Ports
local function port_data_out(self)
    return function(cpu, port, val)
        if self.state == STATE_RECEIVE_COMMAND then
            self.command[self.buffer_pos] = val
            self.buffer_pos = self.buffer_pos + 1

            if self.buffer_pos == self.buffer_count then
                self.buffer_count = 0
                self.buffer_pos = 0
                self.status = STATUS_BSY
                self.state = STATE_START_COMMAND
                update(self)
            end

            return
        elseif self.state == STATE_RECEIVE_DATA then
            self.buffer[self.buffer_pos] = val
            self.buffer_pos = self.buffer_pos + 1

            if self.buffer_pos == self.buffer_count then
                self.buffer_count = 0
                self.buffer_pos = 0
                self.status = STATUS_BSY
                self.state = STATE_RECEIVED_DATA
                update(self)
            end
        end
    end
end

local function port_data_in(self)
    return function(cpu, port)
        self.status = band(self.status, bnot(STATUS_IRQ))

        if self.state == STATE_COMPLETION_BYTE then
            self.status = 0x00
            self.state = STATE_IDLE
            return self.completion
        elseif self.state == STATE_SEND_DATA then
            local ret = self.buffer[self.buffer_pos]
            self.buffer_pos = self.buffer_pos + 1

            if self.buffer_pos == self.buffer_count then
                self.buffer_count = 0
                self.buffer_pos = 0
                self.status = STATUS_BSY
                self.state = STATE_SENT_DATA
                update(self)
            end

            return ret
        end

        return 0xFF
    end
end

local function port_status_out(self)
    return function(cpu, port, val)
        self.status = 0x00
    end
end

local function port_status_in(self)
    return function(cpu, port)
        return bor(self.status, (self.dma_enabled and self.dma:get_drq(HDC_DMA)) and 0x10 or 0x00)
    end
end

local function port_select_pulse_out(self)
    return function(cpu, port, val)
        self.status = bor(STATUS_BSY, bor(STATUS_CD, STATUS_REQ))
        self.buffer_pos = 0
        self.buffer_count = 6
        self.state = STATE_RECEIVE_COMMAND
    end
end

local function port_select_pulse_in(self)
    return function(cpu, port)
        return self.switches
    end
end

local function port_mask_register_out(self)
    return function(cpu, port, val)
        self.dma_enabled = band(val, 0x01) ~= 0
        self.irq_enabled = band(val, 0x02) ~= 0

        if not self.dma_enabled then
            self.dma:clear_service(HDC_DMA)
        end

        if not self.irq_enabled then
            self.status = band(self.status, bnot(STATUS_IRQ))
            self.pic:clear_interrupt(HDC_IRQ)
        end
    end
end

local function set_switches(self)
    self.switches = 0x00

    for i = 0, 1, 1 do
        local drive = self.drives[i]

        if drive.present then
            for c = 0, 3, 1 do
                local format = supported_formats[c]

                if (drive.cylinders == format[1]) and (drive.heads == format[2]) and (drive.sectors == format[3]) then
                    self.switches = bor(self.switches, lshift(c, lshift(bxor(i, 0x01), 1)))
                    break
                end
            end
        end
    end
end

local function insert_drive(self, num, path)
    local drive = self.drives[num]

    if drive then
        local file_ext = file.ext(path)
        local file_format = file_formats[file_ext]

        if file_format then
            local handler = file_format.load(path)

            drive.cylinders = handler.cylinders
            drive.heads = handler.heads
            drive.sectors = handler.sectors
            drive.handler = handler
            drive.present = true

            set_switches(self)
        else
            logger:error("HDC: Unsupported File Format: \"%s\"", num, file_ext)
        end
    else
        logger:error("HDC: Invalid Drive %d", num)
    end
end

local function initialize(self)
    for i = 0, 0x0FFF, 1 do
        self.rom[i] = HDC_ROM[i + 1]
    end

    self.rom[0x1000] = 0xFF
end

local function rom_read(self, addr)
    return self.rom[band(addr, 0x1FFF)]
end

local function rom_write(self, addr, val)
    self.rom[band(addr, 0x1FFF)] = val
end

local function reset(self)
    self.operation = OPERATION_NONE
    self.state = STATE_IDLE
    self.completion = 0x00
    self.status = 0x00
    self.buffer_pos = 0
    self.buffer_count = 0
    self.count = 0
    self.cylinder = 0
    self.head = 0
    self.sector = 0
    self.error = 0
    self.drive_select = 0
    self.last_error = 0
    self.irq_enabled = false
    self.dma_enabled = false
end

local function save(self)
    for i = 0, 1, 1 do
        local drive = self.drives[i]

        if drive.present and drive.edited then
            drive.handler:save()
        end
    end
end

function controller.new(cpu, memory, pic, dma)
    local self = {
        memory = memory,
        pic = pic,
        dma = dma,
        rom = {},
        command = {[0] = 0, 0, 0, 0, 0, 0},
        buffer = {[0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        drives = {},
        state = STATE_IDLE,
        operation = OPERATION_NONE,
        status = 0x00,
        completion = 0x00,
        switches = 0x00,
        buffer_pos = 0,
        buffer_count = 0,
        count = 0,
        cylinder = 0,
        head = 0,
        sector = 0,
        drive_select = 0,
        error = 0,
        last_error = 0,
        dma_enabled = false,
        irq_enabled = false,
        initialize = initialize,
        update = update_operation,
        insert_drive = insert_drive,
        save = save,
        reset = reset
    }

    init_drive(self, 0)
    init_drive(self, 1)

    local cpu_io = cpu:get_io()

    cpu_io:set_port(0x320, port_data_out(self), port_data_in(self))
    cpu_io:set_port(0x321, port_status_out(self), port_status_in(self))
    cpu_io:set_port(0x322, port_select_pulse_out(self), port_select_pulse_in(self))
    cpu_io:set_port_out(0x323, port_mask_register_out(self))

    memory:set_mapping(0xC8000, 0x1000, rom_read, rom_write, self)

    return self
end

return controller
