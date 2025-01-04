-- MDA

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot
local cp437 = require("retro_computers:emulator/cp437")

local font_9_14 = {}
for _, v in pairs(cp437) do
    font_9_14[v] = "fonts/ibm_pc_8_8/glyphs/" .. v
end
setmetatable(font_9_14, {
    __index = function (t, k)
        if rawget(t, k) then
            return rawget(t, k)
        else
            return "fonts/ibm_pc_8_8/glyphs/0"
        end
    end
})

local function port_3B0_3B2_3B4_3B6(self)
    return function(cpu, port, val)
        if val then
            self.crtc_index = band(val, 31)
        else
            return self.crtc_index
        end
    end
end

local function port_3B1_3B3_3B5_3B7(self)
    return function (cpu, port, val)
        if val then
            self.crtc_regs[self.crtc_index] = band(val, 0xFF)
            if (self.crtc_regs[10] == 6) and (self.crtc_regs[11] == 7) then
                self.crtc_regs[10] = 0xB
                self.crtc_regs[11] = 0xC
            end

            local position = bor(self.crtc_regs[0x0F], lshift(self.crtc_regs[0x0E], 8))
            self.display.cursor_x = math.floor(position % 80)
            self.display.cursor_y = math.floor(position / 80)
        else
            return self.crtc_regs[self.crtc_index]
        end
    end
end

local function port_3B8(self)
    return function (cpu, port, val)
        if val then
            self.ctrl = val
        end
    end
end

local function port_3BA(self)
    return function (cpu, port, val)
        return bor(self.status, 0xF0)
    end
end

local function read(self, addr)
    return self.vram[addr - 0xB0000]
end

local function write(self, addr, val)
    self.vram[addr - 0xB0000] = val
end

local function update(self)
    for y = 0, 24, 1 do
        local base = (y * 160)
        self.status = band(self.status, bnot(1))
		for x = 0, 79, 1 do
			local chr = self.vram[base + (x * 2)]
            self.display.char_buffer[y * 80 + x][1] = chr
            self.display.char_buffer[y * 80 + x][2] = 0
            self.display.char_buffer[y * 80 + x][3] = 2934280
            self.status = bor(self.status, 8)
		end
	end
    self.display.update()
end

local function reset(self)
    for i = 0, 31, 1 do
        self.crtc_regs[i] = 0
    end
    self.crtc_index = 0
    self.ctrl = 0
    self.status = 0
end

local mda = {}

function mda.new(cpu, display)
    local self = {
        crtc_regs = {[0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        crtc_index = 0,
        ctrl = 0,
        status = 0,
        vram = {},
        vram_read = read,
        vram_write = write,
        update = update,
        reset = reset,
        display = display,
        start_addr = 0xB0000,
        end_addr = 0xBFFFF,
        glyph_width = 8,
        glyph_height = 8,
        font = font_9_14,
        cursor_color = {8, 198, 44, 255}
    }

    cpu:port_set(0x3B0, port_3B0_3B2_3B4_3B6(self))
    cpu:port_set(0x3B2, port_3B0_3B2_3B4_3B6(self))
    cpu:port_set(0x3B4, port_3B0_3B2_3B4_3B6(self))
    cpu:port_set(0x3B6, port_3B0_3B2_3B4_3B6(self))

    cpu:port_set(0x3B1, port_3B1_3B3_3B5_3B7(self))
    cpu:port_set(0x3B3, port_3B1_3B3_3B5_3B7(self))
    cpu:port_set(0x3B5, port_3B1_3B3_3B5_3B7(self))
    cpu:port_set(0x3B7, port_3B1_3B3_3B5_3B7(self))

    cpu:port_set(0x3B8, port_3B8(self))
    cpu:port_set(0x3BA, port_3BA(self))

    return self
end

return mda