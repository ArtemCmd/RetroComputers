-- =====================================================================================================================================================================
-- Intel 8080 CPU emulation.
-- =====================================================================================================================================================================

local logger = require("dave_logger:logger")("RetroComputers")
local common = require("retro_computers:emulator/hardware/cpu/common")
local io_ports = require("retro_computers:emulator/io_ports")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local cpu = {}

local cycles = {
    [0x00] = 4, 10, 7,  5,  5,  5,  7,  4,  4, 10, 7,  5,  5,  5,  7, 4,
    4, 10, 7,  5,  5,  5,  7,  4,  4, 10, 7,  5,  5,  5,  7, 4,
    4, 10, 16, 5,  5,  5,  7,  4,  4, 10, 16, 5,  5,  5,  7, 4,
    4, 10, 13, 5,  10, 10, 10, 4,  4, 10, 13, 5,  5,  5,  7, 4,
    5, 5,  5,  5,  5,  5,  7,  5,  5, 5,  5,  5,  5,  5,  7, 5,
    5, 5,  5,  5,  5,  5,  7,  5,  5, 5,  5,  5,  5,  5,  7, 5,
    5, 5,  5,  5,  5,  5,  7,  5,  5, 5,  5,  5,  5,  5,  7, 5,
    7, 7,  7,  7,  7,  7,  7,  7,  5, 5,  5,  5,  5,  5,  7, 5,
    4, 4,  4,  4,  4,  4,  7,  4,  4, 4,  4,  4,  4,  4,  7, 4,
    4, 4,  4,  4,  4,  4,  7,  4,  4, 4,  4,  4,  4,  4,  7, 4,
    4, 4,  4,  4,  4,  4,  7,  4,  4, 4,  4,  4,  4,  4,  7, 4,
    4, 4,  4,  4,  4,  4,  7,  4,  4, 4,  4,  4,  4,  4,  7, 4,
    5, 10, 10, 10, 11, 11, 7,  11, 5, 10, 10, 10, 11, 17, 7, 11,
    5, 10, 10, 10, 11, 11, 7,  11, 5, 10, 10, 10, 11, 17, 7, 11,
    5, 10, 10, 18, 11, 11, 7,  11, 5, 5,  10, 4,  11, 17, 7, 11,
    5, 10, 10, 4,  11, 11, 7,  11, 5, 5,  10, 4,  11, 17, 7, 11
}

local interrupt_vectors = {
    [0x00] = 0xC7,
    [0x01] = 0xCF,
    [0x02] = 0xD7,
    [0x03] = 0xDF,
    [0x04] = 0xE7,
    [0x05] = 0xEF,
    [0x06] = 0xF7,
    [0x07] = 0xFF
}

local REG_A = 1
local REG_B = 2
local REG_C = 3
local REG_D = 4
local REG_E = 5
local REG_F = 6
local REG_H = 7
local REG_L = 8

local FLAG_C = 0x01
local FLAG_P = 0x04
local FLAG_A = 0x10
local FLAG_Z = 0x40
local FLAG_S = 0x80

local function fetch_byte(self)
    local byte = self.memory:read8(self.pc)
    self.pc = band(self.pc + 1, 0xFFFF)
    return byte
end

local function fetch_word(self)
    local word = self.memory:read16_l(self.pc)
    self.pc = band(self.pc + 2, 0xFFFF)
    return word
end

local function set_bc(self, val)
    self.regs[REG_B] = rshift(val, 8)
    self.regs[REG_C] = band(val, 0xFF)
end

local function set_de(self, val)
    self.regs[REG_D] = rshift(val, 8)
    self.regs[REG_E] = band(val, 0xFF)
end

local function set_hl(self, val)
    self.regs[REG_H] = rshift(val, 8)
    self.regs[REG_L] = band(val, 0xFF)
end

local function get_bc(self)
    return bor(self.regs[REG_C], lshift(self.regs[REG_B], 8))
end

local function get_de(self)
    return bor(self.regs[REG_E], lshift(self.regs[REG_D], 8))
end

local function get_hl(self)
    return bor(self.regs[REG_L], lshift(self.regs[REG_H], 8))
end

local function cpu_push(self, val)
    self.sp = band(self.sp - 2, 0xFFFF)
    self.memory:write16_l(self.sp, val)
end

local function cpu_pop(self)
    local ret = self.memory:read16_l(self.sp)
    self.sp = band(self.sp + 2, 0xFFFF)
    return ret
end

local function set_flag(self, mask)
    self.regs[REG_F] = bor(self.regs[REG_F], mask)
end

local function clear_flag(self, mask)
    self.regs[REG_F] = band(self.regs[REG_F], bnot(mask))
end

local function write_flag(self, mask, val)
    if val then
        self.regs[REG_F] = bor(self.regs[REG_F], mask)
    else
        self.regs[REG_F] = band(self.regs[REG_F], bnot(mask))
    end
end

local function set_zsp(self, val)
    write_flag(self, FLAG_Z, val == 0)
    write_flag(self, FLAG_S, band(val, 0x80) ~= 0)

    self.regs[REG_F] = bor(band(self.regs[REG_F], bnot(FLAG_P)), lshift(common.parity_table[band(val, 0xFF)], 2))
end

local function cpu_inr(self, val)
    local result = band(val + 1, 0xFF)

    write_flag(self, FLAG_A, band(result, 0x0F) == 0)
    set_zsp(self, result)

    return result
end

local function cpu_dcr(self, val)
    local result = band(val - 1, 0xFF)

    write_flag(self, FLAG_A, band(result, 0x0F) ~= 0x0F)
    set_zsp(self, result)

    return result
end

local function cpu_add(self, val, cf)
    local oper1 = self.regs[REG_A]
    local result = oper1 + val + cf
    local bresult = bxor(bxor(result, oper1), val)

    write_flag(self, FLAG_C, band(bresult, 0x100) ~= 0)
    write_flag(self, FLAG_A, band(bresult, 0x010) ~= 0)
    set_zsp(self, band(result, 0xFF))

    self.regs[REG_A] = band(result, 0xFF)
end

local function cpu_sub(self, val, cf)
    local result = self.regs[REG_A] - val - cf
    local bresult = bxor(result, bxor(self.regs[REG_A], val))

    write_flag(self, FLAG_C, band(bresult, 0x100) ~= 0)
    write_flag(self, FLAG_A, band(bresult, 0x010) == 0)
    set_zsp(self, band(result, 0xFF))

    self.regs[REG_A] = band(result, 0xFF)
end

local function cpu_ana(self, val)
    local oper1 = self.regs[REG_A]
    local result = band(oper1, val)

    clear_flag(self, FLAG_C)
    write_flag(self, FLAG_A, band(bor(oper1, val), 0x08) ~= 0)
    set_zsp(self, result)

    self.regs[REG_A] = result
end

local function cpu_ora(self, val)
    local result = bor(self.regs[REG_A], val)

    clear_flag(self, FLAG_C)
    clear_flag(self, FLAG_A)
    set_zsp(self, result)

    self.regs[REG_A] = result
end

local function cpu_xra(self, val)
    local result = bxor(self.regs[REG_A], val)

    clear_flag(self, FLAG_C)
    clear_flag(self, FLAG_A)
    set_zsp(self, result)

    self.regs[REG_A] = result
end

local function cpu_cmp(self, val)
    local oper1 = self.regs[REG_A]
    local result = oper1 - val

    write_flag(self, FLAG_C, rshift(result, 8) ~= 0)
    write_flag(self, FLAG_A, band(bnot(bxor(bxor(oper1, result), val)), 0x10) ~= 0)
    set_zsp(self, band(result, 0xFF))
end

local function cpu_dad(self, val)
    local result = get_hl(self) + val

    write_flag(self, FLAG_C, band(result, 0x10000) ~= 0)
    set_hl(self, band(result, 0xFFFF))
end

local opcodes = {}

opcodes[0x00] = function(self) -- NOP
end
opcodes[0x08] = opcodes[0x00]
opcodes[0x10] = opcodes[0x00]
opcodes[0x18] = opcodes[0x00]
opcodes[0x20] = opcodes[0x00]
opcodes[0x28] = opcodes[0x00]
opcodes[0x30] = opcodes[0x00]
opcodes[0x38] = opcodes[0x00]

opcodes[0x01] = function(self) -- LXI B, NN
    set_bc(self, fetch_word(self))
end

opcodes[0x11] = function(self) -- LXI D, NN
    set_de(self, fetch_word(self))
end

opcodes[0x21] = function(self) -- LXI H, NN
    set_hl(self, fetch_word(self))
end

opcodes[0x31] = function(self) -- LXI SP, NN
    self.sp = fetch_word(self)
end

opcodes[0x02] = function(self) -- STAX B
    self.memory:write8(get_bc(self), self.regs[REG_A])
end

opcodes[0x12] = function(self) -- STAX D
    self.memory:write8(get_de(self), self.regs[REG_A])
end

opcodes[0x22] = function(self) -- SHLD NN
    self.memory:write16_l(fetch_word(self), get_hl(self))
end

opcodes[0x32] = function(self) -- STA NN
    self.memory:write8(fetch_word(self), self.regs[REG_A])
end

opcodes[0x03] = function(self) -- INX B
    set_bc(self, band(get_bc(self) + 1, 0xFFFF))
end

opcodes[0x13] = function(self) -- INX D
    set_de(self, band(get_de(self) + 1, 0xFFFF))
end

opcodes[0x23] = function(self) -- INX H
    set_hl(self, band(get_hl(self) + 1, 0xFFFF))
end

opcodes[0x33] = function(self) -- INX SP
    self.sp = band(self.sp + 1, 0xFFFF)
end

opcodes[0x04] = function(self) -- INR B
    self.regs[REG_B] = cpu_inr(self, self.regs[REG_B])
end

opcodes[0x14] = function(self) -- INR D
    self.regs[REG_D] = cpu_inr(self, self.regs[REG_D])
end

opcodes[0x24] = function(self) -- INR H
    self.regs[REG_H] = cpu_inr(self, self.regs[REG_H])
end

opcodes[0x34] = function(self) -- INR M
    local hl = get_hl(self)
    self.memory:write8(hl, cpu_inr(self, self.memory:read8(hl)))
end

opcodes[0x05] = function(self) -- DCR B
    self.regs[REG_B] = cpu_dcr(self, self.regs[REG_B])
end

opcodes[0x15] = function(self) -- DCR D
    self.regs[REG_D] = cpu_dcr(self, self.regs[REG_D])
end

opcodes[0x25] = function(self) -- DCR H
    self.regs[REG_H] = cpu_dcr(self, self.regs[REG_H])
end

opcodes[0x35] = function(self) -- DCR M
    local hl = get_hl(self)
    self.memory:write8(hl, cpu_dcr(self, self.memory:read8(hl)))
end

opcodes[0x06] = function(self) -- MVI B, N
    self.regs[REG_B] = fetch_byte(self)
end

opcodes[0x16] = function(self) -- MVI D, N
    self.regs[REG_D] = fetch_byte(self)
end

opcodes[0x26] = function(self) -- MVI H, N
    self.regs[REG_H] = fetch_byte(self)
end

opcodes[0x36] = function(self) -- MVI M, N
    self.memory:write8(get_hl(self), fetch_byte(self))
end

opcodes[0x07] = function(self) -- RLC
    local a = self.regs[REG_A]
    local cf = rshift(a, 7)

    write_flag(self, FLAG_C, cf ~= 0)
    self.regs[REG_A] = band(bor(lshift(a, 1), cf), 0xFF)
end

opcodes[0x17] = function(self) -- RAL
    local a = self.regs[REG_A]

    self.regs[REG_A] = band(bor(lshift(a, 1), band(self.regs[REG_F], FLAG_C)), 0xFF)
    write_flag(self, FLAG_C, rshift(a, 7) ~= 0)
end

opcodes[0x27] = function(self)
    local a = self.regs[REG_A]
    local flags = self.regs[REG_F]
    local cf = band(flags, FLAG_C)
    local correction = 0
    local lsb = band(a, 0x0F)
    local msb = rshift(a, 4)

    if (band(flags, FLAG_A) ~= 0) or (lsb > 9) then
        correction = correction + 0x06
    end

    if (cf ~= 0) or (msb > 9) or ((msb >= 9) and (lsb > 9)) then
        correction = correction + 0x60
        cf = FLAG_C
    end

    cpu_add(self, correction, 0)
    write_flag(self, FLAG_C, cf ~= 0)
end

opcodes[0x37] = function(self) -- STC
    set_flag(self, FLAG_C)
end

opcodes[0x09] = function(self) -- DAD BC
    cpu_dad(self, get_bc(self))
end

opcodes[0x19] = function(self) -- DAD DE
    cpu_dad(self, get_de(self))
end

opcodes[0x29] = function(self) -- DAD HL
    cpu_dad(self, get_hl(self))
end

opcodes[0x39] = function(self) -- DAD SP
    cpu_dad(self, self.sp)
end

opcodes[0x0A] = function(self) -- LDAX BC
    self.regs[REG_A] = self.memory:read8(get_bc(self))
end

opcodes[0x1A] = function(self) -- LDAX DE
    self.regs[REG_A] = self.memory:read8(get_de(self))
end

opcodes[0x2A] = function(self) -- LHLD NN
    set_hl(self, self.memory:read16_l(fetch_word(self)))
end

opcodes[0x3A] = function(self) -- LDA NN
    self.regs[REG_A] = self.memory:read8(fetch_word(self))
end

opcodes[0x0B] = function(self) -- DCX BC
    set_bc(self, band(get_bc(self) - 1, 0xFFFF))
end

opcodes[0x1B] = function(self) -- DCX DE
    set_de(self, band(get_de(self) - 1, 0xFFFF))
end

opcodes[0x2B] = function(self) -- DCX HL
    set_hl(self, band(get_hl(self) - 1, 0xFFFF))
end

opcodes[0x3B] = function(self) -- DCX SP
    self.sp = band(self.sp - 1, 0xFFFF)
end

opcodes[0x0C] = function(self) -- INR C
    self.regs[REG_C] = cpu_inr(self, self.regs[REG_C])
end

opcodes[0x1C] = function(self) -- INR E
    self.regs[REG_E] = cpu_inr(self, self.regs[REG_E])
end

opcodes[0x2C] = function(self) -- INR L
    self.regs[REG_L] = cpu_inr(self, self.regs[REG_L])
end

opcodes[0x3C] = function(self) -- INR A
    self.regs[REG_A] = cpu_inr(self, self.regs[REG_A])
end

opcodes[0x0D] = function(self) -- DCR C
    self.regs[REG_C] = cpu_dcr(self, self.regs[REG_C])
end

opcodes[0x1D] = function(self) -- DCR E
    self.regs[REG_E] = cpu_dcr(self, self.regs[REG_E])
end

opcodes[0x2D] = function(self) -- DCR L
    self.regs[REG_L] = cpu_dcr(self, self.regs[REG_L])
end

opcodes[0x3D] = function(self) -- DCR A
    self.regs[REG_A] = cpu_dcr(self, self.regs[REG_A])
end

opcodes[0x0E] = function(self) -- MVI C, N
    self.regs[REG_C] = fetch_byte(self)
end

opcodes[0x1E] = function(self) -- MVI E, N
    self.regs[REG_E] = fetch_byte(self)
end

opcodes[0x2E] = function(self) -- MVI L, N
    self.regs[REG_L] = fetch_byte(self)
end

opcodes[0x3E] = function(self) -- MVI A, N
    self.regs[REG_A] = fetch_byte(self)
end

opcodes[0x0F] = function(self) -- RRC
    local a = self.regs[REG_A]
    local cf = band(a, 0x01)

    write_flag(self, FLAG_C, cf ~= 0)
    self.regs[REG_A] = band(bor(rshift(a, 1), lshift(cf, 7)), 0xFF)
end

opcodes[0x1F] = function(self) -- RAR
    local a = self.regs[REG_A]

    self.regs[REG_A] = band(bor(rshift(a, 1), lshift(band(self.regs[REG_F], FLAG_C), 7)), 0xFF)
    write_flag(self, FLAG_C, band(a, 0x01) ~= 0)
end

opcodes[0x2F] = function(self) -- CMA
    self.regs[REG_A] = band(bnot(self.regs[REG_A]), 0xFF)
end

opcodes[0x3F] = function(self) -- CMC
    self.regs[REG_F] = bxor(self.regs[REG_F], FLAG_C)
end

opcodes[0x40] = function(self) -- MOV B, B
end

opcodes[0x50] = function(self) -- MOV D, B
    self.regs[REG_D] = self.regs[REG_B]
end

opcodes[0x60] = function(self) -- MOV H, B
    self.regs[REG_H] = self.regs[REG_B]
end

opcodes[0x70] = function(self) -- MOV M, B
    self.memory:write8(get_hl(self), self.regs[REG_B])
end

opcodes[0x41] = function(self) -- MOV B, C
    self.regs[REG_B] = self.regs[REG_C]
end

opcodes[0x51] = function(self) -- MOV D, C
    self.regs[REG_D] = self.regs[REG_C]
end

opcodes[0x61] = function(self) -- MOV H, C
    self.regs[REG_H] = self.regs[REG_C]
end

opcodes[0x71] = function(self) -- MOV M, C
    self.memory:write8(get_hl(self), self.regs[REG_C])
end

opcodes[0x42] = function(self) -- MOV B, D
    self.regs[REG_B] = self.regs[REG_D]
end

opcodes[0x52] = function(self) -- MOV D, D
end

opcodes[0x62] = function(self) -- MOV H, D
    self.regs[REG_H] = self.regs[REG_D]
end

opcodes[0x72] = function(self) -- MOV M, D
    self.memory:write8(get_hl(self), self.regs[REG_D])
end

opcodes[0x43] = function(self) -- MOV B, E
    self.regs[REG_B] = self.regs[REG_E]
end

opcodes[0x53] = function(self) -- MOV D, E
    self.regs[REG_D] = self.regs[REG_E]
end

opcodes[0x63] = function(self) -- MOV H, E
    self.regs[REG_H] = self.regs[REG_E]
end

opcodes[0x73] = function(self) -- MOV M, E
    self.memory:write8(get_hl(self), self.regs[REG_E])
end

opcodes[0x44] = function(self) -- MOV B, H
    self.regs[REG_B] = self.regs[REG_H]
end

opcodes[0x54] = function(self) -- MOV D, H
    self.regs[REG_D] = self.regs[REG_H]
end

opcodes[0x64] = function(self) -- MOV H, H
end

opcodes[0x74] = function(self) -- MOV M, H
    self.memory:write8(get_hl(self), self.regs[REG_H])
end

opcodes[0x45] = function(self) -- MOV B, L
    self.regs[REG_B] = self.regs[REG_L]
end

opcodes[0x55] = function(self) -- MOV D, L
    self.regs[REG_D] = self.regs[REG_L]
end

opcodes[0x65] = function(self) -- MOV H, L
    self.regs[REG_H] = self.regs[REG_L]
end

opcodes[0x75] = function(self) -- MOV M, L
    self.memory:write8(get_hl(self), self.regs[REG_L])
end

opcodes[0x46] = function(self) -- MOV B, M
    self.regs[REG_B] = self.memory:read8(get_hl(self))
end

opcodes[0x56] = function(self) -- MOV D, M
    self.regs[REG_D] = self.memory:read8(get_hl(self))
end

opcodes[0x66] = function(self) -- MOV H, M
    self.regs[REG_H] = self.memory:read8(get_hl(self))
end

opcodes[0x76] = function(self) -- HLT
    self.halted = true
end

opcodes[0x47] = function(self) -- MOV B, A
    self.regs[REG_B] = self.regs[REG_A]
end

opcodes[0x57] = function(self) -- MOV D, A
    self.regs[REG_D] = self.regs[REG_A]
end

opcodes[0x67] = function(self) -- MOV H, A
    self.regs[REG_H] = self.regs[REG_A]
end

opcodes[0x77] = function(self) -- MOV M, A
    self.memory:write8(get_hl(self), self.regs[REG_A])
end

opcodes[0x48] = function(self) -- MOV C, B
    self.regs[REG_C] = self.regs[REG_B]
end

opcodes[0x58] = function(self) -- MOV E, B
    self.regs[REG_E] = self.regs[REG_B]
end

opcodes[0x68] = function(self) -- MOV L, B
    self.regs[REG_L] = self.regs[REG_B]
end

opcodes[0x78] = function(self) -- MOV A, B
    self.regs[REG_A] = self.regs[REG_B]
end

opcodes[0x49] = function(self) -- MOV C, C
end

opcodes[0x59] = function(self) -- MOV E, C
    self.regs[REG_E] = self.regs[REG_C]
end

opcodes[0x69] = function(self) -- MOV L, C
    self.regs[REG_L] = self.regs[REG_C]
end

opcodes[0x79] = function(self) -- MOV A, C
    self.regs[REG_A] = self.regs[REG_C]
end

opcodes[0x4A] = function(self) -- MOV C, D
    self.regs[REG_C] = self.regs[REG_D]
end

opcodes[0x5A] = function(self) -- MOV E, D
    self.regs[REG_E] = self.regs[REG_D]
end

opcodes[0x6A] = function(self) -- MOV L, D
    self.regs[REG_L] = self.regs[REG_D]
end

opcodes[0x7A] = function(self) -- MOV A, D
    self.regs[REG_A] = self.regs[REG_D]
end

opcodes[0x4B] = function(self) -- MOV C, E
    self.regs[REG_C] = self.regs[REG_E]
end

opcodes[0x5B] = function(self) -- MOV E, E
end

opcodes[0x6B] = function(self) -- MOV L, E
    self.regs[REG_L] = self.regs[REG_E]
end

opcodes[0x7B] = function(self) -- MOV A, E
    self.regs[REG_A] = self.regs[REG_E]
end

opcodes[0x4C] = function(self) -- MOV C, H
    self.regs[REG_C] = self.regs[REG_H]
end

opcodes[0x5C] = function(self) -- MOV E, H
    self.regs[REG_E] = self.regs[REG_H]
end

opcodes[0x6C] = function(self) -- MOV L, H
    self.regs[REG_L] = self.regs[REG_H]
end

opcodes[0x7C] = function(self) -- MOV A, H
    self.regs[REG_A] = self.regs[REG_H]
end

opcodes[0x4D] = function(self) -- MOV C, L
    self.regs[REG_C] = self.regs[REG_L]
end

opcodes[0x5D] = function(self) -- MOV E, L
    self.regs[REG_E] = self.regs[REG_L]
end

opcodes[0x6D] = function(self) -- MOV L, L
end

opcodes[0x7D] = function(self) -- MOV A, L
    self.regs[REG_A] = self.regs[REG_L]
end

opcodes[0x4E] = function(self) -- MOV C, M
    self.regs[REG_C] = self.memory:read8(get_hl(self))
end

opcodes[0x5E] = function(self) -- MOV E, M
    self.regs[REG_E] = self.memory:read8(get_hl(self))
end

opcodes[0x6E] = function(self) -- MOV L, M
    self.regs[REG_L] = self.memory:read8(get_hl(self))
end

opcodes[0x7E] = function(self) -- MOV A, M
    self.regs[REG_A] = self.memory:read8(get_hl(self))
end

opcodes[0x4F] = function(self) -- MOV C, A
    self.regs[REG_C] = self.regs[REG_A]
end

opcodes[0x5F] = function(self) -- MOV E, A
    self.regs[REG_E] = self.regs[REG_A]
end

opcodes[0x6F] = function(self) -- MOV L, A
    self.regs[REG_L] = self.regs[REG_A]
end

opcodes[0x7F] = function(self) -- MOV A, A
end

opcodes[0x80] = function(self) -- ADD B
    cpu_add(self, self.regs[REG_B], 0)
end

opcodes[0x90] = function(self) -- SUB B
    cpu_sub(self, self.regs[REG_B], 0)
end

opcodes[0xA0] = function(self) -- ANA B
    cpu_ana(self, self.regs[REG_B])
end

opcodes[0xB0] = function(self) -- ORA B
    cpu_ora(self, self.regs[REG_B])
end

opcodes[0x81] = function(self) -- ADD C
    cpu_add(self, self.regs[REG_C], 0)
end

opcodes[0x91] = function(self) -- SUB C
    cpu_sub(self, self.regs[REG_C], 0)
end

opcodes[0xA1] = function(self) -- ANA C
    cpu_ana(self, self.regs[REG_C])
end

opcodes[0xB1] = function(self) -- ORA C
    cpu_ora(self, self.regs[REG_C])
end

opcodes[0x82] = function(self) -- ADD D
    cpu_add(self, self.regs[REG_D], 0)
end

opcodes[0x92] = function(self) -- SUB D
    cpu_sub(self, self.regs[REG_D], 0)
end

opcodes[0xA2] = function(self) -- ANA D
    cpu_ana(self, self.regs[REG_D])
end

opcodes[0xB2] = function(self) -- ORA D
    cpu_ora(self, self.regs[REG_D])
end

opcodes[0x83] = function(self) -- ADD E
    cpu_add(self, self.regs[REG_E], 0)
end

opcodes[0x93] = function(self) -- SUB E
    cpu_sub(self, self.regs[REG_E], 0)
end

opcodes[0xA3] = function(self) -- ANA E
    cpu_ana(self, self.regs[REG_E])
end

opcodes[0xB3] = function(self) -- ORA E
    cpu_ora(self, self.regs[REG_E])
end

opcodes[0x84] = function(self) -- ADD H
    cpu_add(self, self.regs[REG_H], 0)
end

opcodes[0x94] = function(self) -- SUB H
    cpu_sub(self, self.regs[REG_H], 0)
end

opcodes[0xA4] = function(self) -- ANA H
    cpu_ana(self, self.regs[REG_H])
end

opcodes[0xB4] = function(self) -- ORA H
    cpu_ora(self, self.regs[REG_H])
end

opcodes[0x85] = function(self) -- ADD L
    cpu_add(self, self.regs[REG_L], 0)
end

opcodes[0x95] = function(self) -- SUB L
    cpu_sub(self, self.regs[REG_L], 0)
end

opcodes[0xA5] = function(self) -- ANA L
    cpu_ana(self, self.regs[REG_L])
end

opcodes[0xB5] = function(self) -- ORA L
    cpu_ora(self, self.regs[REG_L])
end

opcodes[0x86] = function(self) -- ADD M
    cpu_add(self, self.memory:read8(get_hl(self)), 0)
end

opcodes[0x96] = function(self) -- SUB M
    cpu_sub(self, self.memory:read8(get_hl(self)), 0)
end

opcodes[0xA6] = function(self) -- ANA M
    cpu_ana(self, self.memory:read8(get_hl(self)))
end

opcodes[0xB6] = function(self) -- ORA M
    cpu_ora(self, self.memory:read8(get_hl(self)))
end

opcodes[0x87] = function(self) -- ADD A
    cpu_add(self, self.regs[REG_A], 0)
end

opcodes[0x97] = function(self) -- SUB A
    cpu_sub(self, self.regs[REG_A], 0)
end

opcodes[0xA7] = function(self) -- ANA A
    cpu_ana(self, self.regs[REG_A])
end

opcodes[0xB7] = function(self) -- ORA A
    cpu_ora(self, self.regs[REG_A])
end

opcodes[0x88] = function(self) -- ADC B
    cpu_add(self, self.regs[REG_B], band(self.regs[REG_F], FLAG_C))
end

opcodes[0x98] = function(self) -- SBB B
    cpu_sub(self, self.regs[REG_B], band(self.regs[REG_F], FLAG_C))
end

opcodes[0xA8] = function(self) -- XRA B
    cpu_xra(self, self.regs[REG_B])
end

opcodes[0xB8] = function(self) -- CMP B
    cpu_cmp(self, self.regs[REG_B])
end

opcodes[0x89] = function(self) -- ADC C
    cpu_add(self, self.regs[REG_C], band(self.regs[REG_F], FLAG_C))
end

opcodes[0x99] = function(self) -- SBB C
    cpu_sub(self, self.regs[REG_C], band(self.regs[REG_F], FLAG_C))
end

opcodes[0xA9] = function(self) -- XRA C
    cpu_xra(self, self.regs[REG_C])
end

opcodes[0xB9] = function(self) -- CMP C
    cpu_cmp(self, self.regs[REG_C])
end

opcodes[0x8A] = function(self) -- ADC D
    cpu_add(self, self.regs[REG_D], band(self.regs[REG_F], FLAG_C))
end

opcodes[0x9A] = function(self) -- SBB D
    cpu_sub(self, self.regs[REG_D], band(self.regs[REG_F], FLAG_C))
end

opcodes[0xAA] = function(self) -- XRA D
    cpu_xra(self, self.regs[REG_D])
end

opcodes[0xBA] = function(self) -- CMP D
    cpu_cmp(self, self.regs[REG_D])
end

opcodes[0x8B] = function(self) -- ADC E
    cpu_add(self, self.regs[REG_E], band(self.regs[REG_F], FLAG_C))
end

opcodes[0x9B] = function(self) -- SBB E
    cpu_sub(self, self.regs[REG_E], band(self.regs[REG_F], FLAG_C))
end

opcodes[0xAB] = function(self) -- XRA E
    cpu_xra(self, self.regs[REG_E])
end

opcodes[0xBB] = function(self) -- CMP E
    cpu_cmp(self, self.regs[REG_E])
end

opcodes[0x8C] = function(self) -- ADC H
    cpu_add(self, self.regs[REG_H], band(self.regs[REG_F], FLAG_C))
end

opcodes[0x9C] = function(self) -- SBB H
    cpu_sub(self, self.regs[REG_H], band(self.regs[REG_F], FLAG_C))
end

opcodes[0xAC] = function(self) -- XRA H
    cpu_xra(self, self.regs[REG_H])
end

opcodes[0xBC] = function(self) -- CMP H
    cpu_cmp(self, self.regs[REG_H])
end

opcodes[0x8D] = function(self) -- ADC L
    cpu_add(self, self.regs[REG_L], band(self.regs[REG_F], FLAG_C))
end

opcodes[0x9D] = function(self) -- SBB L
    cpu_sub(self, self.regs[REG_L], band(self.regs[REG_F], FLAG_C))
end

opcodes[0xAD] = function(self) -- XRA L
    cpu_xra(self, self.regs[REG_L])
end

opcodes[0xBD] = function(self) -- CMP L
    cpu_cmp(self, self.regs[REG_L])
end

opcodes[0x8E] = function(self) -- ADC M
    cpu_add(self, self.memory:read8(get_hl(self)), band(self.regs[REG_F], FLAG_C))
end

opcodes[0x9E] = function(self) -- SBB M
    cpu_sub(self, self.memory:read8(get_hl(self)), band(self.regs[REG_F], FLAG_C))
end

opcodes[0xAE] = function(self) -- XRA M
    cpu_xra(self, self.memory:read8(get_hl(self)))
end

opcodes[0xBE] = function(self) -- CMP M
    cpu_cmp(self, self.memory:read8(get_hl(self)))
end

opcodes[0x8F] = function(self) -- ADC A
    cpu_add(self, self.regs[REG_A], band(self.regs[REG_F], FLAG_C))
end

opcodes[0x9F] = function(self) -- SBB A
    cpu_sub(self, self.regs[REG_A], band(self.regs[REG_F], FLAG_C))
end

opcodes[0xAF] = function(self) -- XRA A
    cpu_xra(self, self.regs[REG_A])
end

opcodes[0xBF] = function(self) -- CMP A
    cpu_cmp(self, self.regs[REG_A])
end

opcodes[0xC0] = function(self) -- RNZ
    if band(self.regs[REG_F], FLAG_Z) == 0 then
        self.pc = cpu_pop(self)
        self.cycles = self.cycles + 6
    end
end

opcodes[0xD0] = function(self) -- RNC
    if band(self.regs[REG_F], FLAG_C) == 0 then
        self.pc = cpu_pop(self)
        self.cycles = self.cycles + 6
    end
end

opcodes[0xE0] = function(self) -- RPO
    if band(self.regs[REG_F], FLAG_P) == 0 then
        self.pc = cpu_pop(self)
        self.cycles = self.cycles + 6
    end
end

opcodes[0xF0] = function(self) -- RP
    if band(self.regs[REG_F], FLAG_S) == 0 then
        self.pc = cpu_pop(self)
        self.cycles = self.cycles + 6
    end
end

opcodes[0xC1] = function(self) -- POP BC
    set_bc(self, cpu_pop(self))
end

opcodes[0xD1] = function(self) -- POP DE
    set_de(self, cpu_pop(self))
end

opcodes[0xE1] = function(self) -- POP HL
    set_hl(self, cpu_pop(self))
end

opcodes[0xF1] = function(self) -- POP PSW
    local val = cpu_pop(self)

    self.regs[REG_A] = rshift(val, 8)
    self.regs[REG_F] = band(val, 0xD7)
end

opcodes[0xC2] = function(self) -- JNZ NN
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_Z) == 0 then
        self.pc = addr
    end
end

opcodes[0xD2] = function(self) -- JNC
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_C) == 0 then
        self.pc = addr
    end
end

opcodes[0xE2] = function(self) -- JPO
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_P) == 0 then
        self.pc = addr
    end
end

opcodes[0xF2] = function(self) -- JP
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_S) == 0 then
        self.pc = addr
    end
end

opcodes[0xC3] = function(self) -- JMP NN
    self.pc = fetch_word(self)
end

opcodes[0xD3] = function(self) -- OUT N
    local port_addr = fetch_byte(self)

    self.io:out_port(port_addr, self.regs[REG_A])
end

opcodes[0xE3] = function(self) -- XTHL
    local val = self.memory:read16_l(self.sp)

    self.memory:write16_l(self.sp, get_hl(self))
    set_hl(self, val)
end

opcodes[0xF3] = function(self) -- DI
    self.iff = false
end

opcodes[0xC4] = function(self) -- CNZ
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_Z) == 0 then
        cpu_push(self, self.pc)

        self.pc = addr
        self.cycles = self.cycles + 6
    end
end

opcodes[0xD4] = function(self) -- CNC
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_C) == 0 then
        cpu_push(self, self.pc)

        self.pc = addr
        self.cycles = self.cycles + 6
    end
end

opcodes[0xE4] = function(self) -- CPO
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_P) == 0 then
        cpu_push(self, self.pc)

        self.pc = addr
        self.cycles = self.cycles + 6
    end
end

opcodes[0xF4] = function(self) -- CP
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_S) == 0 then
        cpu_push(self, self.pc)

        self.pc = addr
        self.cycles = self.cycles + 6
    end
end

opcodes[0xC5] = function(self) -- PUSH BC
    cpu_push(self, get_bc(self))
end

opcodes[0xD5] = function(self) -- PUSH DE
    cpu_push(self, get_de(self))
end

opcodes[0xE5] = function(self) -- PUSH HL
    cpu_push(self, get_hl(self))
end

opcodes[0xF5] = function(self) -- PUSH PSW
    cpu_push(self, bor(bor(self.regs[REG_F], lshift(self.regs[REG_A], 8)), 0x02))
end

opcodes[0xC6] = function(self) -- ADI N
    cpu_add(self, fetch_byte(self), 0)
end

opcodes[0xD6] = function(self) -- SUI N
    cpu_sub(self, fetch_byte(self), 0)
end

opcodes[0xE6] = function(self) -- ANI N
    cpu_ana(self, fetch_byte(self))
end

opcodes[0xF6] = function(self) -- ORI N
    cpu_ora(self, fetch_byte(self))
end

opcodes[0xC7] = function(self) -- RST 0
    cpu_push(self, self.pc)
    self.pc = 0x0000
end

opcodes[0xD7] = function(self) -- RST 2
    cpu_push(self, self.pc)
    self.pc = 0x0010
end

opcodes[0xE7] = function(self) -- RST 4
    cpu_push(self, self.pc)
    self.pc = 0x0020
end

opcodes[0xF7] = function(self) -- RST 6
    cpu_push(self, self.pc)
    self.pc = 0x0030
end

opcodes[0xC8] = function(self) -- RZ
    if band(self.regs[REG_F], FLAG_Z) ~= 0 then
        self.pc = cpu_pop(self)
        self.cycles = self.cycles + 6
    end
end

opcodes[0xD8] = function(self) -- RC
    if band(self.regs[REG_F], FLAG_C) ~= 0 then
        self.pc = cpu_pop(self)
        self.cycles = self.cycles + 6
    end
end

opcodes[0xE8] = function(self) -- RPE
    if band(self.regs[REG_F], FLAG_P) ~= 0 then
        self.pc = cpu_pop(self)
        self.cycles = self.cycles + 6
    end
end

opcodes[0xF8] = function(self) -- RM
    if band(self.regs[REG_F], FLAG_S) ~= 0 then
        self.pc = cpu_pop(self)
        self.cycles = self.cycles + 6
    end
end

opcodes[0xC9] = function(self) -- RET
    self.pc = cpu_pop(self)
end

opcodes[0xD9] = function(self) -- RET
    self.pc = cpu_pop(self)
end

opcodes[0xE9] = function(self) -- PCHL
    self.pc = get_hl(self)
end

opcodes[0xF9] = function(self) -- SPHL
    self.sp = get_hl(self)
end

opcodes[0xCA] = function(self) -- JZ
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_Z) ~= 0 then
        self.pc = addr
    end
end

opcodes[0xDA] = function(self) -- JC
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_C) ~= 0 then
        self.pc = addr
    end
end

opcodes[0xEA] = function(self) -- JPE
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_P) ~= 0 then
        self.pc = addr
    end
end

opcodes[0xFA] = function(self) -- JM
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_S) ~= 0 then
        self.pc = addr
    end
end

opcodes[0xCB] = function(self) -- JMP NN
    self.pc = fetch_word(self)
end

opcodes[0xDB] = function(self) -- IN N
    local port_addr = fetch_byte(self)
    self.regs[REG_A] = band(self.io:in_port(port_addr), 0xFF)
end

opcodes[0xEB] = function(self) -- XCHG
    local de = get_de(self)
    set_de(self, get_hl(self))
    set_hl(self, de)
end

opcodes[0xFB] = function(self) -- EI
    self.iff = true
    self.interrupt_delay = 1
end

opcodes[0xCC] = function(self) -- CZ NN
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_Z) ~= 0 then
        cpu_push(self, self.pc)
        self.pc = addr
        self.cycles = self.cycles + 6
    end
end

opcodes[0xDC] = function(self) -- CC NN
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_C) ~= 0 then
        cpu_push(self, self.pc)
        self.pc = addr
        self.cycles = self.cycles + 6
    end
end

opcodes[0xEC] = function(self) -- CPE NN
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_P) ~= 0 then
        cpu_push(self, self.pc)
        self.pc = addr
        self.cycles = self.cycles + 6
    end
end

opcodes[0xFC] = function(self) -- CM NN
    local addr = fetch_word(self)

    if band(self.regs[REG_F], FLAG_S) ~= 0 then
        cpu_push(self, self.pc)
        self.pc = addr
        self.cycles = self.cycles + 6
    end
end

opcodes[0xCD] = function(self) -- CALL NN
    local addr = fetch_word(self)

    cpu_push(self, self.pc)
    self.pc = addr
end
opcodes[0xDD] = opcodes[0xCD]
opcodes[0xED] = opcodes[0xCD]
opcodes[0xFD] = opcodes[0xCD]

opcodes[0xCE] = function(self) -- ACI N
    cpu_add(self, fetch_byte(self), band(self.regs[REG_F], FLAG_C))
end

opcodes[0xDE] = function(self) -- SBI N
    cpu_sub(self, fetch_byte(self), band(self.regs[REG_F], FLAG_C))
end

opcodes[0xEE] = function(self) -- XRI N
    cpu_xra(self, fetch_byte(self))
end

opcodes[0xFE] = function(self) -- CPI N
    cpu_cmp(self, fetch_byte(self))
end

opcodes[0xCF] = function(self) -- RST 1
    cpu_push(self, self.pc)
    self.pc = 0x08
end

opcodes[0xDF] = function(self) -- RST 3
    cpu_push(self, self.pc)
    self.pc = 0x18
end

opcodes[0xEF] = function(self) -- RST 5
    cpu_push(self, self.pc)
    self.pc = 0x28
end

opcodes[0xFF] = function(self) -- RST 7
    cpu_push(self, self.pc)
    self.pc = 0x38
end

local function execute(self, opcode)
    self.cycles = self.cycles + cycles[opcode]

    if self.interrupt_delay > 0 then
        self.interrupt_delay = self.interrupt_delay - 1
    end

    local instruction = opcodes[opcode]

    if instruction then
        instruction(self)
    else
        logger:error("i8080: Illegal instruction: 0x%02X", opcode)
    end
end

local function step(self)
    if self.int_pending and self.iff and (self.interrupt_delay == 0) then
        self.interrupt_delay = 0
        self.iff = false
        self.halted = false

        execute(self, self.interrupt_opcode)
    elseif not self.halted then
        execute(self, fetch_byte(self))
    end
end

local function call_interrupt(self, vector)
    self.interrupt_opcode = interrupt_vectors[band(vector, 0x07)]
    self.int_pending = true
end

local function get_io(self)
    return self.io
end

local function set_reset_vector(self, pc)
    self.reset_vector = pc
end

local function reset(self)
    for i = 1, 8, 1 do
        self.regs[i] = 0x00
    end

    self.sp = 0x0000
    self.pc = self.reset_vector
    self.cycles = 0
    self.interrupt_delay = 0
    self.interrupt_opcode = 0
    self.iff = false
    self.halted = false
    self.int_pending = false
end

function cpu.new(memory, pic)
    local self = {
        memory = memory,
        pic = pic,
        regs = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, -- A, B, C, D, E, F, H, L
        sp = 0x0000, -- Stack Pointer
        pc = 0x0000, -- Program Counter
        cycles = 0,
        interrupt_delay = 0,
        interrupt_opcode = 0,
        reset_vector = 0x0000,
        iff = false,
        halted = false,
        int_pending = false,
        get_io = get_io,
        set_reset_vector = set_reset_vector,
        step = step,
        interrupt = call_interrupt,
        reset = reset
    }

    self.io = io_ports.new(self)

    return self
end

return cpu
