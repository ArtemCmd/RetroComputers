local logger = require("retro_computers:logger")
local config = require("retro_computers:config")
local image = nil
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor
local printer = {}
local lastId = 0

local function copy_to(src, dest, srcX, srcY, destX, destY, width, height)
    for y = 0, height, 1 do
		for x = 0,  width, 1 do
			local r, g, b, a = src:get(srcX + x, srcY + y)
            if a > 0 then
                dest:set(x + destX, y + destY, 0, 0, 0, a)
            end
		end
	end
end

local function new_page(self)
    if image then
        logger:debug("Printer: Creating new page")
        if not file.exists("retro_computers:textures/printer") then
            file.mkdir("retro_computers:textures/printer")
        end
        self.page:to_png(string.format("retro_computers:textures/printer/page_%d.png", lastId))
        self.page:set_all(255, 255, 255, 255)

        if config.create_page_item then
            local item = {
                ["icon-type"] = "sprite",
                ["icon"] =  string.format("items:page_%d", lastId)
            }
            local img = image:new(512, 512)
            img:place(self.page, 1, 1, 1, 1, 100, 100)
            file.write("retro_computers:items/page_" .. lastId .. ".json", json.tostring(item, true))
            img:to_png("retro_computers:textures/items/page_" .. lastId .. ".png")
        end
        lastId = lastId + 1
    end
end

local function print_char(self, char)
    if image then
        if char == 0x07 then -- BELL
        elseif char == 0x08 then -- BS
            if self.curr_x > 0 then
                self.curr_x = self.curr_x - 1
            end
        elseif char == 0x09 then -- HT
        elseif char == 0x0B then -- VT
            self.curr_x = 0
        elseif char == 0x0C then -- FF
            new_page(self)
        elseif char == 0x0D then -- CR
            self.curr_x = 0
        elseif char == 0x0A then -- LF
            self.curr_x = 0
            self.curr_y = self.curr_y + self.font.height
        elseif char == 0x0E then -- SO
        elseif char == 0x0F then -- SI
        elseif char == 0x11 then -- DC1
        elseif char == 0x12 then -- DC2
        elseif char == 0x13 then -- DC3
        elseif char == 0x14 then -- DC4
        elseif char == 0x18 then -- CAN
        elseif char == 0x1b then -- ESC
        else
            local glyph = image.from_png("retro_computers:textures/fonts/ibm_pc_8_8/glyphs/"..char..".png")
            if self.curr_x >= config.page_width then
                self.curr_x = 0
                self.curr_y = self.curr_y + self.font.height
                if self.curr_y > config.page_height then
                    new_page(self)
                end
            end
            copy_to(glyph, self.page, 0, 0, self.curr_x, self.curr_y, self.font.width - 1, self.font.height - 1)
            self.curr_x = self.curr_x + self.font.width
        end
    end
end

local function int_17(self)
    return function (cpu, ax, ah, al)
        if ah == 0 then -- Print Word
            local char = al
            local id = cpu.regs[3]
            logger:debug("Printer %d: Write word: %s", id, string.char(char) or ' ')
            print_char(self, char)
            cpu.regs[1] = band(cpu.regs[1], 0xFF)
        elseif ah == 1 then -- initilize Printer
            local id = cpu.regs[3]
            logger:debug("Printer %d: Initilizing", id)
            cpu.regs[1] = band(cpu.regs[1], 0xFF)
        elseif ah == 2 then -- Printer Status
            local id = cpu.regs[3]
            logger:debug("Printer %d: Getting status", id)
            cpu.regs[1] = band(cpu.regs[1], 0xFF)
        else
            cpu:set_flag(0)
            return false
        end
        return true
    end
end

function printer.new(cpu)
    local self = {
        font = {
            width = 8,
            height = 8
        },
        page = {},
        curr_x = 0,
        curr_y = 0
    }
    cpu:register_interrupt_handler(0x17, int_17(self))
    if pack.is_installed("libpng") then
        image = require("libpng:image")
        self.page = image:new(config.page_width, config.page_height)
        self.page:set_all(255, 255, 255, 255)
    end
    return self
end

return printer