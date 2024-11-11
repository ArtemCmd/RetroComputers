local logger = require("retro_computers:logger")
local fs = require("retro_computers:filesystem")
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local drives = {}

local function get_drives()
    return drives
end

local function disk_init_data(cpu, drive)
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
		elseif drive.size == (360*1024) then
			drive.sectors = 9
			drive.heads = 2
			drive.cylinders = 40
		elseif drive.size == (320*1024) then
			drive.sectors = 8
			drive.heads = 2
			drive.cylinders = 40
		elseif drive.size == (180*1024) then
			drive.sectors = 9
			drive.heads = 1
			drive.cylinders = 40
		elseif drive.size == (160*1024) then
			drive.sectors = 8
			drive.heads = 1
			drive.cylinders = 40
		else
			logger:error("Disks: Unknown floppy size: " .. drive.size)
		end
	else
		drive.sector_size = 512
		drive.sectors = 63
		drive.heads = 16
		drive.cylinders = math.floor(drive.size / (drive.sector_size * drive.sectors * drive.heads))

        -- drive.sector_size = 512 -- 10 mb
		-- drive.sectors = 17
		-- drive.heads = 4
		-- drive.cylinders = 306
        -- drive.sector_size = 512
		-- drive.sectors = 17
		-- drive.heads = 5
		-- drive.cylinders = 733
		if drive.cylinders <= 0 then
			logger:error("Disks: Unknown disk size: " .. drive.size)
		end
	end
	logger:info("Disks: Added new drive: CHS:%d,%d,%d Sector size:%d ID:%x Size: %d", drive.cylinders, drive.heads, drive.sectors, drive.sector_size, drive.id, drive.size)

	-- Сonfigure table
	local tba = 0xF2000 + drive.id*16
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

local function insert_disk(cpu, path, id)
    local ptr = fs.open(path)

    if ptr then
        local drive = {
            id = id,
            floppy = id < 0x80,
            is_initilized = false,
            inserted = false,
            size = file.length(path),
            path = path,
            handler = ptr,
            readonly = false,
            edited = false
        }
        function drive:initilize()
            if self.is_initilized == false then
                disk_init_data(cpu, self)
                self.is_initilized = true
            end
        end
        drives[id] = drive
        if drive.id >= 0x80 then
            cpu.memory[0x475] = cpu.memory[0x475] + 1
        end
        -- drive:initilize()
    else
        logger:error("Disks: File %s load error", path)
    end
end

local last_status = 0x00

local function ret_status(cpu, v)
	if v ~= nil then
		last_status = band(v, 0xFF)
	end
	cpu.regs[1] = bor(band(cpu.regs[1], 0xFF), lshift(last_status, 8))
	cpu:write_flag(0, last_status ~= 0)
end

local function int_13(cpu, ax,ah,al)
    -- logger:debug("Disks: Interrupt 13h: AH = %02X", ah)
	if ah == 0x00 then -- Reset Disk Drives
		ret_status(cpu, 0)
		return true
	elseif ah == 0x01 then -- Check Drive Status
		ret_status(cpu)
		return true
	elseif ah == 0x02 then -- Read Sectors
		local cx = cpu.regs[2]
		local dx = cpu.regs[3]
		local bx = cpu.regs[4]
		local sector = band(cx, 0x3F)
		local cylinder = rshift(cx, 8)
		local head = rshift(dx, 8)
		local drive_num = band(dx, 0xFF)
		if drive_num >= 0x80 then
			cylinder = bor(cylinder, lshift(band(cx, 0xC0), 2))
		end

		local drive = drives[drive_num]
        -- logger:debug("Disks: Attempt Read bytes from drive:%02X", drive_num)
		if drive then
            if not drive.inserted then
                ret_status(cpu, 31)
                return true
            end

            -- if drive.readonly then
            --     ret_status(cpu, 3)
            --     return true
            -- end

            if sector == 0 or sector > drive.sectors or head >= drive.heads or cylinder >= drive.cylinders then
                logger:error("Disks: Out of bounds id=%02X CHS=%s,%s,%s", drive_num, cylinder, head, sector)
				ret_status(cpu, 4)
				return true
			end

            local pos = cylinder
            pos = pos * drive.heads + head
            pos = pos * drive.sectors + (sector - 1)
            pos = pos * drive.sector_size
            cpu.regs[1] = al
            drive.handler:set_position(pos)
            local count = al * drive.sector_size
            local data = drive.handler:read(count)
            for i=0,count-1 do
                cpu.memory[cpu:seg(cpu.seg_es, bx + i)] = data[i + 1] or 0x00
            end
            -- logger:debug("Disks: Read bytes from drive:%02X sector:%d head:%d cylinder:%d", drive.id, sector, head, cylinder)
            ret_status(cpu, 0)
        else
			ret_status(cpu, 1)
		end
        return true
	elseif ah == 0x03 then -- Write Sectors
		local cx = cpu.regs[2]
		local dx = cpu.regs[3]
		local bx = cpu.regs[4]
		local sector = band(cx, 0x3F)
		local cylinder = rshift(cx, 8)
		local head = rshift(dx, 8)
		local drive_num = band(dx, 0xFF)
		if drive_num >= 0x80 then
			cylinder = bor(cylinder, lshift(band(cx, 0xC0), 2))
		end
		local drive = drives[drive_num]
        --logger:debug("Disks: Attempt write to disk %02X", drive_num)
        if drive then
			if not drive.inserted then
                ret_status(cpu, 31)
                return true
            end

            -- if drive.readonly then
            --     ret_status(cpu, 3)
            --     return true
            -- end

			if sector == 0 or sector > drive.sectors or head >= drive.heads or cylinder >= drive.cylinders then
				ret_status(cpu, 4)
				logger:error("Disks: Out of bounds - %02X c=%d h=%d s=%d", drive, cylinder, head, sector)
                return true
			end

            local pos = cylinder
            pos = pos * drive.heads + head
            pos = pos * drive.sectors + (sector - 1)
            pos = pos * drive.sector_size
            cpu.regs[1] = al -- AH = 0 (OK), AL = sectors transferred
            drive.handler:set_position(pos)
            local count = al * drive.sector_size
            for i=0,count-1 do
                drive.handler:write(cpu.memory[cpu:seg(cpu.seg_es, bx + i)])
            end
            logger:debug("Disks: Write %s bytes to drive:%02X sector:%s head:%s cylinder:%s", count, drive.id, sector, head, cylinder)
            if not drive.edited then
                drive.edited = true
            end
            ret_status(cpu, 0)
            return true
		else
            return true
		end
	elseif ah == 0x04 then -- Verify Sectors
		local drive = band(cpu.regs[3], 0xFF)
		ret_status(cpu, 0)
		return true
	elseif ah == 0x08 then -- Get Drive Parameters
		local drive = band(cpu.regs[3], 0xFF)
		local d = drives[drive]
		if not d then
			ret_status(cpu, 1)
		else
			d:initilize()
			local maxc = d.cylinders - 1
			local drives = cpu.memory[0x475]
			if d.floppy then drives = band(rshift(cpu.memory[0x410], 6), 3) + 1 end
			cpu.regs[2] = bor(bor(lshift(band(maxc, 0xFF), 8), band(d.sectors, 0x3F)), rshift(band(maxc, 0x300), 2)) -- CX = cylinder number | sector number
			cpu.regs[3] = bor(lshift((d.heads - 1), 8), drives)
			cpu.regs[8] = 2000 + (drive*16)
			cpu.segments[cpu.seg_es+1] = 0xF000
			if d.floppy then
				if d.sectors == 18 then
					cpu.regs[4] = bor(band(cpu.regs[4], 0xFF00), 4)
				else
					cpu.regs[4] = bor(band(cpu.regs[4], 0xFF00), 3)
				end
			else
				cpu.regs[4] = band(cpu.regs[4], 0xFF00)
			end
			ret_status(cpu, 0)
		end
		return true
	elseif ah == 0x15 then -- Get Drive Type
		local drive_num = band(cpu.regs[3], 0xFF)
		local drive = drives[drive_num]
		if drive then
            local code = 0
			if drive.floppy then code = 1
			else code = 3 end

            cpu:clear_flag(0)
		    cpu.regs[1] = bor(lshift(code, 8), band(cpu.regs[1], 0xFF))
            -- cpu.regs[2] = rshift(rshift(d.size, 9), 16)
            -- cpu.regs[3] = band(rshift(d.size, 9), 0xFFFF)
            --cpu.regs[1] = code
            if not drive.floppy then
                cpu.regs[2] = rshift(rshift(drive.size, 9), 16)
                cpu.regs[3] = band(rshift(drive.size, 9), 0xFFFF)
            end

            ret_status(cpu, 0)
		else
            -- cpu.regs[1] = 0
            -- cpu.regs[2] = 0
            -- cpu.regs[3] = 0
            ret_status(cpu, 1)
        end
		return true
	elseif ah == 0x18 then -- Set Floppy Drive Media Type
		local drive = band(cpu.regs[3], 0xFF)
		local code = 0x80
		if drives[drive] then code = 0 end
		cpu:clear_flag(0)
		cpu.regs[1] = bor(lshift(code, 8), band(cpu.regs[1], 0xFF))
		return true
	else
		cpu:set_flag(0)
		return false
	end
end

local function disk_boot(cpu, id)
	local drive = drives[id]
    cpu:register_interrupt_handler(0x13, int_13)
    if drive then
        logger:debug("Disks: Booting from: %02X", id)
        drive:initilize()
        local f = drive.handler
        f:set_position(0)
        local bootsector = f:read(512)
        for i=0,511 do
            cpu.memory[0x7c00 + i] = bootsector[i+1]
        end
        cpu:set_ip(0x0000, 0x7C00)
        cpu.regs[3] = bor(0x0000, id)
        cpu.regs[5] = 0x8000
    else
        logger:error("Disks: Drive:%02X not found.", id)
    end
end

local disks = {}

function disks:initilize(cpu)
    cpu.memory[0x475] = 0
end

function disks.new(cpu)
    local instance = {
        boot_drive = disk_boot,
        insert_disk = insert_disk,
        get_drives = get_drives
    }

    return instance
end

return disks