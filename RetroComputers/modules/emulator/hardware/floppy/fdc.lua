-- =====================================================================================================================================================================
-- NEC µPD765 Floppy Disk Controller emulation.
-- =====================================================================================================================================================================

local logger = require("dave_logger:logger")("RetroComputers")
local fdd_img = require("retro_computers:emulator/hardware/floppy/fdd_img")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local fdc = {}

local FDC_IRQ = 0x06
local FDC_DMA = 0x02

local FDC_STATUS_MRQ = 0x80
local FDC_STATUS_DIO = 0x40
local FDC_STATUS_NON_DMA_MODE = 0x20
local FDC_STATUS_BUSY = 0x10

local ST0_NORMAL_TERMINATION = 0x00
local ST0_ABNORMAL_TERMINATION = 0x40
local ST0_INVALID_OPCODE = 0x80
local ST0_ABNORMAL_POLLING = 0xD0
local ST0_HEAD_ACTIVE = 0x04
local ST0_NOT_READY = 0x08
local ST0_SEEK_END = 0x20
local ST0_RESET = 0xC0

local ST1_NOERROR = 0x00
local ST1_NODATA = 0x04
local ST1_WRITE_PROTECT = 0x02
local ST1_NO_ID = 0x01
local ST1_CRC_ERROR = 0x20

local ST3_WRITE_PROTECT = 0x40
local ST3_READY = 0x20
local ST3_TRACK0 = 0x10
local ST3_DOUBLESIDED = 0x08
local ST3_HEAD = 0x04

local OPERATION_NONE = 0
local OPERATION_READ  = 1
local OPERATION_WRITE = 2

local sector_sizes = {
    [0x00] = 128,
    [0x01] = 256,
    [0x02] = 512,
    [0x03] = 1024,
    [0x04] = 2048,
    [0x05] = 4096,
    [0x06] = 8192,
    [0x07] = 16384,
}

local file_formats = {
    ["img"] = fdd_img
}

local function fdc_send_int(self)
    self.pic:request_interrupt(FDC_IRQ)
    self.pending_interrupt = true
end

local function fdc_clear_int(self)
    self.pic:clear_interrupt(FDC_IRQ)
    self.pending_interrupt = false
end

local function send_results(self, drive_id, cylinder, head, sector, sector_size, code)
    local drive = self.drives[drive_id]
    local st0 = bor(drive_id, code)
    local st1 = self.last_error

    -- ST0
    if drive.head == 1 then
        st0 = bor(st0, ST0_HEAD_ACTIVE)
    end

    if (not drive.motor_enabled) or (not drive.present) then
        st0 = bor(st0, ST0_NOT_READY)
    end

    -- ST1
    if not drive.present then
        st1 = bor(st1, bor(ST1_NODATA, ST1_NO_ID))
    end

    self.out[0] = sector_size
    self.out[1] = sector
    self.out[2] = head
    self.out[3] = cylinder
    self.out[4] = 0x00
    self.out[5] = st1
    self.out[6] = st0
    self.params_out = 7
    self.last_error = ST1_NOERROR
    self.msr = bor(FDC_STATUS_BUSY, bor(FDC_STATUS_DIO, FDC_STATUS_MRQ))
end

local function end_rw_operation(self, drive, drive_id, cylinder, head, sector, sector_size, code)
    drive.cylinder = self.cylinder
    drive.head = self.head
    drive.sector = self.sector

    self.operation = OPERATION_NONE
    self.dma:clear_service(FDC_DMA)

    send_results(self, drive_id, cylinder, head, sector, sector_size, code)
    fdc_send_int(self)
end

-- Commands
local function command_specify(self)
    self.drq_enabled = band(self.params[1], 0x01) == 0
    return true
end

local function command_sense_interrupt_status(self)
    local st0
    local drive = self.drives[self.drive_select]

    if self.reset_flag then
        st0 = ST0_RESET
        self.reset_sense_count = 1
        self.reset_flag = false
    elseif self.last_command == 0x08 then
        if self.reset_sense_count < 4 then
            st0 = bor(ST0_RESET, band(self.reset_sense_count, 0x03))
            self.reset_sense_count = self.reset_sense_count + 1
        else
            self.reset_flag = false
            self.reset_sense_count = 0
            self.out[0] = ST0_INVALID_OPCODE
            self.params_out = 1
            goto continue
        end
    else
        if self.pending_interrupt then
            st0 = self.drive_select

            if drive.head == 1 then
                st0 = bor(st0, ST0_HEAD_ACTIVE)
            end

            if (not drive.motor_enabled) or (not drive.present) then
                st0 = bor(st0, ST0_NOT_READY)
            end

            if (self.last_command == 0x07) or (self.last_command == 0x0F) then
                st0 = bor(st0, ST0_SEEK_END)
            end

            if self.last_error ~= ST1_NOERROR then
                st0 = bor(st0, ST0_ABNORMAL_TERMINATION)
            end
        else
            self.out[0] = ST0_INVALID_OPCODE
            self.params_out = 1
            goto continue
        end
    end

    self.out[0] = drive.cylinder
    self.out[1] = st0
    self.params_out = 2

    ::continue::
    self.last_command = 0x08
    self.command = 0x00
    self.msr = bor(self.msr, bor(FDC_STATUS_BUSY, bor(FDC_STATUS_DIO, FDC_STATUS_MRQ)))
    fdc_clear_int(self)

    return false
end

local function command_recalibrate_drive(self)
    local drive_id = band(self.params[0], 0x03)
    local drive = self.drives[drive_id]

    if drive.seek then
        drive:seek(0)
    end

    self.drive_select = drive_id
    self.msr = bor(FDC_STATUS_MRQ, lshift(1, self.drive_select))
    fdc_send_int(self)

    return true
end

local function command_read_sector_id(self)
    local drive_id = band(self.params[0], 0x03)
    local drive = self.drives[self.drive_select]

    send_results(self, drive_id, drive.cylinder, drive.head, drive.sector, drive.sector_size, ST0_NORMAL_TERMINATION)
    fdc_send_int(self)

    return true
end

local function command_sense_drive_status(self)
    local drive_id = band(self.params[0], 0x03)
    local drive = self.drives[drive_id]
    local st3 = drive_id

    if drive.head == 1 then
        st3 = bor(st3, ST3_HEAD)
    end

    if drive.heads == 2 then
        st3 = bor(st3, ST3_DOUBLESIDED)
    end

    if drive.cylinder == 0 then
        st3 = bor(st3, ST3_TRACK0)
    end

    if drive.ready then
        st3 = bor(st3, ST3_READY)
    end

    if drive.write_protected then
        st3 = bor(st3, ST3_WRITE_PROTECT)
    end

    self.out[0] = st3
    self.msr = bor(band(self.msr, 0x0F), bor(FDC_STATUS_MRQ, bor(FDC_STATUS_BUSY, FDC_STATUS_DIO)))
    self.params_out = 1

    return true
end

local function command_read_data(self)
    local drive_id = band(self.params[0], 0x03)
    local drive = self.drives[drive_id]

    if not drive.present then
        return true
    end

    if self.drq_enabled then
        self.msr = bor(FDC_STATUS_DIO, FDC_STATUS_BUSY)
    else
        logger:error("FDC: Unsupported PIO mode!")
        return true
    end

    self.drive_select = drive_id
    self.cylinder = self.params[1]
    self.head = self.params[2]
    self.sector = self.params[3]
    self.sector_size = self.params[4]
    self.sectors = self.params[5]
    self.operation = OPERATION_READ

    drive.cylinder = self.cylinder
    drive.head = self.head
    drive.sector = self.sector

    return false
end

local function command_seek(self)
    local drive_id = band(self.params[0], 0x03)
    local drive = self.drives[drive_id]
    local cylinder = self.params[1]

    if drive.seek then
        drive:seek(cylinder)
    end

    self.drive_select = drive_id
    self.msr = bor(FDC_STATUS_MRQ, lshift(1, self.drive_select))
    self.last_error = ST1_NOERROR
    fdc_send_int(self)

    return true
end

local function command_write_data(self)
    local drive_id = band(self.params[0], 0x03)
    local drive = self.drives[drive_id]

    if not drive.present then
        return true
    end

    if self.drq_enabled then
        self.msr = FDC_STATUS_BUSY
    else
        logger:error("FDC: Unsupported PIO mode!")
        return true
    end

    self.drive_select = drive_id
    self.cylinder = self.params[1]
    self.head = self.params[2]
    self.sector = self.params[3]
    self.sector_size = self.params[4]
    self.sectors = self.params[5]

    if drive.write_protected then
        self.last_error = bor(ST1_WRITE_PROTECT, ST1_NO_ID)
        send_results(self, drive_id, self.cylinder, self.head, self.sector, self.sector_size, ST0_ABNORMAL_POLLING)

        self.operation = OPERATION_NONE
        fdc_send_int(self)
        return true
    end

    self.operation = OPERATION_WRITE
    drive.edited = true

    return false
end

local commands = {
    [0x03] = {2, command_specify},
    [0x04] = {1, command_sense_drive_status},
    [0x05] = {8, command_write_data},
    [0x06] = {8, command_read_data},
    [0x07] = {1, command_recalibrate_drive},
    [0x08] = {0, command_sense_interrupt_status},
    [0x0A] = {1, command_read_sector_id},
    [0x0F] = {2, command_seek}
}

local function advance_sector(self, drive)
    if self.sector == self.sectors then
        if not self.mt then
            self.cylinder = self.cylinder + 1
            self.sector = 1

            end_rw_operation(self, drive, self.drive_select, self.cylinder, self.head, self.sector, self.sector_size, ST0_NORMAL_TERMINATION)
            return
        end

        if self.head == 1 then
            self.cylinder = self.cylinder + 1
            self.head = band(self.head, 0xFE)
            self.sector = 1

            drive.head = 0

            end_rw_operation(self, drive, self.drive_select, self.cylinder, self.head, self.sector, self.sector_size, ST0_NORMAL_TERMINATION)
            return
        else
            self.sector = 1
            self.head = 1

            if (drive.heads == 1) and (self.head == 1) then
                drive.head = 0
            else
                drive.head = self.head
            end
        end
    elseif (self.sector < self.sectors) or (self.sectors == 0) then
        self.sector = self.sector + 1
    end
end

-- Operations
local function operation_read_data(self)
    local drive = self.drives[self.drive_select]
    local sector_size = sector_sizes[self.sector_size]

    if (self.sector > drive.sectors) or (self.head > drive.heads) or (self.cylinder > drive.cylinders) then
        self.operation = OPERATION_NONE
        self.last_error = ST1_NO_ID
        end_rw_operation(self, drive, self.drive_select, drive.cylinder, drive.head, drive.sector, sector_size, ST0_ABNORMAL_TERMINATION)
        fdc_send_int(self)
        return
    end

    local buffer = drive:read_sector(self.cylinder, self.head, self.sector, sector_size)

    self.dma:request_service(FDC_DMA)
    self.msr = bor(FDC_STATUS_DIO, FDC_STATUS_BUSY)

    for i = 1, sector_size, 1 do
        local status = self.dma:channel_write(FDC_DMA, buffer[i], false)

        if status == 0x100 then
            if self.sector == self.sectors then
                if not self.mt then
                    self.cylinder = self.cylinder + 1
                    self.sector = 1
                else
                    if self.head ~= 0 then
                        self.cylinder = self.cylinder + 1
                    end

                    self.head = bxor(self.head, 0x01)
                    self.sector = 1

                    if (drive.heads == 1) and (self.head == 1) then
                        drive.head = 0
                    else
                        drive.head = self.head
                    end
                end
            else
                self.sector = self.sector + 1
            end

            end_rw_operation(self, drive, self.drive_select, self.cylinder, self.head, self.sector, self.sector_size, ST0_NORMAL_TERMINATION)
            return
        end
    end

    advance_sector(self, drive)
end

local function operation_write_data(self)
    local drive = self.drives[self.drive_select]
    local sector_size = sector_sizes[self.sector_size]
    local buffer = {}

    if (self.sector > drive.sectors) or (self.head > drive.heads) or (self.cylinder > drive.cylinders) then
        self.operation = OPERATION_NONE
        self.last_error = ST1_NO_ID
        end_rw_operation(self, drive, self.drive_select, drive.cylinder, drive.head, drive.sector, sector_size, ST0_ABNORMAL_TERMINATION)
        fdc_send_int(self)
        return
    end

    self.msr = FDC_STATUS_BUSY
    self.dma:request_service(FDC_DMA)

    for i = 1, sector_size, 1 do
        local result = self.dma:channel_read(FDC_DMA, false)

        buffer[i] = band(result, 0xFF)

        if band(result, 0x100) == 0x100 then
            drive:write_sector(self.cylinder, self.head, self.sector, buffer)

            if self.sector == self.sectors then
                if not self.mt then
                    self.cylinder = self.cylinder + 1
                    self.sector = 1
                else
                    if self.head ~= 0 then
                        self.cylinder = self.cylinder + 1
                    end

                    self.head = bxor(self.head, 0x01)
                    self.sector = 1

                    if (drive.heads == 1) and (self.head == 1) then
                        drive.head = 0
                    else
                        drive.head = self.head
                    end
                end
            else
                self.sector = self.sector + 1
            end

            end_rw_operation(self, drive, self.drive_select, self.cylinder, self.head, self.sector, self.sector_size, ST0_NORMAL_TERMINATION)
            return
        end
    end

    drive:write_sector(self.cylinder, self.head, self.sector, buffer)
    advance_sector(self, drive)
end

local operations = {
    [OPERATION_READ] = operation_read_data,
    [OPERATION_WRITE] = operation_write_data
}

-- Ports
local function port_dor_out(self)
    return function(cpu, port, val)
        if band(val, 0x04) == 0 then
            self.params_num = 0
            self.params_in = 0
            self.msr = 0x00
        elseif band(self.dor, 0x04) == 0 then
            self.params_num = 0
            self.params_in = 0
            self.reset_sense_count = 0
            self.drive_select = 0
            self.msr = FDC_STATUS_MRQ
            self.reset_flag = true

            fdc_send_int(self)
        end

        self.drq_enabled = band(val, 0x08) ~= 0
        self.drive_select = band(val, 0x03)
        self.dor = val

        for i = 0, 3, 1 do
            self.drives[i].motor_enabled = band(val, lshift(0x10, self.drive_select)) ~= 0
        end
    end
end

local function port_msr_in(self)
    return function(cpu, port)
        return self.msr
    end
end

local function port_command_register_out(self)
    return function(cpu, port, val)
        if self.params_num == self.params_in then
            self.command = band(val, 0x1F)
            self.mt = band(val, 0x80) ~= 0

            local command = commands[self.command]

            if command then
                self.last_error = ST1_NOERROR
                self.params_in = command[1]
                self.params_out = 0
                self.params_num = 0
                self.command_function = command[2]

                if self.command == 0x08 then
                    self.command_function(self)
                end
            else
                logger:error("FDC: Unknown Command 0x%02X", self.command)
            end
        else
            self.params[self.params_num] = val
            self.params_num = self.params_num + 1

            if self.params_num == self.params_in then
                local result = self.command_function(self)

                if result then
                    self.command_function = function() end
                    self.last_command = self.command
                    self.command = 0x00
                end
            end
        end
    end
end

local function port_command_register_in(self)
    return function(cpu, port)
        self.msr = band(self.msr, 0xF0)

        if self.params_out > 0 then
            self.msr = band(self.msr, bnot(FDC_STATUS_MRQ))
            self.params_out = self.params_out - 1

            if self.params_out == 0 then
                self.msr = FDC_STATUS_MRQ
            else
                self.msr = bor(self.msr, bor(FDC_STATUS_MRQ, FDC_STATUS_DIO))
            end

            return self.out[self.params_out]
        end

        return 0x00
    end
end

-- Other
local function update(self)
    if self.operation ~= OPERATION_NONE then
        operations[self.operation](self)
    end
end

local function insert_drive(self, num, path, write_protected)
    local drive = self.drives[num]

    if drive then
        local file_ext = file.ext(path)
        local file_format = file_formats[file_ext]

        if file_format then
            local ok, result = pcall(file_format.load, path)

            if ok then
                drive.cylinders = result.cylinders
                drive.heads = result.heads
                drive.sectors = result.sectors
                drive.sector_size = result.sector_size
                drive.seek = function(_, cylinder)
                    drive.cylinder = cylinder
                end
                drive.read_sector = result.read_sector
                drive.write_sector = result.write_sector
                drive.save = result.save
                drive.write_protected = write_protected
                drive.present = true
            else
                logger:error("FDC: Load File Error: \"%s\"", result)
            end
        else
            logger:error("FDC: Unsupported File Format: \"%s\"", file_ext)
        end
    else
        logger:error("FDC: Invalid Drive %d", num)
    end
end

local function eject_drive(self, num)
    local drive = self.drives[num]

    if drive then
        drive.present = false

        if drive.edited then
            drive.edited = false
            drive:save()
        end

        drive.seek = nil
        drive.read_sector = nil
        drive.write_sector = nil
        drive.save = nil
    else
        logger:error("FDC: Invalid Drive %d", num)
    end
end

local function init_drive(self, drive_num)
    self.drives[drive_num] = {
        cylinders = 0,
        heads = 0,
        sectors = 0,
        sector_size = 0,
        cylinder = 0,
        head = 0,
        sector = 0,
        ready = true,
        present = false,
        motor_enabled = false,
        write_protected = false,
        edited = false
    }
end

local function reset_drive(self, num)
    local drive = self.drives[num]

    drive.motor_enabled = false
    drive.cylinder = 0
    drive.head = 0
    drive.sector = 0
end

local function reset(self)
    self.params_in = 0
    self.params_out = 0
    self.params_num = 0
    self.dor = 0
    self.msr = 0x80
    self.command = 0
    self.last_command = 0
    self.reset_sense_count = 0
    self.drive_select = 0
    self.sectors = 0
    self.cylinder = 0
    self.head = 0
    self.sector = 0
    self.sector_size = 0
    self.operation = OPERATION_NONE
    self.last_error = 0
    self.reset_flag = false
    self.mt = false
    self.drq_enabled = false
    self.pending_interrupt = false

    reset_drive(self, 0)
    reset_drive(self, 1)
    reset_drive(self, 2)
    reset_drive(self, 3)
end

local function save(self)
    for i = 0, 3, 1 do
        local drive = self.drives[i]

        if drive.edited then
            drive:save()
        end
    end
end

function fdc.new(cpu, pic, dma)
    local self = {
        pic = pic,
        dma = dma,
        params = {[0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        out = {[0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        drives = {},
        params_in = 0,
        params_out = 0,
        params_num = 0,
        dor = 0, -- Digital Output Register
        msr = 0x80, -- Main Status Register
        command = 0,
        last_command = 0x00,
        reset_sense_count = 0,
        drive_select = 0,
        cylinder = 0,
        head = 0,
        sector = 0,
        sector_size = 0,
        sectors = 0,
        operation = OPERATION_NONE,
        last_error = 0,
        mt = false,
        reset_flag = false,
        drq_enabled = false,
        pending_interrupt = false,
        command_function = function() end,
        insert_drive = insert_drive,
        eject_drive = eject_drive,
        update = update,
        save = save,
        reset = reset
    }

    local cpu_io = cpu:get_io()

    cpu_io:set_port_out(0x3F2, port_dor_out(self))
    cpu_io:set_port_in(0x3F4, port_msr_in(self))
    cpu_io:set_port(0x3F5, port_command_register_out(self), port_command_register_in(self))

    init_drive(self, 0)
    init_drive(self, 1)
    init_drive(self, 2)
    init_drive(self, 3)

    return self
end

return fdc
