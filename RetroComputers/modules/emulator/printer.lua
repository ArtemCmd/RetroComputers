local logger = require "retro_computers:logger"
-- local png = require "lua_image:png"
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local printer = {}

local function int_17(cpu, ax, ah, al)
    if ah == 0 then -- Print Word
        local word = al
        local id = cpu.regs[3]
        logger:debug("Printer %d: Write word: %s", id, string.char(word) or ' ')
        cpu.regs[1] = band(cpu.regs[1], 0xFF)
    elseif ah == 1 then -- initilize Printer
        local id = cpu.regs[3]
        logger:debug("Printer %d: Initilizing", id)
        cpu.regs[1] = band(cpu.regs[1], 0xFF)
    elseif ah == 2 then -- Printer Status
        local id = cpu.regs[3]
        logger:debug("Printer %d: Getting status", id)
        -- cpu.regs[1] = bor(lshift(1, 8), band(cpu.regs[1], 0xFF))
        cpu.regs[1] = band(cpu.regs[1], 0xFF)
    else
        cpu:set_flag(0)
        return false
    end
    return true
end

function printer.new(cpu)
    cpu:register_interrupt_handler(0x17, int_17)
end

-- function printer.load_font(path)
    
-- end

return printer