local logger = require("retro_computers:logger")
local filesystem = require("retro_computers:emulator/filesystem")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

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

local fdc = {}

local function interrupt(self)
    if self.drq_enabled then
        self.pic:request_interrupt(0x40, true)
    end
end

local function send_results(self, drive_id, cylinder, head, sector, sector_size, code)
    local drive = self.drives[drive_id]

    -- ST0
    local st0 = bor(drive_id, code)

    if drive.head == 1 then
        st0 = bor(st0, 0x04)
    end

    if (not drive.motor_enabled) or (not drive.present) then
        st0 = bor(st0, 0x08)
    end

    -- ST1
    local st1 = self.last_error

    if not drive.present then
        st1 = bor(st1, 0x05)
    end

    -- OUT
    self.out[0] = sector_size
    self.out[1] = sector
    self.out[2] = head
    self.out[3] = cylinder
    self.out[4] = 0x00
    self.out[5] = st1
    self.out[6] = st0
    self.params_out = 7
    self.last_error = 0x00
    self.msr = 0xD0
end

local function end_rw_operation(self, drive, drive_id, cylinder, head, sector, sector_size, code)
    drive.cylinder = self.cylinder
    drive.head = self.head
    drive.sector = self.sector
    self.msr = bor(self.msr, 0x20)
    self.operation = 0x00

    send_results(self, drive_id, cylinder, head, sector, sector_size, code)
    interrupt(self)
end

-- Commands
local function command_specify(self)
    return true
end

local function command_sense_interrupt_status(self)
    local st0 = 0x80
    local drive = self.drives[self.drive_select]

    if self.reset_flag then
        st0 = 0xC0
        self.reset_sense_count = 1
        self.reset_flag = false
    elseif self.last_command == 0x08 then
        if self.reset_sense_count < 4 then
            st0 = bor(bor(st0, 0xC0), band(self.reset_sense_count, 0x03))
            self.reset_sense_count = self.reset_sense_count + 1
        else
            st0 = 0x80
            self.reset_flag = false
            self.reset_sense_count = 0
        end
    else
        st0 = bor(self.drive_select, self.last_error)

        if drive.head == 1 then
            st0 = bor(st0, 0x04)
        end

        if (not drive.motor_enabled) or (not drive.present) then
            st0 = bor(st0, 0x08)
        end

        if (self.last_command == 0x07) or (self.last_command == 0x0F) then
            st0 = bor(st0, 0x20)
        end
    end

    self.out[0] = drive.cylinder
    self.out[1] = st0
    self.params_out = 2
    self.last_command = 0x08
    self.command = 0x00
    self.msr = bor(self.msr, 0xD0)
    self.pic:request_interrupt(0x40, false)

    return false
end

local function command_recalibrate_drive(self)
    local drive_id = band(self.params[0], 0x03)
    local drive = self.drives[drive_id]

    self.drive_select = drive_id

    if drive.handler then
        drive.handler:seek(0)
    end

    interrupt(self)

    return true
end

local function command_read_sector_id(self)
    local drive_id = band(self.params[0], 0x03)
    local drive = self.drives[self.drive_select]

    send_results(self, drive_id, drive.cylinder, drive.head, drive.head, drive.sector_size, 0x00)
    interrupt(self)

    return true
end

local function command_sense_drive_status(self)
    local drive_id = band(self.params[0], 0x03)
    local drive = self.drives[drive_id]

    -- ST3
    self.out[0] = drive_id

    if drive.head == 1 then
        self.out[0] = bor(self.out[0], 0x04)
    end

    if drive.heads == 2 then
        self.out[0] = bor(self.out[0], 0x08)
    end

    if drive.cylinder == 0 then
        self.out[0] = bor(self.out[0], 0x10)
    end

    if drive.motor_enabled then
        self.out[0] = bor(self.out[0], 0x20)
    end

    if drive.write_protected then
        self.out[0] = bor(self.out[0], 0x40)
    end

    self.msr = bor(band(self.msr, 0x0F), 0xD0)
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
        self.msr = band(self.msr, 0x7F)
    else
        logger.error("FDC: Unsupported PIO mode!")
        return false
    end

    self.drive_select = drive_id
    self.cylinder = self.params[1]
    self.head = self.params[2]
    self.sector = self.params[3]
    self.sector_size = self.params[4]
    self.sectors = self.params[5]
    self.operation = 0x01

    return false
end

local function command_seek(self)
    local drive_id = band(self.params[0], 0x03)
    local drive = self.drives[drive_id]
    local cylinder = self.params[1]

    if drive.handler then
        drive.handler:seek(cylinder)
    end

    self.drive_select = drive_id

    interrupt(self)
    return true
end

local function command_write_data(self)
    local drive_id = band(self.params[0], 0x03)
    local drive = self.drives[drive_id]
    self.drive_select = drive_id

    if not drive.present then
        return true
    end

    if self.drq_enabled then
        self.msr = band(self.msr, 0x7F)
    else
        logger.error("FDC: Unsupported PIO mode!")
        return
    end

    self.cylinder = self.params[1]
    self.head = self.params[2]
    self.sector = self.params[3]
    self.sector_size = self.params[4]
    self.sectors = self.params[5]

    if drive.write_protected then
        self.operation = 0x00
        self.last_error = 0x03
        send_results(self, drive_id, self.cylinder, self.head, self.sector, self.sector_size, 0xC0)
        interrupt(self)
        return true
    end

    self.operation = 0x02

    drive.edited = true

    return false
end

-- [Command_ID] = {params_in, function}
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

-- Operations
local function operation_read_data(self)
    local drive = self.drives[self.drive_select]
    local sector_size = sector_sizes[self.sector_size]

    local buffer = drive.handler:read_sector(self.cylinder, self.head, self.sector, sector_size)
    self.msr = 0x50

    for i = 1, sector_size, 1 do
        local status = self.dma:channel_write(2, buffer[i])

        if status == 0x100 then
            end_rw_operation(self, drive, self.drive_select, self.cylinder, self.head, self.sector, self.sector_size, 0x00)
            return
        end
    end

    if self.sector == self.sectors then
        if self.head == 1 then
            self.cylinder = self.cylinder + 1
            self.head = 0
            self.sector = 1

            end_rw_operation(self, drive, self.drive_select, self.cylinder, self.head, self.sector, self.sector_size, 0x00)
            return
        else
            self.sector = 1
            self.head = 1
        end
    elseif self.sector < self.sectors then
        self.sector = self.sector + 1
    end
end

local function operation_write_data(self)
    local drive = self.drives[self.drive_select]
    local buffer = {}

    self.msr = 0x10

    for i = 1, sector_sizes[self.sector_size], 1 do
        local result = self.dma:channel_read(2)

        buffer[i] = band(result, 0xFF)

        if band(result, 0x100) == 0x100 then
            drive.handler:write_sector(self.cylinder, self.head, self.sector, buffer)
            end_rw_operation(self, drive, self.drive_select, self.cylinder, self.head, self.sector, self.sector_size, 0x00)
            return
        end
    end

    drive.handler:write_sector(self.cylinder, self.head, self.sector, buffer)

    if self.sector == self.sectors then
        if self.head == 1 then
            self.cylinder = self.cylinder + 1
            self.head = 0
            self.sector = 1

            end_rw_operation(self, drive, self.drive_select, self.cylinder, self.head, self.sector, self.sector_size, 0x00)
            return
        else
            self.sector = 1
            self.head = 1
        end
    elseif self.sector < self.sectors then
        self.sector = self.sector + 1
    end
end

local operations = {
    [0x01] = operation_read_data,
    [0x02] = operation_write_data
}

-- Ports
local function port_3F2(self) -- DOR
    return function(cpu, port, val)
        if val then
            if band(val, 0x04) == 0 then
                self.params_num = 0
                self.params_in = 0
                self.msr = 0x00
            elseif band(self.dor, 0x04) == 0 then
                self.reset_sense_count = 0
                self.reset_flag = true
                self.drive_select = 0
                self.msr = 0x80
                interrupt(self)
            end

            local drive_num = band(val, 0x03)

            for i = 0, 1, 1 do
                self.drives[i].motor_enabled = band(val, lshift(0x10, drive_num)) ~= 0
            end

            self.drq_enabled = band(val, 0x08) ~= 0
            self.drive_select = drive_num

            self.dor = val
        else
            return 0xFF
        end
    end
end

local function port_3F4(self) -- DSR
    return function(cpu, port, val)
        if not val then
            return self.msr
        end
    end
end

local function port_3F5(self) -- Command register
    return function(cpu, port, val)
        if val then
            if self.params_num == self.params_in then
                self.command = band(val, 0x1F)

                local command = commands[self.command]

                if command then
                    self.last_error = 0x00
                    self.params_in = command[1]
                    self.params_out = 0
                    self.params_num = 0
                    self.command_function = command[2]

                    if self.command == 0x08 then
                        self.command_function(self)
                    end
                else
                    logger.error("FDC: Unknown Command 0x%02X", self.command)
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
        else
            if self.params_out > 0 then
                self.msr = band(self.msr, bnot(0x80))

                self.params_out = self.params_out - 1

                if self.params_out == 0 then
                    self.msr = 0x80
                else
                    self.msr = bor(self.msr, 0xC0)
                end

                return self.out[self.params_out]
            end

            return 0x00
        end
    end
end

local function port_3F7(self) -- Digital Input Register
    return function(cpu, port, val)
        if not val then
            return 0x00
        end
    end
end

-- Other
local function update(self)
    if self.operation > 0 then
        operations[self.operation](self)
    end
end

local function insert_drive(self, num, path, write_protected)
    local drive = self.drives[num]

    if drive then
        local stream = filesystem.open(path, false)

        if stream then
            local file_size = file.length(path)

            drive.heads = 2
            drive.sector_size = 512

            if file_size == 163840 then
                drive.sectors = 8
                drive.cylinders = 40
                drive.heads = 1
            elseif file_size == 184320 then
                drive.sectors = 9
                drive.cylinders = 40
                drive.heads = 1
            elseif file_size == 322560 then
                drive.sectors = 9
                drive.cylinders = 70
                drive.heads = 1
            elseif file_size == 327680 then
                drive.sectors = 8
                drive.cylinders = 40
            elseif file_size == 368640 then
                drive.sectors = 9
                drive.cylinders = 40
            elseif file_size == 409600 then
                drive.sectors = 10
                drive.cylinders = 80
                drive.heads = 1
            elseif file_size == 655360 then
                drive.sectors = 8
                drive.cylinders = 80
            elseif file_size == 737280 then
                drive.sectors = 9
                drive.cylinders = 80
            elseif file_size == 819200 then
                drive.sectors = 10
                drive.cylinders = 80
            elseif file_size == 827392 then
                drive.sectors = 11
                drive.cylinders = 80
            elseif file_size == 983040 then
                drive.sectors = 12
                drive.cylinders = 80
            elseif file_size == 1064960 then
                drive.sectors = 13
                drive.cylinders = 80
            elseif file_size == 1146880 then
                drive.sectors = 14
                drive.cylinders = 80
            elseif file_size == 1228800 then
                drive.sectors = 15
                drive.cylinders = 80
            elseif file_size == 1474560 then
                drive.sectors = 18
                drive.cylinders = 80
            elseif file_size == 1556480 then
                drive.sectors = 19
                drive.cylinders = 80
            elseif file_size == 1720320 then
                drive.sectors = 21
                drive.cylinders = 80
            elseif file_size == 1741824 then
                drive.sectors = 21
                drive.cylinders = 81
            elseif file_size == 1763328 then
                drive.sectors = 21
                drive.cylinders = 82
            elseif file_size == 1884160 then
                drive.sectors = 23
                drive.cylinders = 80
            elseif file_size == 2949120 then
                drive.sectors = 36
                drive.cylinders = 80
            else
                logger.error("FDC: Drive %d: Unknown floppy size", num)
                return
            end

            drive.handler = {
                seek = function(_, cylinder)
                    drive.cylinder = cylinder
                end,
                read_sector = function(_, cylinder, head, sector, sector_size)
                    stream:set_position(((cylinder * drive.heads + head) * drive.sectors + (sector - 1)) * drive.sector_size)
                    return stream:read_bytes(sector_size)
                end,
                write_sector = function(_, cylinder, head, sector, data)
                    stream:set_position(((cylinder * drive.heads + head) * drive.sectors + (sector - 1)) * drive.sector_size)
                    stream:write_bytes(data)
                end,
                save = function(_)
                    stream:flush()
                end
            }

            drive.write_protected = write_protected
            drive.present = true
        else
            logger.error("FDC: Drive %d: File \"%s\" not found", num, path)
        end
    else
        logger.error("FDC: Invalid Drive %d", num)
    end
end

local function eject_drive(self, num)
    local drive = self.drives[num]

    if drive then
        drive.present = false
        drive.handler = nil
    else
        logger.error("FDC: Invalid Drive %d", num)
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
        present = false,
        motor_enabled = false,
        write_protected = false,
        edited = false
    }
end

local function reset_drive(self, num)
    local drive = self.drives[num]
    drive.motor_enabled = false
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
    self.operation = 0
    self.drq_enabled = false
    self.last_error = 0

    reset_drive(self, 0)
    reset_drive(self, 1)
    reset_drive(self, 2)
    reset_drive(self, 3)
end

local function save(self)
    for i = 0, 3, 1 do
        local drive = self.drives[i]

        if drive.edited then
            drive.handler:save()
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
        operation = 0,
        last_error = 0,
        drq_enabled = false,
        command_function = function() end,
        insert_drive = insert_drive,
        eject_drive = eject_drive,
        update = update,
        save = save,
        reset = reset
    }

    cpu:set_port(0x3F2, port_3F2(self))
    cpu:set_port(0x3F4, port_3F4(self))
    cpu:set_port(0x3F5, port_3F5(self))
    cpu:set_port(0x3F7, port_3F7(self))

    init_drive(self, 0)
    init_drive(self, 1)
    init_drive(self, 2)
    init_drive(self, 3)

    return self
end

return fdc