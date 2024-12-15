local logger = require("retro_computers:logger")
local drive_manager = require("retro_computers:emulator/drive_manager")
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local function init_disk(self, cpu, drive)
	drive.inserted = true
	if drive.size == 0 then
		drive.inserted = false
		drive.sector_size = 0
		drive.sectors = 0
		drive.heads = 0
		drive.cylinders = 0
	elseif drive.floppy then
		drive.sector_size = 512
		if drive.size == 2949120 then
			drive.sectors = 36
			drive.heads = 2
			drive.cylinders = 80
		elseif drive.size == 1761280 then
			drive.sectors = 21
			drive.heads = 2
			drive.cylinders = 82
		elseif drive.size == 1720320 then
			drive.sectors = 21
			drive.heads = 2
			drive.cylinders = 80
		elseif drive.size == 1474560 then
			drive.sectors = 18
			drive.heads = 2
			drive.cylinders = 80
		elseif drive.size == 1228800 then
			drive.sectors = 15
			drive.heads = 2
			drive.cylinders = 80
		elseif drive.size == 737280 then
			drive.sectors = 9
			drive.heads = 2
			drive.cylinders = 80
		elseif drive.size == 368640 then
			drive.sectors = 9
			drive.heads = 2
			drive.cylinders = 40
		elseif drive.size == 327680 then
			drive.sectors = 8
			drive.heads = 2
			drive.cylinders = 40
		elseif drive.size == 184320 then
			drive.sectors = 9
			drive.heads = 1
			drive.cylinders = 40
		elseif drive.size == 163840 then
			drive.sectors = 8
			drive.heads = 1
			drive.cylinders = 40
		else
			logger:error("Disks: Unknown floppy size: " .. drive.size)
            return
		end
	else
        if (drive.sector_size == 0) and (drive.cylinders == 0) and (drive.heads == 0) and (drive.sectors == 0) then
            drive.sector_size = 512
            if drive.size == 10653696 then
                drive.sectors = 17
                drive.heads = 4
                drive.cylinders = 306
            elseif drive.size == 5326848 then
                drive.sectors = 17
                drive.heads = 2
                drive.cylinders = 306
            elseif drive.size == 26112000 then
                drive.sectors = 17
                drive.heads = 8
                drive.cylinders = 375
            elseif drive.size == 15980544 then
                drive.sectors = 17
                drive.heads = 6
                drive.cylinders = 306
            else
                drive.sectors = 63
                drive.heads = 16
                drive.cylinders = math.floor(drive.size / (drive.sector_size * drive.sectors * drive.heads))
            end
        end

		if drive.cylinders <= 0 then
			logger:error("Disks: Unknown disk size: %d", drive.size)
            return
		end
	end
	logger:info("Disks: Added new drive: CHS: = %d,%d,%d, Sector size = %d, ID = %x, Size = %d, Readonly = %s", drive.cylinders, drive.heads, drive.sectors, drive.sector_size, drive.id, drive.size, drive.readonly)

	-- Сonfigure table
	local tba = 0xF2000 + drive.id * 16
	if drive.id == 0x80 then
		cpu.memory:w16(0x0104, band(tba, 0xFFFF))
		cpu.memory:w16(0x0106, 0xF000)
	elseif drive.id == 0x81 then
		cpu.memory:w16(0x0118, band(tba, 0xFFFF))
		cpu.memory:w16(0x011A, 0xF000)
	elseif drive.id == 0x00 then
		cpu.memory:w16(0x0078, band(tba, 0xFFFF))
		cpu.memory:w16(0x007A, 0xF000)
	end
	if drive.floppy then
		cpu.memory[tba] = 0xF0
		cpu.memory[tba + 1] = 0x00
		cpu.memory[tba + 2] = 0x00
		cpu.memory[tba + 3] = math.ceil(drive.sector_size / 128) - 1
		cpu.memory[tba + 4] = drive.sectors
		cpu.memory[tba + 5] = 0
		cpu.memory[tba + 6] = 0
		cpu.memory[tba + 7] = 0
		cpu.memory[tba + 8] = 0xF6
		cpu.memory[tba + 9] = 0
		cpu.memory[tba + 10] = 0
	else
		cpu.memory:w16(tba, drive.cylinders)
		cpu.memory[tba + 2] = drive.heads
		cpu.memory:w16(tba + 3, 0)
		cpu.memory:w16(tba + 5, 0)
		cpu.memory[tba + 7] = 0
		cpu.memory[tba + 8] = 0xC0
		if drive.heads > 8 then
			cpu.memory[tba + 8] = bor(cpu.memory[tba + 8], 0x08)
		end
		cpu.memory[tba + 9] = 0
		cpu.memory[tba + 10] = 0
		cpu.memory[tba + 11] = 0
		cpu.memory:w16(tba + 12, 0)
		cpu.memory[tba + 14] = drive.sectors
	end
end

local function eject_drive(self, id)
    local drive = self.drives[id]
    if drive then
        drive.handler:flush()
        drive.inserted = false
        self.drives[id] = nil
    end
end

local function insert_disk(self, cpu, path, readonly, id)
    local disk = drive_manager.load_drive(path)

    if disk then
        if self.drives[id] then
            local drive = self.drives[id]
            init_disk(self, cpu, drive)
            if drive.id >= 0x80 then
                cpu.memory[0x475] = cpu.memory[0x475] + 1
            end
        else
            local drive = {
                id = id,
                floppy = id < 0x80,
                inserted = false,
                size = file.length(path),
                path = path,
                handler = disk.handler,
                readonly = readonly,
                edited = false,
                sector_size = disk.sector_size or 0,
                cylinders = disk.cylinders or 0,
                heads = disk.heads or 0,
                sectors = disk.sectors or 0
            }

            init_disk(self, cpu, drive)
            self.drives[id] = drive
            if drive.id >= 0x80 then
                cpu.memory[0x475] = cpu.memory[0x475] + 1
            end
        end
    else
        logger:error("Disks: File %s load error", path)
    end
end

local function ret_status(self, cpu, v)
	if v ~= nil then
		self.last_status = band(v, 0xFF)
	end
	cpu.regs[1] = bor(band(cpu.regs[1], 0xFF), lshift(self.last_status, 8))
	cpu:write_flag(0, self.last_status ~= 0)
end

local function int_13(self)
    return function(cpu, ax, ah, al)
        -- logger:debug("Disks: Interrupt 13h: AH = %02X", ah)
        if ah == 0x00 then -- Reset Disk Drives
            local drive_id = band(cpu.regs[3], 0xFF)
            local drive = self.drives[drive_id]
            if drive then
                drive.handler:set_position(0)
            end
            ret_status(self, cpu, 0)
            return true
        elseif ah == 0x01 then -- Check Drive Status
            ret_status(self, cpu)
            return true
        elseif ah == 0x02 then -- Read Sectors
            local cx = cpu.regs[2]
            local dx = cpu.regs[3]
            local bx = cpu.regs[4]
            local sector = band(cx, 0x3F)
            local cylinder = rshift(cx, 8)
            local head = rshift(dx, 8)
            local drive_id = band(dx, 0xFF)
            if drive_id >= 0x80 then
                cylinder = bor(cylinder, lshift(band(cx, 0xC0), 2))
            end

            local drive = self.drives[drive_id]
            if drive then
                if not drive.inserted then
                    ret_status(self, cpu, 0x31)
                    return true
                end

                if sector == 0 or sector > drive.sectors or head >= drive.heads or cylinder >= drive.cylinders then
                    logger:error("Disks: Disk %02X: Out of bounds, CHS = %d, %d, %d", drive_id, cylinder, head, sector)
                    ret_status(self, cpu, 4)
                    return true
                end

                local pos = ((cylinder * drive.heads + head) * drive.sectors + (sector - 1)) * drive.sector_size
                cpu.regs[1] = al
                drive.handler:set_position(pos)
                local count = al * drive.sector_size
                local data = drive.handler:read(count)
                for i = 0, count - 1 do
                    cpu.memory[cpu:seg(cpu.seg_es, bx + i)] = data[i + 1] or 0x00
                end
                -- logger:debug("Disks: Read bytes from drive %02X at sector:%d head:%d cylinder:%d", drive.id, sector, head, cylinder)
                ret_status(self, cpu, 0)
            else
                ret_status(self, cpu, 1)
            end
            return true
        elseif ah == 0x03 then -- Write Sectors
            local cx = cpu.regs[2]
            local dx = cpu.regs[3]
            local bx = cpu.regs[4]
            local sector = band(cx, 0x3F)
            local cylinder = rshift(cx, 8)
            local head = rshift(dx, 8)
            local drive_id = band(dx, 0xFF)
            if drive_id >= 0x80 then
                cylinder = bor(cylinder, lshift(band(cx, 0xC0), 2))
            end
            local drive = self.drives[drive_id]

            if drive then
                if not drive.inserted then
                    ret_status(self, cpu, 0x31)
                    return true
                end

                if sector == 0 or sector > drive.sectors or head >= drive.heads or cylinder >= drive.cylinders then
                    ret_status(self, cpu, 4)
                    logger:error("Disks: Disk %02X: Out of bounds, CHS = %d, %d, %d", drive_id, cylinder, head, sector)
                    return true
                end

                if drive.readonly then
                    ret_status(self, cpu, 0x03)
                    return true
                end

                local pos = ((cylinder * drive.heads + head) * drive.sectors + (sector - 1)) * drive.sector_size
                cpu.regs[1] = al -- AH = 0 (OK), AL = sectors transferred
                drive.handler:set_position(pos)
                local count = al * drive.sector_size
                for i = 0, count - 1 do
                    drive.handler:write(cpu.memory[cpu:seg(cpu.seg_es, bx + i)])
                end
                -- logger:debug("Disks: Write %s bytes to drive %02X sector:%s head:%s cylinder:%s", count, drive.id, sector, head, cylinder)
                if not drive.edited then
                    drive.edited = true
                end
                ret_status(self, cpu, 0)
                return true
            else
                return true
            end
        elseif ah == 0x04 then -- Verify Sectors
            local drive_id = band(cpu.regs[3], 0xFF)
            -- logger:debug("Disks: Drive %02X: Verify sectors", drive_id)
            ret_status(self, cpu, 0)
            return true
        elseif ah == 0x08 then -- Get Drive Parameters
            local drive_num = band(cpu.regs[3], 0xFF)
            local drive = self.drives[drive_num]

            -- logger:debug("Disks: Getting drive %02X parameters, Drive exists = %s", drive_num, drive ~= nil)

            if not drive then
                ret_status(self, cpu, 1)
            else
                local maxc = drive.cylinders - 1
                local drives_count = cpu.memory[0x475]
                if drive.floppy then
                    drives_count = band(rshift(cpu.memory[0x410], 6), 3) + 1
                end
                cpu.regs[2] = bor(bor(lshift(band(maxc, 0xFF), 8), band(drive.sectors, 0x3F)), rshift(band(maxc, 0x300), 2)) -- CX = cylinder number | sector number
                cpu.regs[3] = bor(lshift((drive.heads - 1), 8), drives_count)
                if drive.floppy then
                    if drive.sectors == 18 then
                        cpu.regs[4] = bor(band(cpu.regs[4], 0xFF00), 4)
                    else
                        cpu.regs[4] = bor(band(cpu.regs[4], 0xFF00), 3)
                    end
                    cpu.regs[8] = 2000 + (drive.id * 16)
                    cpu.segments[cpu.seg_es+1] = 0xF000
                else
                    cpu.regs[4] = band(cpu.regs[4], 0xFF00)
                end
                ret_status(self, cpu, 0)
            end
            return true
        elseif ah == 0x15 then -- Get Drive Type
            local drive_num = band(cpu.regs[3], 0xFF)
            local drive = self.drives[drive_num]
            -- logger:debug("Disks: Getting drive %02X type, Drive exists = %s", drive_num, drive ~= nil)
            if drive then
                local code = 0
                if drive.floppy then
                    code = 1
                else
                    code = 3
                end

                cpu:clear_flag(0)
                cpu.regs[1] = bor(lshift(code, 8), band(cpu.regs[1], 0xFF))

                ret_status(self, cpu, 0)
            else
                ret_status(self, cpu, 1)
            end
            return true
        elseif ah == 0x18 then -- Set Floppy Drive Media Type
            local drive = band(cpu.regs[3], 0xFF)
            local code = 0x80
            if self.drives[drive] then code = 0 end
            cpu:clear_flag(0)
            cpu.regs[1] = bor(lshift(code, 8), band(cpu.regs[1], 0xFF))
            return true
        else
            cpu:set_flag(0)
            return false
        end
    end
end

local function disk_boot(self, cpu, id)
	local drive = self.drives[id]
    if drive then
        logger:debug("Disks: Booting from drive %02X", id)
        drive.handler:set_position(0)
        local bootsector =  drive.handler:read(512)
        for i=0,511 do
            cpu.memory[0x7c00 + i] = bootsector[i+1]
        end
        cpu:set_ip(0x0000, 0x7C00)
        cpu.regs[3] = bor(0x0000, id)
        cpu.regs[5] = 0x8000
    else
        logger:error("Disks: Drive %02X not found.", id)
    end
end

local disks = {}

local function reset(self, memory)
    memory[0x475] = 0
end

function disks.new(cpu)
    local self = {
        drives = {},
        last_status = 0,
        boot_drive = disk_boot,
        eject_drive = eject_drive,
        insert_disk = insert_disk,
        reset = reset
    }

    cpu:register_interrupt_handler(0x13, int_13(self))
    return self
end

return disks