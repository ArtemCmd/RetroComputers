-- Serial ports
-- FIXME!!!!!!!!!!!!!!
local logger = require("retro_computers:logger")

local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor
local status = 5
local dlab = 0
local ports = {}
local devisor = 0
local ier = 0
local fifo = false
local fifoq = {}
local itl = 0 -- Interrupt Trigger Level
local beb = false -- Break Enable Bit

local function init_serial_port(cpu, base_addr)
    cpu:port_set(base_addr, function (cpu, port, val)
        if val then
            if dlab == 0 then
                logger:debug("Serial: %03X: Write to serial port: %d", base_addr, string.char(val))
            else
                devisor = band(val, 0x00FF)
                logger:debug("Serial: %03X: Devisor set ot %d", base_addr, devisor)
            end
        else
            if dlab == 0 then
                logger:debug("Serial: %03X: Read from serial port", base_addr)
                return 0xFF
            else
                return band(devisor, 0x00FF)
            end
        end
    end)

    cpu:port_set(base_addr + 1, function (cpu, port, val) -- Interrupt Enable Register
        if val then
            if dlab == 0 then
                if band(val, 1) == 1 then
                    logger:debug("Serial: %03X: Irq \"Received Data Available\" Enebled", base_addr)
                end
                if band(val, 2) == 2 then
                    logger:debug("Serial: %03X: Irq \"Transmitter Holding Register Empty\" Enebled", base_addr)
                end
                if band(val, 4) == 4 then
                    logger:debug("Serial: %03X: Irq \"Receiver Line Status\" Enebled", base_addr)
                end
                if band(val, 8) == 8 then
                    logger:debug("Serial: %03X: Irq \"Modem Status\" Enebled", base_addr)
                end
                ier = band(val, 0xFF)
            end
        else
            if dlab == 0 then
                return ier
            end
        end
    end)

    cpu:port_set(base_addr + 2, function (cpu, port, val) -- FIFO control registers / Interrupt Identification
        if val then
            if band(val, 1) == 1 then
                fifo = true
                logger:debug("Serial: %03X: FIFO enebled", base_addr)
            end
            if band(val, 2) == 2 then
                for key, _ in pairs(fifoq) do
                    fifoq[key] = nil
                end
                logger:debug("Serial: %03X: Receive FIFO cleared", base_addr)
            end
            if band(val, 4) == 4 then
                logger:debug("Serial: %03X: Transmit FIFO cleared", base_addr)
            end
            if band(val, 8) == 8 then
                logger:debug("Serial: %03X: DMA enebled", base_addr)
            end
            itl = band(rshift(val, 6), 0xF)
            logger:debug("Serial: %03X: Interrupt Trigger Level = %d", base_addr, itl)
        else
            return 0
        end
    end)

    cpu:port_set(base_addr + 3, function (cpu, port, val) -- Line Control Register
        if val then
            dlab = rshift(val, 7)
            beb = band(val, 8) == 8
            local party_bits = band(val, 4) == 4
            local stop_bits = band(val, 2) == 2
            local data_bits = band(val, 0xFF)
            logger:debug("Serial: %03X: Setting DLAB=%s,BEB=%s,PB=%s,SB=%s,DB=%s", base_addr, dlab, beb, party_bits, stop_bits, data_bits)
        else
            return 0xFF
        end
    end)

    cpu:port_set(base_addr + 4, function (cpu, port, val) -- Modem Control Register (TODO)
        if val then

        else
            return 0xFF
        end
    end)

    cpu:port_set(base_addr + 5, function (cpu, port, val) -- Line Status Register (TODO)
        if val then

        else
            return 1
        end
    end)
end

local byte_to_speed = {
    [1] = 110,
    [2] = 150,
    [3] = 300,
    [4] = 600,
    [5] = 1200,
    [6] = 2400,
    [7] = 4800,
    [9] = 9600
}

local function int_14(cpu, ax, ah, al)
    if ah == 0 then -- Initilize port
        local id = cpu.regs[3] -- DX
        local params = al
        local word_lenght = band(params, 0x1)
        local stop_bit
        local chetnost
        local speed = rshift(params, 5)
        logger:debug("COM%d: initilize params=%d", id, params)
        logger:debug("COM%d: Parameters: Word lenght:%d Stop Bit:%d chetnost:%d Speed:%d", id, word_lenght, 0, 0, byte_to_speed[speed])
    elseif ah == 1 then -- Write byte to port
        local byte = al
        local port = cpu.regs[3]
        logger:debug("COM%d: Write %d byte", port, byte)
    elseif ah == 2 then -- Read byte from port
        local port = cpu.regs[3]
        logger:debug("COM%d: Reading byte", port)
    elseif ah == 3 then -- Get port status
        local port = cpu.regs[3]
        logger:debug("COM%d: Getting status", port)
    elseif ah == 4 then -- Extended Initilize
        local port = cpu.regs[3]
        local status = al
        local chetnost = cpu.regs[2]
        local stop_bits = band(lshift(cpu.regs[2], 4), 0xFF)
        local word_lenght = band(lshift(cpu.regs[4], 4), 0xFF)
        local speed = cpu.regs[4]
        logger:debug("COM%d: EInitilize status:%d chetnost:%d stop_bits:%d word_lenght:%d speed:%d", port, status, chetnost, stop_bits, word_lenght, speed)
    elseif ah == 5 then -- Extended modem control
        if al == 0 then -- Read from modem
            logger:debug("Modem: Read")
        elseif al == 1 then -- Write too mdem
            logger:debug("Modem: Write")
        end
    else
        cpu:clear_flag(1) -- Clear CR 
        return false
    end
    return true
end
local serial = {}

function serial.new(cpu)
    local self = {}
    cpu:register_interrupt_handler(0x14, int_14)
    init_serial_port(cpu, 0x3F8) -- COM1
    init_serial_port(cpu, 0x2F8) -- COM2
    init_serial_port(cpu, 0x3E8) -- COM3
    init_serial_port(cpu, 0x2E8) -- COM4
    init_serial_port(cpu, 0x5F8) -- COM5
    init_serial_port(cpu, 0x4F8) -- COM6
    init_serial_port(cpu, 0x5E8) -- COM7
    init_serial_port(cpu, 0x4E8) -- COM8
    return self
end

return serial