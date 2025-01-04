-- Serial (https://en.wikibooks.org/wiki/Serial_Programming/8250_UART_Programming#)

local logger = require("retro_computers:logger")
local fifo = require("retro_computers:emulator/fifo")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local ier_map = {[0] = 0x04, 0x01, 0x01, 0x02, 0x08, 0x40, 0x80}
local iir_map = {[0] = 0x06, 0x0C, 0x04, 0x02, 0x00, 0x0E, 0x0A}

local function update_interrupts(port, cpu)
    port.iir = bor(band(port.iir, 0xF0), 0x01)

    for i = 0, 6, 1 do
        if (band(port.ier, ier_map[i]) > 0) and (band(port.int_status, lshift(1, i)) > 0) then
            port.iir = bor(band(port.iir, 0xF0), iir_map[i])
            break
        end
    end

    if band(port.iir, 0x01) == 0 then
        cpu:emit_interrupt(0x0C)
    end
end

local function init_serial_port(self, cpu, base_addr)
    local ser_port = {
        lcr = 0, -- Line Control register
        lsr = 0x60, -- Line Status Register
        ier = 0, -- Interrupt Enable Register
        iir = 0, -- Interrupt Identification Register
        dlab = 96, -- Divisor Latch Byte
        bits = 0,
        int_status = 0,
        -- FIFO
        fifo_enebled = false,
        fcr = 0x06, -- FIFO Control Register
        fifo_transmit = fifo.new(64),
        fifo_receive = fifo.new(64)
    }

    ser_port.fifo_receive:set_empty_event(function(f)
        if f.empty then
            ser_port.lsr = bor(band(ser_port.lsr, 0xFE), 0)
        else
            ser_port.lsr = bor(band(ser_port.lsr, 0xFE), 1)
        end
        logger:debug("Serial: Port 0x%03X: FIFO Receive: Empty event", base_addr)
    end)

    ser_port.fifo_receive:set_overflow_event(function(f)
        if f.overflow then
            ser_port.lsr = bor(band(ser_port.lsr, 0xFD), 0x02)
        else
            ser_port.lsr = bor(band(ser_port.lsr, 0xFD), 0)
        end
        logger:debug("Serial: Port 0x%03X: FIFO Receive: Overflow event", base_addr)
    end)

    ser_port.fifo_receive:set_ready_event(function(f)
        if f.ready then
            ser_port.int_status = bor(band(ser_port.int_status, bnot(4)), 4)
        else
            ser_port.int_status = bor(band(ser_port.int_status, bnot(4)), 0)
        end
        update_interrupts(ser_port, cpu)
        logger:debug("Serial: Port 0x%03X: FIFO Receive: Ready event", base_addr)
    end)

    ser_port.fifo_transmit:set_empty_event(function(f)
        if f.empty then
            ser_port.lsr = bor(band(ser_port.lsr, 0x9F), 5)
            ser_port.int_status = bor(ser_port.int_status, 8)
        else
            ser_port.lsr = band(ser_port.lsr, 0x9F)
            ser_port.int_status = band(ser_port.int_status, bnot(8))
        end
    end)

    cpu:port_set(base_addr, function (_, _, val) -- Transmitter Holding Buffer / Receiver Buffer / Divisor Latch Low Byte
        if val then
            logger:debug("Serial: Port 0x%03X: Write %d to 0", base_addr, val)
            if band(ser_port.lcr, 0x80) == 0x80 then
                ser_port.dlab = bor(band(ser_port.dlab, 0xFF00), val)
            else
                if ser_port.fifo_enebled then
                    ser_port.fifo_transmit:ewrite(val)
                    logger:debug("Serial: Port 0x%03X: Write %02X to fifo", base_addr, val)
                end
            end
        else
            logger:debug("Serial: Port 0x%03X: Read from 0", base_addr)
            if band(ser_port.lcr, 0x80) == 0x80 then
                return band(ser_port.lcr, 0xFF)
            end

            if ser_port.fifo_enebled then
                logger:debug("Serial: Port 0x%03X: Read from fifo", base_addr)
                return ser_port.fifo_receive:eread() or 0
            else
                return 0
            end
        end
    end)

    cpu:port_set(base_addr + 1, function (_, _, val) -- Interrupt Enable Register / Divisor Latch High Byte
        if val then
            logger:debug("Serial: Port 0x%03X: Write %d to Interrupt Enable Register", base_addr, val)
            if band(ser_port.lcr, 0x80) == 0x80 then
                ser_port.dlab = bor(band(ser_port.dlab, 0x00FF), val)
            else
                if band(val, 1) == 1 then
                    logger:debug("Serial: Port 0x%03X: Irq \"Received Data Available\" Enebled", base_addr)
                end
                if band(val, 2) == 2 then
                    logger:debug("Serial: Port 0x%03X: Irq \"Transmitter Holding Register Empty\" Enebled", base_addr)
                end
                if band(val, 4) == 4 then
                    logger:debug("Serial: Port 0x%03X: Irq \"Receiver Line Status\" Enebled", base_addr)
                end
                if band(val, 8) == 8 then
                    logger:debug("Serial: Port 0x%03X: Irq \"Modem Status\" Enebled", base_addr)
                end

                if (band(val, 2) == 2) and (band(ser_port.lsr, 0x20) == 0x20) then
                    ser_port.int_status = bor(ser_port.int_status, 0x08)
                end

                ser_port.ier = band(val, 0xF)
                update_interrupts(ser_port, cpu)
            end
        else
            logger:debug("Serial: Port 0x%03X: Read Interrupt Enable Register", base_addr)
            if band(ser_port.lcr, 0x80) == 0x80 then
                return band(rshift(ser_port.dlab, 8), 0xFF)
            end
            return ser_port.ier
        end
    end)

    cpu:port_set(base_addr + 2, function (_, _, val) -- FIFO control registers / Interrupt Identification
        if val then
            ser_port.fcr = band(val, 0xF9)
            ser_port.fifo_enebled = band(val, 0x01) == 0x01

            if band(val, 2) == 2 then
                if ser_port.fifo_enebled then
                    ser_port.fifo_receive:ereset()
                else
                    ser_port.fifo_receive:reset()
                end
                logger:debug("Serial: Port 0x%03X: Receive FIFO cleared", base_addr)
            end
            if band(val, 4) == 4 then
                if ser_port.fifo_enebled then
                    ser_port.fifo_transmit:ereset()
                else
                    ser_port.fifo_transmit:reset()
                end
                logger:debug("Serial: Port 0x%03X: Transmit FIFO cleared", base_addr)
            end

            local trigger_level = band(rshift(val, 6), 0x03)
            if trigger_level == 0 then
                ser_port.fifo_receive.trigger_len = 1
            elseif trigger_level == 1 then
                ser_port.fifo_receive.trigger_len = 4
            elseif trigger_level == 2 then
                ser_port.fifo_receive.trigger_len = 8
            elseif trigger_level == 3 then
                ser_port.fifo_receive.trigger_len = 14
            end
            ser_port.fifo_transmit.trigger_len = 16

            logger:debug("Serial: Port 0x%03X: Interrupt Trigger Level = %d", base_addr, trigger_level)

            if ser_port.fifo_enebled then
                logger:debug("Serial: Port 0x%03X: FIFO enebled", base_addr)
            else
                logger:debug("Serial: Port 0x%03X: FIFO disebled", base_addr)
            end
        else
            logger:debug("Serial: Port 0x%03X: Interrupt Identification Register", base_addr)
            if band(ser_port.fcr, 1) == 1 then
                return bor(ser_port.iir, 0xC0)
            end
            return ser_port.iir
        end
    end)

    cpu:port_set(base_addr + 3, function (cpu, port, val) -- Line Control Register
        if val then
            ser_port.lcr = val
            ser_port.bits = (band(ser_port.lcr, 0x03) + 5) + 1
            local dlab = rshift(val, 7)
            local beb = band(val, 8) == 8
            local party_bits = band(val, 4) == 4
            local stop_bits = band(val, 2) == 2
            local data_bits = band(val, 0xFF)
            logger:debug("Serial: Port 0x%03X: Setting DLAB=%s,BEB=%s,PB=%s,SB=%s,DB=%s", base_addr, dlab, beb, party_bits, stop_bits, data_bits)
        else
            return ser_port.lcr
        end
    end)

    cpu:port_set(base_addr + 4, function (cpu, port, val) -- Modem Control Register
        if val then

        else
            return 0xFF
        end
    end)

    cpu:port_set(base_addr + 5, function (cpu, port, val) -- Line Status Register
        if not val then
            logger:debug("Serial: Port 0x%03X: Read Line Status Register", base_addr)
            ser_port.int_status = band(ser_port.int_status, bnot(1))
            return ser_port.lsr
        end
    end)

    cpu:port_set(base_addr + 6, function (cpu, port, val) -- Modem Status Register
        if val then

        else
            return 0xFF
        end
    end)

    self.ports[base_addr] = ser_port
end

local function write_port(self, port, val)
    local serial_port = self.ports[port]
    if serial_port then
        if serial_port.fifo_enebled then
            logger:debug("Serial: Send %d to port 0x%03X", val, port)
            serial_port.fifo_receive:ewrite(band(val, 0xFF))
        end
    end
end

local function read_port(self, port)
    local serial_port = self.ports[port]
    if serial_port then
        if serial_port.fifo_enebled then
            local result = serial_port.fifo_transmit:eread()
            logger:debug("Serial: Read %d from port 0x%03X", port)
            return result
        end
    end
end

local function reset(self)
    for _, port in pairs(self.ports) do
        if port.fifo_enebled then
            port.fifo_transmit:ereset()
            port.fifo_receive:ereset()
        else
            port.fifo_transmit:reset()
            port.fifo_receive:reset()
        end

        port.lcr = 0
        port.lsr = 0x60
        port.ier = 0
        port.iir = 0
        port.dlab = 96
        port.bits = 0
        port.int_status = 0
        port.fifo_enebled = false
        port.fcr = 0x06
    end
end

local serial = {}

function serial.new(cpu, count)
    local self = {
        ports = {},
        write_port = write_port,
        read_port = read_port,
        reset = reset
    }

    local ports = {0x3F8, 0x2F8, 0x3E8, 0x2E8, 0x5F8, 0x4F8, 0x5E8, 0x4E8}

    if count then
        for i = 1, math.min(count, 8), 1 do
            local port = ports[i]
            init_serial_port(self, cpu, port)
        end
    else
        init_serial_port(self, cpu, 0x3F8) -- COM1
        init_serial_port(self, cpu, 0x2F8) -- COM2
        init_serial_port(self, cpu, 0x3E8) -- COM3
        init_serial_port(self, cpu, 0x2E8) -- COM4
        init_serial_port(self, cpu, 0x5F8) -- COM5
        init_serial_port(self, cpu, 0x4F8) -- COM6
        init_serial_port(self, cpu, 0x5E8) -- COM7
        init_serial_port(self, cpu, 0x4E8) -- COM8
    end

    return self
end

return serial