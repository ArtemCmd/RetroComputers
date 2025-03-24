local logger = require("retro_computers:logger")
local filesystem = require("retro_computers:emulator/filesystem")
local hdf = require("retro_computers:emulator/hardware/disk/hdd_hdf")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local STATE_IDLE = 0
local STATE_RECEIVE_COMMAND = 1
local STATE_START_COMMAND = 2
local STATE_RECEIVE_DATA = 3
local STATE_RECEIVED_DATA = 4
local STATE_SEND_DATA = 5
local STATE_SENT_DATA = 6
local STATE_COMPLETION_BYTE = 7

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
        self.last_error = 0x04
        return -1
    end

    if self.head >= drive.heads then
        self.last_error = 0x21
        return -1
    end

    if self.sector >= drive.sectors then
        self.last_error = 0x21
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
    self.status = 0x0F
    self.state = STATE_COMPLETION_BYTE

    if self.dma_enabled then
        self.dma:clear_service(3)
    end

    if self.irq_enabled then
        self.status = bor(self.status, 0x20)
        self.pic:request_interrupt(0x20, true)
    end
end

-- Commands
local function command_test_drive_ready(self)
    local drive = self.drives[self.drive_select]

    if not drive.present then
        hdc_error(self, 0x04)
    end

    command_complete(self)
end

local function command_recalibrate_drive(self)
    local drive = self.drives[self.drive_select]

    if self.state == STATE_START_COMMAND then
        if not drive.present then
            hdc_error(self, 0x04)
            command_complete(self)
            return
        end

        self.cylinder = 0
        drive.cylinder = 0
        self.state = STATE_IDLE
        command_complete(self)
    end
end

local function command_verify(self)
    local drive = self.drives[self.drive_select]

    if self.state == STATE_START_COMMAND then
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
        self.status = 0x0B
        self.last_error = 0x00
        self.state = STATE_SEND_DATA
    elseif self.state == STATE_SENT_DATA then
        command_complete(self)
    end
end

local function command_read(self)
    local drive = self.drives[self.drive_select]

    if self.state == STATE_START_COMMAND then
        get_chs(self, drive)

        self.buffer_pos = 0
        self.buffer_count = 512
        self.status = 0x0B
        self.state = STATE_SEND_DATA
        self.operation = 0x01
    end
end

local function command_write(self)
    local drive = self.drives[self.drive_select]

    if self.state == STATE_START_COMMAND then
        get_chs(self, drive)

        self.buffer_pos = 0
        self.buffer_count = 512
        self.status = 0x09
        self.state = STATE_RECEIVED_DATA
        self.operation = 0x02

        drive.edited = true
    end
end

local function command_seek(self)
    local drive = self.drives[self.drive_select]

    if drive.present then
        if not get_chs(self, drive) then
            hdc_error(self, 0x15)
        end
    else
        hdc_error(self, 0x04)
    end

    command_complete(self)
end

local function command_specify(self)
    local drive = self.drives[self.drive_select]

    if self.state == STATE_START_COMMAND then
        self.buffer_pos = 0
        self.buffer_count = 8
        self.status = 0x09
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
        self.status = 0x0B

        for _ = 0, 511, 1 do
            self.dma:channel_write(3, self.buffer[self.buffer_pos])
            self.buffer_pos = self.buffer_pos + 1
        end

        self.dma:clear_service(3)
        self.state = STATE_SENT_DATA
        command_complete(self)
    end
end

local function command_write_buffer(self)
    if self.state == STATE_START_COMMAND then
        self.buffer_pos = 0
        self.buffer_count = 512
        self.status = 0x09

        for _ = 0, 511, 1 do
            local val = band(self.dma:channel_read(3), 0xFF)
            self.buffer[self.buffer_pos] = val
            self.buffer_pos = self.buffer_pos + 1
        end

        self.dma:clear_service(3)
        self.state = STATE_RECEIVED_DATA
        command_complete(self)
        return
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
    [0x05] = command_verify,
    [0x08] = command_read,
    [0x0A] = command_write,
    [0x0B] = command_seek,
    [0x0C] = command_specify,
    [0x0E] = command_read_buffer,
    [0x0F] = command_write_buffer,
    [0xE0] = command_ram_diagnistic,
    [0xE4] = command_diagnistic
}

-- Operation
local function operation_read(self)
    local drive = self.drives[self.drive_select]
    local addr = get_sector(self, drive)

    if addr == -1 then
        self.operation = 0x00
        hdc_error(self, self.last_error)
        command_complete(self)
        return
    end

    local sector = drive.handler:read_sector(addr)
    -- logger.debug("HDC: Drive %d: Read sector from CHS = %d:%d:%d", self.drive_select, self.cylinder, self.head, self.sector)

    for i = 0, 511, 1 do
        local val = sector[i + 1]
        self.buffer[i] = val
        self.dma:channel_write(3, val)
    end

    self.count = self.count - 1

    if self.count == 0 then
        self.operation = 0x00
        command_complete(self)
        return
    end

    next_sector(self, drive)

    self.buffer_pos = 0
    self.buffer_count = 512
    self.status = 0x0B
    self.state = STATE_SEND_DATA
end

local function operation_write(self)
    local drive = self.drives[self.drive_select]
    local addr = get_sector(self, drive)

    if addr == -1 then
        self.operation = 0x00
        hdc_error(self, 0x22)
        command_complete(self)
        return
    end

    local sector = {}

    for i = 1, 512, 1 do
        local val = self.dma:channel_read(3)
        sector[i] = band(val, 0xFF)
    end

    drive.handler:write_sector(addr, sector)
    -- logger.debug("HDC: Drive %d: Write sector to CHS = %d:%d:%d", self.drive_select, self.cylinder, self.head, self.sector)

    self.count = self.count - 1

    if self.count == 0 then
        self.operation = 0x00
        command_complete(self)
        return
    end

    next_sector(self, drive)

    self.buffer_pos = 0
    self.buffer_count = 512
    self.status = 0x09
    self.state = STATE_RECEIVE_DATA
end

local operations = {
    [0x01] = operation_read,
    [0x02] = operation_write
}

-- Other
local function update(self)
    local drive_num = band(rshift(self.command[1], 5), 0x01)
    local command_id = self.command[0]
    local command = commands[command_id]

    self.completion = rshift(drive_num, 5)
    self.drive_select = drive_num

    if command_id ~= 3 then
        self.error = 0x00
    end

    if command then
        command(self)
    else
        logger.error("ST506: Unknown command 0x%02X", command_id)
        hdc_error(self, 0x20)
        command_complete(self)
    end
end

-- Ports
local function port_320(self) -- Data Register
    return function(cpu, port, val)
        if val then
            if self.state == STATE_RECEIVE_COMMAND then
                self.command[self.buffer_pos] = val
                self.buffer_pos = self.buffer_pos + 1

                if self.buffer_pos == self.buffer_count then
                    self.buffer_count = 0
                    self.buffer_pos = 0
                    self.status = 0x08
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
                    self.status = 0x08
                    self.state = STATE_RECEIVED_DATA
                    update(self)
                end
                return
            end
        else
            self.status = band(self.status, bnot(0x20))

            if self.state == STATE_COMPLETION_BYTE then
                self.status = 0x00
                self.state = STATE_IDLE
                return self.completion
            elseif self.state == STATE_SEND_DATA then
                local ret = self.buffer[self.buffer_pos] or 0x00
                self.buffer_pos = self.buffer_pos + 1

                if self.buffer_pos == self.buffer_count then
                    self.buffer_count = 0
                    self.buffer_pos = 0
                    self.status = 0x08
                    self.state = STATE_SENT_DATA
                    update(self)
                end

                return ret
            end

            return 0xFF
        end
    end
end

local function port_321(self) -- Status Register
    return function(cpu, port, val)
        if val then
            self.status = 0x00
        else
            return bor(self.status, self.dma_enabled and 0x10 or 0x00)
        end
    end
end

local function port_322(self) -- DIP Register
    return function(cpu, port, val)
        if val then
            self.status = 0x0D
            self.buffer_pos = 0
            self.buffer_count = 6
            self.state = STATE_RECEIVE_COMMAND
        else
            return 0x0A
        end
    end
end

local function port_323(self) -- Mask Regsiter
    return function(cpu, port, val)
        if val then
            self.dma_enabled = band(val, 0x01) ~= 0
            self.irq_enabled = band(val, 0x02) ~= 0

            if not self.dma_enabled then
                self.dma:clear_service(3)
            end

            if not self.irq_enabled then
                self.pic:request_interrupt(0x20, false)
            end
        else
            return 0xFF
        end
    end
end

-- Other
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

local function insert_drive(self, num, path)
    local drive = self.drives[num]

    if drive then
        local stream = hdf.load(path)

        drive.cylinders = stream.cylinders
        drive.heads = stream.heads
        drive.sectors = stream.sectors

        drive.handler = {
            read_sector = stream.read_sector,
            write_sector = stream.write_sector,
            save = stream.save
        }

        drive.present = true
    else
        logger.error("HDC: Invalid Drive %d", num)
    end
end

local function initialize(self)
    local stream = filesystem.open("retro_computers:modules/emulator/roms/hdd/ibm_xebec_62x0822_1985.bin", false)

    if stream then
        local bios = stream:get_buffer()

        for i = 0, #bios - 1, 1 do
            self.memory[0xC8000 + i] = bios[i + 1]
        end
    end
end

local function update_operation(self)
    if self.operation > 0 then
        local operation = operations[self.operation]
        operation(self)
    end
end

local function reset(self)
    self.status = 0x00
    self.state = 0
    self.buffer_pos = 0
    self.buffer_count = 0
    self.completion = 0x00
    self.cylinder = 0
    self.head = 0
    self.sector = 0
    self.error = 0
    self.drive_select = 0
    self.operation = 0
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

local controller = {}

function controller.new(cpu, memory, pic, dma)
    local self = {
        memory = memory,
        pic = pic,
        dma = dma,
        command = {[0] = 0, 0, 0, 0, 0, 0},
        buffer = {[0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        drives = {},
        status = 0x00,
        state = 0,
        buffer_pos = 0,
        buffer_count = 0,
        count = 0,
        completion = 0x00,
        cylinder = 0,
        head = 0,
        sector = 0,
        error = 0,
        drive_select = 0,
        operation = 0,
        last_error = 0,
        dma_enabled = false,
        irq_enabled = false,
        initialize = initialize,
        update = update_operation,
        insert_drive = insert_drive,
        save = save,
        reset = reset
    }

    cpu:set_port(0x320, port_320(self))
    cpu:set_port(0x321, port_321(self))
    cpu:set_port(0x322, port_322(self))
    cpu:set_port(0x323, port_323(self))

    init_drive(self, 0)
    init_drive(self, 1)

    return self
end

return controller