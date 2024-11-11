-- v razrabotke (tam zloshno prosto)
local logger = require 'retro_computers:logger'
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local controller = {}

local function port_3F0(cpu, port, value)
    logger:debug("FDC: Port 0x3F0")
end

local function port_3F1(cpu, port, value)
    logger:debug("FDC: Port 0x3F1")
end

local function port_3F2(cpu, port, value)
    local motd = rshift(value, 7)
    logger:debug("FDC: Port 0x3F2 %02X", motd)
end

local function port_3F3(cpu, port, value)
    logger:debug("FDC: Port 0x3F3")
end

local function port_3F4(cpu, port, value)
    logger:debug("FDC: Port 0x3F4")
end

local function port_3F5(cpu, port, value)
    logger:debug("FDC: Port 0x3F5")
end

local function port_3F6(cpu, port, value)
    logger:debug("FDC: Port 0x3F6")
end

local function port_3F7(cpu, port, value)
    logger:debug("FDC: Port 0x3F7")
end

function controller.new(cpu)
    local self = {}
    cpu:port_set(0x3F0, port_3F0)
    cpu:port_set(0x3F1, port_3F1)
    cpu:port_set(0x3F2, port_3F2)
    cpu:port_set(0x3F3, port_3F3)
    cpu:port_set(0x3F4, port_3F4)
    cpu:port_set(0x3F5, port_3F5)
    cpu:port_set(0x3F6, port_3F6)
    cpu:port_set(0x3F7, port_3F7)
    return self
end

return controller
