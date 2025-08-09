-- =====================================================================================================================================================================
-- Intel 8088 CPU emulation.
-- =====================================================================================================================================================================

local logger = require("dave_logger:logger")("RetroComputers")
local common = require("retro_computers:emulator/hardware/cpu/common")
local io_ports = require("retro_computers:emulator/io_ports")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local cpu = {}

local FLAG_C = 0x0001
local FLAG_P = 0x0004
local FLAG_A = 0x0010
local FLAG_Z = 0x0040
local FLAG_S = 0x0080
local FLAG_T = 0x0100
local FLAG_I = 0x0200
local FLAG_D = 0x0400
local FLAG_O = 0x0800

local REG_AX = 1
local REG_CX = 2
local REG_DX = 3
local REG_BX = 4
local REG_SP = 5
local REG_BP = 6
local REG_SI = 7
local REG_DI = 8

local SEG_ES = 1
local SEG_CS = 2
local SEG_SS = 3
local SEG_DS = 4

-- AX, CX, DX, BX, SP, BP, SI, DI    ES, CS, SS, DS
local rm_seg_table = {
    [0] = SEG_DS,
    [1] = SEG_DS,
    [2] = SEG_SS,
    [3] = SEG_SS,
    [4] = SEG_DS,
    [5] = SEG_DS,
    [6] = SEG_SS,
    [7] = SEG_DS
}

local jmp_conds = {
    [0] = function(self) return band(self.flags, FLAG_O) ~= 0 end,
    function(self) return band(self.flags, FLAG_O) == 0 end,
    function(self) return band(self.flags, FLAG_C) ~= 0 end,
    function(self) return band(self.flags, FLAG_C) == 0 end,
    function(self) return band(self.flags, FLAG_Z) ~= 0 end,
    function(self) return band(self.flags, FLAG_Z) == 0 end,
    function(self) return (band(self.flags, FLAG_C) ~= 0) or (band(self.flags, FLAG_Z) ~= 0) end,
    function(self) return (band(self.flags, FLAG_C) == 0) and (band(self.flags, FLAG_Z) == 0) end,
    function(self) return band(self.flags, FLAG_S) ~= 0 end,
    function(self) return band(self.flags, FLAG_S) == 0 end,
    function(self) return band(self.flags, FLAG_P) ~= 0 end,
    function(self) return band(self.flags, FLAG_P) == 0 end,
    function(self) return (band(self.flags, FLAG_O) ~= 0) ~= (band(self.flags, FLAG_S) ~= 0) end,
    function(self) return (band(self.flags, FLAG_O) ~= 0) == (band(self.flags, FLAG_S) ~= 0) end,
    function(self) return (band(self.flags, FLAG_Z) ~= 0) or ((band(self.flags, FLAG_S) ~= 0) ~= (band(self.flags, FLAG_O) ~= 0)) end,
    function(self) return (band(self.flags, FLAG_Z) == 0) and ((band(self.flags, FLAG_S) ~= 0) == (band(self.flags, FLAG_O) ~= 0)) end
}

local mod_rm = {
    [0] = function(self) return self.regs[REG_BX] + self.regs[REG_SI] end,
    [1] = function(self) return self.regs[REG_BX] + self.regs[REG_DI] end,
    [2] = function(self) return self.regs[REG_BP] + self.regs[REG_SI] end,
    [3] = function(self) return self.regs[REG_BP] + self.regs[REG_DI] end,
    [4] = function(self) return self.regs[REG_SI] end,
    [5] = function(self) return self.regs[REG_DI] end,
    [6] = function(self) return self.regs[REG_BP] end,
    [7] = function(self) return self.regs[REG_BX] end
}

local function to_sign_8(value)
    if value >= 0x80 then
        return value - 0x100
    end

    return value
end

local function to_sign_16(value)
    if value >= 0x8000 then
        return value - 0x10000
    end

    return value
end

local function clear_flag(self, flag)
    self.flags = band(self.flags, bnot(flag))
end

local function set_flag(self, flag)
    self.flags = bor(self.flags, flag)
end

local function write_flag(self, flag, val)
    if val then
        set_flag(self, flag)
    else
        clear_flag(self, flag)
    end
end

local function set_of_add(self, bits, oper1, oper2, result)
    local mask = lshift(1, bits - 1)
    write_flag(self, FLAG_O, band(band(bxor(result, oper2), bxor(result, oper1)), mask) ~= 0)
end

local function set_of_sub(self, bits, oper1, oper2, result)
    local mask = lshift(1, bits - 1)
    write_flag(self, FLAG_O, band(band(bxor(oper1, oper2), bxor(result, oper1)), mask) ~= 0)
end

local function set_of_rot(self, bits, val, result)
    local mask = lshift(1, bits - 1)
    write_flag(self, FLAG_O, band(bxor(result, val), mask) ~= 0)
end

local function set_pzs(self, bits, result)
    local size_mask = lshift(1, bits) - 1
    local sign_mask = lshift(1, bits - 1)

    write_flag(self, FLAG_Z, band(result, size_mask) == 0)
    write_flag(self, FLAG_S, band(result, sign_mask) ~= 0)

    self.flags = bor(band(self.flags, bnot(FLAG_P)), lshift(common.parity_table[band(result, 0xFF)], 2))
end

local function set_apzs(self, bits, oper1, oper2, result)
    set_pzs(self, bits, result)
    write_flag(self, FLAG_A, band(bxor(bxor(result, oper2), oper1), 0x10) ~= 0)
end

local function set_flags_bit(self, bits, result)
    self.flags = band(self.flags, bnot(0x0811)) -- CF, AF, OF
    set_pzs(self, bits, result)
end

local function memory_read16(self, segment, offset)
    local low = self.memory:read8(segment + offset)
    local high = self.memory:read8(segment + band(offset + 1, 0xFFFF))

    return bor(low, lshift(high, 8))
end

local function read_memory(self, opcode, segment, offset)
    if band(opcode, 0x01) == 0x01 then
        return memory_read16(self, segment, band(offset, 0xFFFF))
    end

    return self.memory:read8(segment + band(offset, 0xFFFF))
end

local function fetch_byte(self)
    local addr = lshift(self.segments[SEG_CS], 4) + self.ip
    self.ip = band(self.ip + 1, 0xFFFF)
    return self.memory:read8(addr)
end

local function fetch_word(self)
    local addr = lshift(self.segments[SEG_CS], 4) + self.ip
    self.ip = band(self.ip + 2, 0xFFFF)
    return self.memory:read16_l(addr)
end

local function fetch(self, word)
    if word then
        return fetch_word(self)
    end

    return fetch_byte(self)
end

local function get_reg_byte(self, reg)
    local reg_index = band(reg, 0x03) + 1

    if reg > 3 then
        return rshift(self.regs[reg_index], 8)
    end

    return band(self.regs[reg_index], 0xFF)
end

local function get_reg(self, opcode, reg)
    if band(opcode, 0x1) == 0x1 then
        return self.regs[reg + 1]
    end

    return get_reg_byte(self, reg)
end

local function set_reg_byte(self, reg, val)
    local reg_index = band(reg, 0x03) + 1

    if reg > 3 then
        self.regs[reg_index] = bor(band(self.regs[reg_index], 0x00FF), lshift(band(val, 0xFF), 8))
    else
        self.regs[reg_index] = bor(band(self.regs[reg_index], 0xFF00), band(val, 0xFF))
    end
end

local function set_reg(self, opcode, reg, val)
    if band(opcode, 0x01) == 0x01 then
        self.regs[reg + 1] = band(val, 0xFFFF)
    else
        set_reg_byte(self, reg, val)
    end
end

local function do_mod_rm(self)
    local rm_data = fetch_byte(self)

    self.reg = band(rshift(rm_data, 3), 0x07)
    self.mode = band(rshift(rm_data, 6), 0x03)
    self.rm = band(rm_data, 0x07)

    if self.mode == 3 then
        return
    end

    if band(rm_data, 0xC7) == 0x06 then -- 0 mode, 6 R/M
        self.ea_addr = fetch_word(self)
        self.ea_seg = lshift(self.segments[self.segment_mode or SEG_DS], 4)
    else
        local temp_ea = mod_rm[self.rm](self)

        if self.mode == 1 then
            temp_ea = temp_ea + to_sign_8(fetch_byte(self))
        elseif self.mode == 2 then
            temp_ea = temp_ea + fetch_word(self)
        end

        self.ea_addr = band(temp_ea, 0xFFFF)
        self.ea_seg = lshift(self.segments[self.segment_mode or rm_seg_table[self.rm]], 4)
    end
end

local function read_rm_byte(self)
    if self.mode == 3 then
        return get_reg_byte(self, self.rm)
    end

    return self.memory:read8(self.ea_seg + self.ea_addr)
end

local function read_rm_word(self)
    if self.mode == 3 then
        return self.regs[self.rm + 1]
    end

    return memory_read16(self, self.ea_seg, self.ea_addr)
end

local function write_rm_byte(self, val)
    if self.mode == 3 then
        set_reg_byte(self, self.rm, val)
    else
        self.memory:write8(self.ea_seg + self.ea_addr, band(val, 0xFF))
    end
end

local function write_rm_word(self, val)
    if self.mode == 3 then
        self.regs[self.rm + 1] = band(val, 0xFFFF)
    else
        self.memory:write8(self.ea_seg + self.ea_addr, band(val, 0xFF))
        self.memory:write8(self.ea_seg + band(self.ea_addr + 1, 0xFFFF), band(rshift(val, 8), 0xFF))
    end
end

local function read_rm(self, opcode)
    if band(opcode, 0x01) == 0x01 then
        return read_rm_word(self)
    end

    return read_rm_byte(self)
end

local function write_rm(self, opcode, val)
    if band(opcode, 0x1) == 0x1 then
        write_rm_word(self, val)
    else
        write_rm_byte(self, val)
    end
end

local function cpu_push16(self, val)
    self.regs[REG_SP] = band(self.regs[REG_SP] - 2, 0xFFFF)

    local base = lshift(self.segments[SEG_SS], 4)
    local offset = self.regs[REG_SP]

    self.memory:write8(base + offset, band(val, 0xFF))
    self.memory:write8(base + band(offset + 1, 0xFFFF), rshift(val, 8))
end

local function cpu_pop16(self)
    local base_addr = lshift(self.segments[SEG_SS], 4)
    local low = self.memory:read8(base_addr + self.regs[REG_SP])
    local high = self.memory:read8(base_addr + band(self.regs[REG_SP] + 1, 0xFFFF))

    self.regs[REG_SP] = band(self.regs[REG_SP] + 2, 0xFFFF)
    return bor(low, lshift(high, 8))
end

local function cpu_in(self, word, port)
    if word then
        local low = self.io:in_port(port)
        local high = self.io:in_port(port + 1)

        return bor(low, lshift(high, 8))
    else
        return self.io:in_port(port)
    end
end

local function cpu_out(self, word, port, val)
    if word then
        self.io:out_port(port, band(val, 0xFF))
        self.io:out_port(port + 1, rshift(val, 8))
    else
        self.io:out_port(port, val)
    end
end

local function call_interrupt(self, id)
    local addr = lshift(id, 2)

    cpu_push16(self, band(self.flags, 0xFFD7))
    cpu_push16(self, self.segments[SEG_CS])
    cpu_push16(self, self.ip)

    self.ip = self.memory:read16_l(addr)
    self.segments[SEG_CS] = self.memory:read16_l(addr + 2)
    self.flags = band(self.flags, bnot(0x0300)) -- IF, TF
end

local function irq_pending(self)
    return ((band(self.flags, FLAG_T) ~= 0) or ((band(self.flags, FLAG_I) ~= 0) and self.pic.int_pending)) and (not self.no_int)
end

local function check_interrupts(self)
    if (band(self.flags, FLAG_T) ~= 0) and (not self.no_int) then
        call_interrupt(self, 0x01)
        return
    end

    if (band(self.flags, FLAG_I) ~= 0) and self.pic.int_pending and (not self.no_int) then
        self.repeating = false
        self.completed = true
        self.segment_mode = nil
        self.pic:irq_ack()
        local interrupt = self.pic:irq_ack()
        self.opcode = 0x00
        call_interrupt(self, interrupt)
        return
    end
end

local function cpu_add(self, opcode, alu_opcode, oper1, oper2)
    local bits = lshift(8, band(opcode, 0x01))
    local size_mask = lshift(1, bits) - 1
    local result = oper1 + oper2
    local carry = 0

    if (alu_opcode == 2) and (band(self.flags, FLAG_C) ~= 0) then
        carry = 1
    end

    set_of_add(self, bits, oper1, oper2 - carry, result)
    set_apzs(self, bits, oper1, oper2 - carry, result)

    if (alu_opcode == 2) and (band(oper2, size_mask) == 0) and (band(self.flags, FLAG_C) ~= 0) then
        set_flag(self, FLAG_C)
    else
        write_flag(self, FLAG_C, band(oper2, size_mask) > band(result, size_mask))
    end

    return result
end

local function cpu_or(self, opcode, alu_opcode, oper1, oper2)
    local bits = lshift(8, band(opcode, 0x01))
    local result = bor(oper1, oper2)
    set_flags_bit(self, bits, result)
    return result
end

local function cpu_test(self, opcode, alu_opcode, oper1, oper2)
    local bits = lshift(8, band(opcode, 0x01))
    local result = band(oper1, oper2)
    set_flags_bit(self, bits, result)
    return result
end

local function cpu_xor(self, opcode, alu_opcode, oper1, oper2)
    local bits = lshift(8, band(opcode, 0x01))
    local result = bxor(oper1, oper2)
    set_flags_bit(self, bits, result)
    return result
end

local function cpu_sub(self, opcode, alu_opcode, oper1, oper2)
    local bits = lshift(8, band(opcode, 0x01))
    local result = oper1 - oper2
    local size_mask = lshift(1, bits) - 1
    local carry = 0

    if (alu_opcode == 3) and (band(self.flags, FLAG_C) ~= 0) then
        carry = 1
    end

    set_apzs(self, bits, oper1, oper2 - carry, result)
    set_of_sub(self, bits, oper1, oper2 - carry, result)

    if (alu_opcode == 3) and (band(oper2, size_mask) == 0) and (band(self.flags, FLAG_C) ~= 0) then
        set_flag(self, FLAG_C)
    else
        write_flag(self, FLAG_C, band(oper2, size_mask) > band(oper1, size_mask))
    end

    return result
end

local function cpu_rol(self, bits, val)
    write_flag(self, FLAG_C, band(val, lshift(1, bits - 1)) ~= 0)
    local result = bor(lshift(val, 1), band(self.flags, FLAG_C))
    set_of_rot(self, bits, val, result)

    return result
end

local function cpu_ror(self, bits, val)
    local result = rshift(val, 1)

    write_flag(self, FLAG_C, band(val, 0x01) ~= 0)

    if band(self.flags, FLAG_C) ~= 0 then
        result = bor(result, lshift(1, bits - 1))
    end

    set_of_rot(self, bits, val, result)
    return result
end

local function cpu_rcl(self, bits, val)
    local result = bor(lshift(val, 1), band(self.flags, 0x01))

    write_flag(self, FLAG_C, band(val, lshift(1, bits - 1)) ~= 0)
    set_of_rot(self, bits, val, result)

    return result
end

local function cpu_rcr(self, bits, val)
    local result = rshift(val, 1)

    if band(self.flags, FLAG_C) ~= 0 then
        result = bor(result, lshift(1, bits - 1))
    end

    set_of_rot(self, bits, val, result)
    write_flag(self, FLAG_C, band(val, 0x01) ~= 0)

    return result
end

local function cpu_shl(self, bits, val)
    local mask = lshift(1, bits - 1)
    local result = lshift(val, 1)

    write_flag(self, FLAG_C, band(val, mask) ~= 0)
    set_of_rot(self, bits, val, result)
    write_flag(self, FLAG_A, band(result, 0x10) ~= 0)
    set_pzs(self, bits, result)

    return result
end

local function cpu_shr(self, bits, val)
    local result = rshift(val, 1)

    write_flag(self, FLAG_C, band(val, 0x01) ~= 0)
    set_of_rot(self, bits, val, result)
    clear_flag(self, FLAG_A)
    set_pzs(self, bits, result)

    return result
end

local function cpu_setmo(self, bits, val)
    clear_flag(self, FLAG_C)
    clear_flag(self, FLAG_A)
    clear_flag(self, FLAG_O)
    set_pzs(self, bits, 0xFFFF)
    return 0xFFFF
end

local function cpu_sar(self, bits, val)
    local mask = lshift(1, bits - 1)
    local result = bor(rshift(val, 1), band(val, mask))

    set_of_rot(self, bits, val, result)
    write_flag(self, FLAG_C, band(val, 0x1) ~= 0)
    clear_flag(self, FLAG_A)
    set_pzs(self, bits, result)

    return result
end

local function cpu_mul(self, bits, oper1, oper2)
    local size_mask = lshift(1, bits) - 1
    local a = band(oper1, size_mask)
    local b = band(oper2, size_mask)
    local c = 0
    local temp = 0
    local carry = band(a, 0x01)

    a = rshift(a, 1)

    for _ = 1, bits, 1 do
        if carry ~= 0 then
            local temp_c = c
            c = band(b + c, size_mask)
            carry = (band(temp_c, size_mask) > c) and 0x01 or 0x00
        end

        temp = bor(rshift(c, 1), lshift(carry, bits - 1))
        carry = band(c, 0x01)
        c = temp

        temp = bor(rshift(a, 1), lshift(carry, bits - 1))
        carry = band(a, 0x01)
        a = temp
    end

    write_flag(self, FLAG_C, c ~= 0)
    write_flag(self, FLAG_O, c ~= 0)

    return bor(a, lshift(c, bits))
end

local function cpu_imul(self, bits, oper1, oper2)
    local size_mask = lshift(1, bits) - 1
    local sign_mask = lshift(1, bits - 1)
    local high_bit = lshift(1, bits - 1)
    local a = oper1
    local b = oper2
    local c = 0
    local negate = false

    if band(a, high_bit) == 0 then
        if band(b, high_bit) ~= 0 then
            b = bnot(b) + 1
            negate = true
        end
    else
        a = bnot(a) + 1

        if band(b, high_bit) ~= 0 then
            b = bnot(b) + 1
            negate = false
        else
            negate = true
        end
    end

    local result = cpu_mul(self, bits, a, b)

    a = band(result, size_mask)
    c = rshift(result, bits)

    if negate then
        c = bnot(c)
        a = band(bnot(a) + 1, size_mask)

        if a == 0 then
            c = c + 1
        end
    end

    result = c + rshift(band(a, sign_mask), bits - 1)
    c = band(c, size_mask)

    set_apzs(self, 16, c, 0, result)
    write_flag(self, FLAG_C, result ~= 0)
    write_flag(self, FLAG_O, result ~= 0)

    return bor(a, lshift(c, bits))
end

local function cpu_div(self, bits, high, low, oper2)
    local size_mask = lshift(1, bits) - 1
    local high_bit = lshift(1, bits - 1)
    local tmp_high = high
    local tmp_low = low
    local tmp_oper2 = band(oper2, size_mask)
    local carry = (tmp_oper2 > band(high, size_mask)) and 0x01 or 0x00
    local result = high - oper2

    set_apzs(self, bits, high, oper2, result)
    set_of_sub(self, bits, high, oper2, result)
    write_flag(self, FLAG_C, carry ~= 0)

    if carry == 0x00 then
        call_interrupt(self, 0x00)
        return nil
    end

    for _ = 1, bits, 1 do
        local new_low = bor(lshift(tmp_low, 1), carry)
        carry = rshift(band(tmp_low, high_bit), bits - 1)
        tmp_low = new_low

        local new_high = bor(lshift(tmp_high, 1), carry)
        carry = rshift(band(tmp_high, high_bit), bits - 1)
        tmp_high = new_high

        if carry ~= 0 then
            carry = 0
            tmp_high = tmp_high - tmp_oper2
        else
            result = tmp_high - tmp_oper2

            set_apzs(self, bits, tmp_high, oper2, result)
            set_of_sub(self, bits, tmp_high, oper2, result)
            carry = (band(oper2, size_mask) > band(tmp_high, size_mask)) and 0x01 or 0x00

            if carry == 0 then
                tmp_high = result
            end
        end
    end

    tmp_low = bor(lshift(tmp_low, 1), carry)
    carry = band(tmp_low, high_bit)
    write_flag(self, FLAG_C, carry ~= 0)

    return {tmp_high, bnot(tmp_low)}
end

local function cpu_idiv(self, bits, high, low, oper2, negate)
    local high_bit = lshift(1, bits - 1)
    local size_mask = lshift(1, bits) - 1
    local a = high
    local b = low
    local c = oper2
    local negative = negate
    local dividend_negative = false

    if band(a, high_bit) ~= 0 then
        a = bnot(a)
        b = band(bnot(b) + 1, size_mask)

        if b == 0 then
            a = a + 1
        end

        a = band(a, size_mask)

        negative = not negative
        dividend_negative = true
    end

    if band(c, high_bit) ~= 0 then
        c = bnot(c) + 1
        negative = not negative
    end

    c = band(c, size_mask)

    local result = cpu_div(self, bits, a, b, c)

    if result then
        a = result[1]
        b = result[2]

        if band(b, high_bit) ~= 0 then
            call_interrupt(self, 0x00)
            return nil
        end

        if negative then
            b = bnot(b) + 1
        end

        if dividend_negative then
            a = bnot(a) + 1
        end

        clear_flag(self, FLAG_C)
        clear_flag(self, FLAG_O)

        return {a, b}
    end
end

local function rep_action(self)
    if self.rep_type == 0 then
        return false
    end

    if irq_pending(self) and self.repeating then
        self.ip = self.ip - 2
        self.completed = true
        self.repeating = false
        return true
    end

    if self.regs[REG_CX] == 0 then
        self.completed = true
        self.repeating = false
        return true
    end

    self.regs[REG_CX] = band(self.regs[REG_CX] - 1, 0xFFFF)
    self.completed = false
    return false
end

local function string_increment(self, opcode, val)
    local amount = lshift(1, band(opcode, 0x1))

    if band(self.flags, FLAG_D) ~= 0 then
        return band(val - amount, 0xFFFF)
    else
        return band(val + amount, 0xFFFF)
    end
end

local function cpu_loads(self, opcode)
    local base = lshift(self.segments[self.segment_mode or SEG_DS], 4)
    local offset = self.regs[REG_SI]

    self.regs[REG_SI] = string_increment(self, opcode, self.regs[REG_SI])

    if band(opcode, 0x01) == 0x01 then
        local low = self.memory:read8(base + offset)
        local high = self.memory:read8(base + band(offset + 1, 0xFFFF))

        return bor(low, lshift(high, 8))
    else
        return self.memory:read8(base + offset)
    end
end

local function cpu_stos(self, opcode, val)
    local base = lshift(self.segments[SEG_ES], 4)
    local offset = self.regs[REG_DI]

    if band(opcode, 0x01) == 0x01 then
        self.memory:write8(base + offset, band(val, 0xFF))
        self.memory:write8(base + band(offset + 1, 0xFFFF), rshift(val, 8))
    else
        self.memory:write8(base + offset, band(val, 0xFF))
    end

    self.regs[REG_DI] = string_increment(self, opcode, self.regs[REG_DI])
end

local alu_opcodes = {
    [0] = cpu_add,
    [1] = cpu_or,
    [2] = function(self, opcode, alu_opcode, oper1, oper2) -- ADC
        return cpu_add(self, opcode, alu_opcode, oper1, oper2 + band(self.flags, FLAG_C))
    end,
    [3] = function(self, opcode, alu_opcode, oper1, oper2) -- SBB
        return cpu_sub(self, opcode, alu_opcode, oper1, oper2 + band(self.flags, FLAG_C))
    end,
    [4] = cpu_test,
    [5] = cpu_sub,
    [6] = cpu_xor,
    [7] = cpu_sub -- CMP
}

local opcode_map = {}

-- NOP
opcode_map[0x90] = function(self, opcode) end

-- ALU r / m, r / m 
opcode_map[0x00] = function(self, opcode)
    do_mod_rm(self)
    local oper1 = read_rm(self, opcode)
    local oper2 = get_reg(self, opcode, self.reg)
    local alu_opcode = band(rshift(opcode, 3), 0x07)
    local result

    if band(opcode, 0x02) == 0 then
        result = alu_opcodes[alu_opcode](self, opcode, alu_opcode, oper1, oper2)
    else
        result = alu_opcodes[alu_opcode](self, opcode, alu_opcode, oper2, oper1)
    end

    if alu_opcode ~= 7 then
        if band(opcode, 0x02) == 0 then
            write_rm(self, opcode, result)
        else
            set_reg(self, opcode, self.reg, result)
        end
    end
end
opcode_map[0x01] = opcode_map[0x00]
opcode_map[0x02] = opcode_map[0x00]
opcode_map[0x03] = opcode_map[0x00]
opcode_map[0x08] = opcode_map[0x00]
opcode_map[0x09] = opcode_map[0x00]
opcode_map[0x0A] = opcode_map[0x00]
opcode_map[0x0B] = opcode_map[0x00]
opcode_map[0x10] = opcode_map[0x00]
opcode_map[0x11] = opcode_map[0x00]
opcode_map[0x12] = opcode_map[0x00]
opcode_map[0x13] = opcode_map[0x00]
opcode_map[0x18] = opcode_map[0x00]
opcode_map[0x19] = opcode_map[0x00]
opcode_map[0x1A] = opcode_map[0x00]
opcode_map[0x1B] = opcode_map[0x00]
opcode_map[0x20] = opcode_map[0x00]
opcode_map[0x21] = opcode_map[0x00]
opcode_map[0x22] = opcode_map[0x00]
opcode_map[0x23] = opcode_map[0x00]
opcode_map[0x28] = opcode_map[0x00]
opcode_map[0x29] = opcode_map[0x00]
opcode_map[0x2A] = opcode_map[0x00]
opcode_map[0x2B] = opcode_map[0x00]
opcode_map[0x30] = opcode_map[0x00]
opcode_map[0x31] = opcode_map[0x00]
opcode_map[0x32] = opcode_map[0x00]
opcode_map[0x33] = opcode_map[0x00]
opcode_map[0x38] = opcode_map[0x00]
opcode_map[0x39] = opcode_map[0x00]
opcode_map[0x3A] = opcode_map[0x00]
opcode_map[0x3B] = opcode_map[0x00]

-- ALU A, imm
opcode_map[0x04] = function(self, opcode)
    local oper1, oper2

    if band(opcode, 0x01) == 0x01 then
        oper1 = self.regs[REG_AX]
        oper2 = fetch_word(self)
    else
        oper1 = band(self.regs[REG_AX], 0xFF)
        oper2 = fetch_byte(self)
    end

    local alu_opcode = band(rshift(opcode, 0x03), 0x07)
    local result = alu_opcodes[alu_opcode](self, opcode, alu_opcode, oper1, oper2)

    if alu_opcode ~= 7 then
        if band(opcode, 0x01) == 0x01 then
            self.regs[REG_AX] = band(result, 0xFFFF)
        else
            self.regs[REG_AX] = bor(band(self.regs[REG_AX], 0xFF00), band(result, 0xFF))
        end
    end
end
opcode_map[0x05] = opcode_map[0x04]
opcode_map[0x0C] = opcode_map[0x04]
opcode_map[0x0D] = opcode_map[0x04]
opcode_map[0x14] = opcode_map[0x04]
opcode_map[0x15] = opcode_map[0x04]
opcode_map[0x1C] = opcode_map[0x04]
opcode_map[0x1D] = opcode_map[0x04]
opcode_map[0x24] = opcode_map[0x04]
opcode_map[0x25] = opcode_map[0x04]
opcode_map[0x2C] = opcode_map[0x04]
opcode_map[0x2D] = opcode_map[0x04]
opcode_map[0x34] = opcode_map[0x04]
opcode_map[0x35] = opcode_map[0x04]
opcode_map[0x3C] = opcode_map[0x04]
opcode_map[0x3D] = opcode_map[0x04]

-- PUSH seg
opcode_map[0x06] = function(self, opcode) cpu_push16(self, self.segments[SEG_ES]) end
opcode_map[0x0E] = function(self, opcode) cpu_push16(self, self.segments[SEG_CS]) end
opcode_map[0x16] = function(self, opcode) cpu_push16(self, self.segments[SEG_SS]) end
opcode_map[0x1E] = function(self, opcode) cpu_push16(self, self.segments[SEG_DS]) end

-- POP seg
opcode_map[0x07] = function(self, opcode)
    self.segments[SEG_ES] = cpu_pop16(self)
    self.no_int = true
end
opcode_map[0x0F] = function(self, opcode)
    self.segments[SEG_CS] = cpu_pop16(self)
    self.no_int = true
end
opcode_map[0x17] = function(self, opcode)
    self.segments[SEG_SS] = cpu_pop16(self)
    self.no_int = true
end
opcode_map[0x1F] = function(self, opcode)
    self.segments[SEG_DS] = cpu_pop16(self)
    self.no_int = true
end

-- ES:
opcode_map[0x26] = function(self, opcode)
    self.segment_mode = SEG_ES
    self.completed = false
end

-- CS:
opcode_map[0x2E] = function(self, opcode)
    self.segment_mode = SEG_CS
    self.completed = false
end

-- SS:
opcode_map[0x36] = function(self, opcode)
    self.segment_mode = SEG_SS
    self.completed = false
end

-- DS:
opcode_map[0x3E] = function(self, opcode)
    self.segment_mode = SEG_DS
    self.completed = false
end

-- DAA
opcode_map[0x27] = function(self, opcode)
    local al = band(self.regs[REG_AX], 0xFF)
    local af = band(self.flags, FLAG_A) ~= 0
    local temp_al = al

    clear_flag(self, FLAG_O)

    if af or (band(temp_al, 0x0F) > 9) then
        al = al + 0x06
        set_of_add(self, 8, temp_al, 6, al)
        set_flag(self, FLAG_A)
    end

    if (band(self.flags, FLAG_C) ~= 0) or (temp_al > (af and 0x9F or 0x99)) then
        al = al + 0x60
        set_of_add(self, 8, temp_al, 6, al)
        set_flag(self, FLAG_C)
    end

    set_pzs(self, 8, al)
    self.regs[REG_AX] = bor(band(self.regs[REG_AX], 0xFF00), band(al, 0xFF))
end

-- DAS
opcode_map[0x2F] = function(self, opcode)
    local al = band(self.regs[REG_AX], 0xFF)
    local af = band(self.flags, FLAG_A) ~= 0
    local temp_al = al

    clear_flag(self, FLAG_O)

    if af or (band(temp_al, 0x0F) > 9) then
        al = al - 0x06
        set_of_sub(self, 8, temp_al, 6, al)
        set_flag(self, FLAG_A)
    end

    if (band(self.flags, FLAG_C) ~= 0) or (temp_al > (af and 0x9F or 0x99)) then
        al = al - 0x60
        set_of_sub(self, 8, temp_al, 6, al)
        set_flag(self, FLAG_C)
    end

    set_pzs(self, 8, al)
    self.regs[REG_AX] = bor(band(self.regs[REG_AX], 0xFF00), band(al, 0xFF))
end

-- AAA
opcode_map[0x37] = function(self, opcode)
    local al = band(self.regs[REG_AX], 0xFF)
    local src

    if (band(self.flags, FLAG_A) ~= 0) or (band(al, 0x0F) > 9) then
        src = 0x06
        self.regs[REG_AX] = band(self.regs[REG_AX] + 0x100, 0xFFFF)
        self.flags = bor(self.flags, 0x11) -- AF, CF
    else
        src = 0x00
        self.flags = band(self.flags, bnot(0x11)) -- AF, CF
    end

    local result = al + src
    self.regs[REG_AX] = bor(band(self.regs[REG_AX], 0xFF00), band(result, 0x0F)) 

    set_of_add(self, 8, al, src, result)
    set_pzs(self, 8, result)
end

-- AAS
opcode_map[0x3F] = function(self, opcode)
    local al = band(self.regs[REG_AX], 0xFF)
    local oper2

    if (band(self.flags, FLAG_A) ~= 0) or (band(al, 0x0F) > 9) then
        oper2 = 0x06
        self.regs[REG_AX] = band(self.regs[REG_AX] - 0x100, 0xFFFF)
        self.flags = bor(self.flags, 0x11) -- AF, CF
    else
        oper2 = 0
        self.flags = band(self.flags, bnot(0x11)) -- AF, CF
    end

    local result = al - oper2

    set_of_sub(self, 8, al, oper2, result)
    set_pzs(self, 8, result)

    self.regs[REG_AX] = bor(band(self.regs[REG_AX], 0xFF00), band(result, 0x0F))
end

-- INC r16
opcode_map[0x40] = function(self, opcode)
    local reg = band(opcode, 0x07) + 1
    local val = self.regs[reg]
    local result = val + 1

    set_of_add(self, 16, val, 1, result)
    set_apzs(self, 16, val, 1, result)

    self.regs[reg] = band(result, 0xFFFF)
end
opcode_map[0x41] = opcode_map[0x40]
opcode_map[0x42] = opcode_map[0x40]
opcode_map[0x43] = opcode_map[0x40]
opcode_map[0x44] = opcode_map[0x40]
opcode_map[0x45] = opcode_map[0x40]
opcode_map[0x46] = opcode_map[0x40]
opcode_map[0x47] = opcode_map[0x40]

-- DEC r16
opcode_map[0x48] = function(self, opcode)
    local reg = band(opcode, 0x07) + 1
    local val = self.regs[reg]
    local result = val - 1

    set_of_sub(self, 16, val, 1, result)
    set_apzs(self, 16, val, 1, result)

    self.regs[reg] = band(result, 0xFFFF)
end
opcode_map[0x49] = opcode_map[0x48]
opcode_map[0x4A] = opcode_map[0x48]
opcode_map[0x4B] = opcode_map[0x48]
opcode_map[0x4C] = opcode_map[0x48]
opcode_map[0x4D] = opcode_map[0x48]
opcode_map[0x4E] = opcode_map[0x48]
opcode_map[0x4F] = opcode_map[0x48]

-- PUSH r16
opcode_map[0x50] = function(self, opcode) cpu_push16(self, self.regs[REG_AX]) end
opcode_map[0x51] = function(self, opcode) cpu_push16(self, self.regs[REG_CX]) end
opcode_map[0x52] = function(self, opcode) cpu_push16(self, self.regs[REG_DX]) end
opcode_map[0x53] = function(self, opcode) cpu_push16(self, self.regs[REG_BX]) end
opcode_map[0x54] = function(self, opcode) cpu_push16(self, self.regs[REG_SP] - 2) end
opcode_map[0x55] = function(self, opcode) cpu_push16(self, self.regs[REG_BP]) end
opcode_map[0x56] = function(self, opcode) cpu_push16(self, self.regs[REG_SI]) end
opcode_map[0x57] = function(self, opcode) cpu_push16(self, self.regs[REG_DI]) end

-- POP r16
opcode_map[0x58] = function(self, opcode) self.regs[REG_AX] = cpu_pop16(self) end
opcode_map[0x59] = function(self, opcode) self.regs[REG_CX] = cpu_pop16(self) end
opcode_map[0x5A] = function(self, opcode) self.regs[REG_DX] = cpu_pop16(self) end
opcode_map[0x5B] = function(self, opcode) self.regs[REG_BX] = cpu_pop16(self) end
opcode_map[0x5C] = function(self, opcode) self.regs[REG_SP] = cpu_pop16(self) end
opcode_map[0x5D] = function(self, opcode) self.regs[REG_BP] = cpu_pop16(self) end
opcode_map[0x5E] = function(self, opcode) self.regs[REG_SI] = cpu_pop16(self) end
opcode_map[0x5F] = function(self, opcode) self.regs[REG_DI] = cpu_pop16(self) end

-- JMP
for i = 0x60, 0x7F, 1 do
    local cond = jmp_conds[band(i, 0xF)]

    opcode_map[i] = function(self, opcode)
        local offset = fetch_byte(self)

        if cond(self) then
            self.ip = band(self.ip + to_sign_8(offset), 0xFFFF)
        end
    end
end

-- GRP1
opcode_map[0x80] = function(self, opcode)
    do_mod_rm(self)

    local oper1 = read_rm(self, opcode)
    local oper2

    if opcode == 0x81 then
        oper2 = fetch_word(self)
    elseif opcode == 0x83 then
        oper2 = to_sign_8(fetch_byte(self))
    else
        oper2 = fetch_byte(self)
    end

    local result = alu_opcodes[self.reg](self, opcode, self.reg, oper1, oper2)

    if self.reg ~= 7 then
        write_rm(self, opcode, result)
    end
end
opcode_map[0x81] = opcode_map[0x80]
opcode_map[0x82] = opcode_map[0x80]
opcode_map[0x83] = opcode_map[0x80]

-- TEST rm, reg
opcode_map[0x84] = function(self, opcode)
    do_mod_rm(self)
    local bits = lshift(8, band(opcode, 0x01))
    local result = band(read_rm(self, opcode), get_reg(self, opcode, self.reg))
    set_flags_bit(self, bits, result)
end
opcode_map[0x85] = opcode_map[0x84]

-- XCHG rm, reg
opcode_map[0x86] = function(self, opcode)
    do_mod_rm(self)
    local val = get_reg(self, opcode, self.reg)
    set_reg(self, opcode, self.reg, read_rm(self, opcode))
    write_rm(self, opcode, val)
end
opcode_map[0x87] = opcode_map[0x86]

-- MOV rm, reg
opcode_map[0x88] = function(self, opcode)
    do_mod_rm(self)
    write_rm(self, opcode, get_reg(self, opcode, self.reg))
end
opcode_map[0x89] = opcode_map[0x88]

-- MOV reg, rm
opcode_map[0x8A] = function(self, opcode)
    do_mod_rm(self)
    set_reg(self, opcode, self.reg, read_rm(self, opcode))
end
opcode_map[0x8B] = opcode_map[0x8A]

-- MOV rm, seg
opcode_map[0x8C] = function(self, opcode)
    do_mod_rm(self)
    write_rm_word(self, self.segments[band(self.reg, 3) + 1])
end

-- LEA
opcode_map[0x8D] = function(self, opcode)
    do_mod_rm(self)
    self.regs[self.reg + 1] = self.ea_addr
end

-- MOV seg, rm
opcode_map[0x8E] = function(self, opcode)
    do_mod_rm(self)
    self.segments[band(self.reg, 3) + 1] = read_rm_word(self)

    if self.reg == 2 then
        self.no_int = true
    end
end

-- POPW
opcode_map[0x8F] = function(self, opcode)
    do_mod_rm(self)
    write_rm_word(self, cpu_pop16(self))
end

-- XCHG A, reg
opcode_map[0x91] = function(self, opcode)
    local reg = band(opcode, 0x7) + 1
    local temp = self.regs[reg]
    self.regs[reg] = self.regs[REG_AX]
    self.regs[REG_AX] = temp
end
opcode_map[0x92] = opcode_map[0x91]
opcode_map[0x93] = opcode_map[0x91]
opcode_map[0x94] = opcode_map[0x91]
opcode_map[0x95] = opcode_map[0x91]
opcode_map[0x96] = opcode_map[0x91]
opcode_map[0x97] = opcode_map[0x91]

-- CBW
opcode_map[0x98] = function(self, opcode)
    local val = band(self.regs[REG_AX], 0xFF)

    if val >= 0x80 then
        val = bor(val, 0xFF00)
    end

    self.regs[REG_AX] = val
end

-- CWD
opcode_map[0x99] = function(self, opcode)
    if self.regs[REG_AX] >= 0x8000 then
        self.regs[REG_DX] = 0xFFFF
    else
        self.regs[REG_DX] = 0x0000
    end
end

-- CALL far
opcode_map[0x9A] = function(self, opcode)
    local new_ip = fetch_word(self)
    local new_cs = fetch_word(self)

    cpu_push16(self, self.segments[SEG_CS])
    cpu_push16(self, self.ip)

    self.ip = new_ip
    self.segments[SEG_CS] = new_cs
end

-- WAIT
opcode_map[0x9B] = function(self, opcode)
end

-- PUSHF
opcode_map[0x9C] = function(self, opcode)
    cpu_push16(self, bor(band(self.flags, 0x0FD7), 0xF000))
end

-- POPF
opcode_map[0x9D] = function(self, opcode)
    self.flags = bor(band(cpu_pop16(self), 0xFD5), 0xF002)
end

-- SAHF
opcode_map[0x9E] = function(self, opcode)
    self.flags = bor(band(self.flags, 0xFF02), rshift(band(self.regs[REG_AX], 0xD500), 8))
end

-- LAHF
opcode_map[0x9F] = function(self, opcode)
    self.regs[REG_AX] = bor(band(self.regs[REG_AX], 0xFF), lshift(band(self.flags, 0xD7), 8))
end

-- MOV AL, offset8
opcode_map[0xA0] = function(self, opcode)
    local addr = fetch_word(self)
    self.regs[REG_AX] = bor(band(self.regs[REG_AX], 0xFF00), self.memory:read8(lshift(self.segments[self.segment_mode or 4], 4) + addr))
end

-- MOV AX, offset16
opcode_map[0xA1] = function(self, opcode)
    local addr = fetch_word(self)
    self.regs[REG_AX] = self.memory:read16_l(lshift(self.segments[self.segment_mode or 4], 4) + addr)
end

-- MOV offset8, AL
opcode_map[0xA2] = function(self, opcode)
    local addr = fetch_word(self)
    self.memory:write8(lshift(self.segments[self.segment_mode or 4], 4) + addr, band(self.regs[REG_AX], 0xFF))
end

-- MOV offset16, AL
opcode_map[0xA3] = function(self, opcode)
    local addr = fetch_word(self)
    self.memory:write16_l(lshift(self.segments[self.segment_mode or 4], 4) + addr, self.regs[REG_AX])
end

-- MOVSB/MOVSW
opcode_map[0xA4] = function(self, opcode)
    if not rep_action(self) then
        cpu_stos(self, opcode, cpu_loads(self, opcode))

        if self.rep_type ~= 0 then
            self.repeating = true
        end
    end
end
opcode_map[0xA5] = opcode_map[0xA4]

-- CMPSB/CMPSW
opcode_map[0xA6] = function(self, opcode)
    if not rep_action(self) then
        local oper1 = cpu_loads(self, opcode)
        local oper2 = read_memory(self, opcode, lshift(self.segments[SEG_ES], 4), self.regs[REG_DI])

        self.regs[REG_DI] = string_increment(self, opcode, self.regs[REG_DI])

        cpu_sub(self, opcode, 0, oper1, oper2)

        if self.rep_type ~= 0 then
            if (band(self.flags, FLAG_Z) ~= 0) == (self.rep_type == 1) then
                self.completed = true
            else
                self.repeating = true
            end
        end
    end
end
opcode_map[0xA7] = opcode_map[0xA6]

-- TEST AL, imm8
opcode_map[0xA8] = function(self, opcode)
    set_flags_bit(self, 8, band(band(self.regs[REG_AX], 0xFF), fetch_byte(self)))
end
-- TEST AX, imm16
opcode_map[0xA9] = function(self, opcode)
    set_flags_bit(self, 16, band(self.regs[REG_AX], fetch_word(self)))
end

-- STOSB/STOSW
opcode_map[0xAA] = function(self, opcode)
    if not rep_action(self) then
        cpu_stos(self, opcode, self.regs[REG_AX])

        if self.rep_type ~= 0 then
            self.repeating = true
        end
    end
end
opcode_map[0xAB] = opcode_map[0xAA]

-- LODSB/LODSW
opcode_map[0xAC] = function(self, opcode)
    if not rep_action(self) then
        local val = cpu_loads(self, opcode)

        if band(opcode, 0x01) == 0x01 then
            self.regs[REG_AX] = val
        else
            self.regs[REG_AX] = bor(band(self.regs[REG_AX], 0xFF00), band(val, 0xFF))
        end

        if self.rep_type ~= 0 then
            self.repeating = true
        end
    end
end
opcode_map[0xAD] = opcode_map[0xAC]

-- SCASB/SCASW
opcode_map[0xAE] = function(self, opcode)
    if not rep_action(self) then
        local oper1
        local oper2 = read_memory(self, opcode, lshift(self.segments[SEG_ES], 4), self.regs[REG_DI])

        if band(opcode, 0x01) == 0x01 then
            oper1 = self.regs[REG_AX]
        else
            oper1 = band(self.regs[REG_AX], 0xFF)
        end

        self.regs[REG_DI] = string_increment(self, opcode, self.regs[REG_DI])

        cpu_sub(self, opcode, 0, oper1, oper2)

        if self.rep_type ~= 0 then
            if (band(self.flags, FLAG_Z) ~= 0) == (self.rep_type == 1) then
                self.completed = true
                return
            end

            self.repeating = true
        end
    end
end
opcode_map[0xAF] = opcode_map[0xAE]

-- MOV reg, imm8
opcode_map[0xB0] = function(self, opcode) self.regs[REG_AX] = bor(band(self.regs[REG_AX], 0xFF00), fetch_byte(self)) end
opcode_map[0xB1] = function(self, opcode) self.regs[REG_CX] = bor(band(self.regs[REG_CX], 0xFF00), fetch_byte(self)) end
opcode_map[0xB2] = function(self, opcode) self.regs[REG_DX] = bor(band(self.regs[REG_DX], 0xFF00), fetch_byte(self)) end
opcode_map[0xB3] = function(self, opcode) self.regs[REG_BX] = bor(band(self.regs[REG_BX], 0xFF00), fetch_byte(self)) end
opcode_map[0xB4] = function(self, opcode) self.regs[REG_AX] = bor(band(self.regs[REG_AX], 0xFF), lshift(fetch_byte(self), 8)) end
opcode_map[0xB5] = function(self, opcode) self.regs[REG_CX] = bor(band(self.regs[REG_CX], 0xFF), lshift(fetch_byte(self), 8)) end
opcode_map[0xB6] = function(self, opcode) self.regs[REG_DX] = bor(band(self.regs[REG_DX], 0xFF), lshift(fetch_byte(self), 8)) end
opcode_map[0xB7] = function(self, opcode) self.regs[REG_BX] = bor(band(self.regs[REG_BX], 0xFF), lshift(fetch_byte(self), 8)) end

-- MOV reg, imm16
opcode_map[0xB8] = function(self, opcode) self.regs[REG_AX] = fetch_word(self) end
opcode_map[0xB9] = function(self, opcode) self.regs[REG_CX] = fetch_word(self) end
opcode_map[0xBA] = function(self, opcode) self.regs[REG_DX] = fetch_word(self) end
opcode_map[0xBB] = function(self, opcode) self.regs[REG_BX] = fetch_word(self) end
opcode_map[0xBC] = function(self, opcode) self.regs[REG_SP] = fetch_word(self) end
opcode_map[0xBD] = function(self, opcode) self.regs[REG_BP] = fetch_word(self) end
opcode_map[0xBE] = function(self, opcode) self.regs[REG_SI] = fetch_word(self) end
opcode_map[0xBF] = function(self, opcode) self.regs[REG_DI] = fetch_word(self) end

-- RET
opcode_map[0xC0] = function(self, opcode)
    local disp = fetch_word(self)
    self.ip = cpu_pop16(self)
    self.regs[REG_SP] = band(self.regs[REG_SP] + disp, 0xFFFF)
end
opcode_map[0xC2] = opcode_map[0xC0]

-- RET
opcode_map[0xC1] = function(self, opcode)
    self.ip = cpu_pop16(self)
end
opcode_map[0xC3] = opcode_map[0xC1]

-- LES/LDS
opcode_map[0xC4] = function(self, opcode)
    do_mod_rm(self)

    self.regs[self.reg + 1] = memory_read16(self, self.ea_seg, self.ea_addr)
    local val = memory_read16(self, self.ea_seg, band(self.ea_addr + 2, 0xFFFF))

    if opcode == 0xC5 then
        self.segments[SEG_DS] = val
    else
        self.segments[SEG_ES] = val
    end
end
opcode_map[0xC5] = opcode_map[0xC4]

-- MOV rm, imm
opcode_map[0xC6] = function(self, opcode)
    do_mod_rm(self)
    write_rm(self, opcode, fetch(self, band(opcode, 0x1) ~= 0))
end
opcode_map[0xC7] = opcode_map[0xC6]

-- RET far + pop
opcode_map[0xCA] = function(self, opcode)
    local imm16 = fetch_word(self)

    self.ip = cpu_pop16(self)
    self.segments[SEG_CS] = cpu_pop16(self)
    self.regs[REG_SP] = band(self.regs[REG_SP] + imm16, 0xFFFF)
end
opcode_map[0xC8] = opcode_map[0xCA]

-- RET far
opcode_map[0xCB] = function(self, opcode)
    self.ip = cpu_pop16(self)
    self.segments[SEG_CS] = cpu_pop16(self)
end
opcode_map[0xC9] = opcode_map[0xCB]

-- INT 3
opcode_map[0xCC] = function(self, opcode)
    call_interrupt(self, 0x03)
end

-- INT imm
opcode_map[0xCD] = function(self, opcode)
    call_interrupt(self, fetch_byte(self))
end

-- INTO
opcode_map[0xCE] = function(self, opcode)
    if band(self.flags, 0x800) ~= 0 then
        call_interrupt(self, 0x04)
    end
end

-- IRET
opcode_map[0xCF] = function(self, opcode)
    self.ip = cpu_pop16(self)
    self.segments[SEG_CS] = cpu_pop16(self)
    self.flags =  bor(band(cpu_pop16(self), 0xFD5), 0xF002)
    self.no_int = true
    self.nmi_enable = true
end

local grp2_table = {
    [0] = cpu_rol,
    [1] = cpu_ror,
    [2] = cpu_rcl,
    [3] = cpu_rcr,
    [4] = cpu_shl,
    [5] = cpu_shr,
    [6] = cpu_setmo,
    [7] = cpu_sar
}

-- GRP2
opcode_map[0xD0] = function(self, opcode)
    do_mod_rm(self)
    local bits = lshift(8, band(opcode, 0x01))
    local result = read_rm(self, opcode)

    if band(opcode, 0x2) == 0x2 then
        local count = band(self.regs[REG_CX], 0xFF)

        while count ~= 0 do
            result = grp2_table[self.reg](self, bits, result)
            count = count - 1
        end
    else
        result = grp2_table[self.reg](self, bits, result)
    end

    write_rm(self, opcode, result)
end
opcode_map[0xD1] = opcode_map[0xD0]
opcode_map[0xD2] = opcode_map[0xD0]
opcode_map[0xD3] = opcode_map[0xD0]

-- AAM
opcode_map[0xD4] = function(self, opcode)
    local val = fetch_byte(self)

    if val == 0 then
        set_pzs(self, 8, 0)
        clear_flag(self, FLAG_C)
        clear_flag(self, FLAG_A)
        clear_flag(self, FLAG_O)
        call_interrupt(self, 0x00)
        return
    end

    local al = band(self.regs[REG_AX], 0xFF)
    local new_ah = math.floor(al / val)
    local new_al = al % val

    set_pzs(self, 8, new_al)
    clear_flag(self, FLAG_C)
    clear_flag(self, FLAG_A)
    clear_flag(self, FLAG_O)

    self.regs[REG_AX] = bor(lshift(band(new_ah, 0xFF), 8), band(new_al, 0xFF))
end

-- AAD
opcode_map[0xD5] = function(self, opcode)
    local val = fetch_byte(self)
    local al = band(self.regs[REG_AX], 0xFF)
    local ah = band(rshift(self.regs[REG_AX], 8), 0xFF)
    local result = band(cpu_add(self, 0, 0, ah * val, al), 0xFF)

    self.regs[REG_AX] = result
    set_pzs(self, 8, result)
end

-- SALC
opcode_map[0xD6] = function(self, opcode)
    if band(self.flags, 0x01) ~= 0 then
        self.regs[REG_AX] = bor(self.regs[REG_AX], 0xFF)
    else
        self.regs[REG_AX] = band(self.regs[REG_AX], 0xFF00)
    end
end

-- XLAT
opcode_map[0xD7] = function(self, opcode)
    local addr = band(self.regs[REG_BX] + band(self.regs[REG_AX], 0xFF), 0xFFFF)
    self.regs[REG_AX] = bor(band(self.regs[REG_AX], 0xFF00), self.memory:read8(lshift(self.segments[self.segment_mode or 4], 4) + addr))
end

-- 8087 FPU
opcode_map[0xD8] = function(self, opcode)
    do_mod_rm(self)
end
opcode_map[0xD9] = opcode_map[0xD8]
opcode_map[0xDA] = opcode_map[0xD8]
opcode_map[0xDB] = opcode_map[0xD8]
opcode_map[0xDC] = opcode_map[0xD8]
opcode_map[0xDD] = opcode_map[0xD8]
opcode_map[0xDE] = opcode_map[0xD8]
opcode_map[0xDF] = opcode_map[0xD8]

-- LOOPNZ r8
opcode_map[0xE0] = function(self, opcode)
    local offset = to_sign_8(fetch_byte(self))
    self.regs[REG_CX] = band(self.regs[REG_CX] - 1, 0xFFFF)

    if (self.regs[REG_CX] ~= 0) and (band(self.flags, 0x40) == 0) then
        self.ip = band(self.ip + offset, 0xFFFF)
    end
end

-- LOOPZ r8
opcode_map[0xE1] = function(self, opcode)
    local offset = to_sign_8(fetch_byte(self))
    self.regs[REG_CX] = band(self.regs[REG_CX] - 1, 0xFFFF)

    if (self.regs[REG_CX] ~= 0) and (band(self.flags, 0x40) ~= 0) then
        self.ip = band(self.ip + offset, 0xFFFF)
    end
end

-- LOOP r8
opcode_map[0xE2] = function(self, opcode)
    local offset = to_sign_8(fetch_byte(self))
    self.regs[REG_CX] = band(self.regs[REG_CX] - 1, 0xFFFF)

    if self.regs[REG_CX] ~= 0 then
        self.ip = band(self.ip + offset, 0xFFFF)
    end
end

-- JCXZ r8
opcode_map[0xE3] = function(self, opcode)
    local offset = to_sign_8(fetch_byte(self))

    if self.regs[REG_CX] == 0 then
        self.ip = band(self.ip + offset, 0xFFFF)
    end
end

-- IN AL, Ib
opcode_map[0xE4] = function(self, opcode)
    self.regs[REG_AX] = bor(band(self.regs[REG_AX], 0xFF00), cpu_in(self, false, fetch_byte(self)))
end

-- IN AX, Ib
opcode_map[0xE5] = function(self, opcode)
    self.regs[REG_AX] = cpu_in(self, true, fetch_byte(self))
end

-- OUT AL, Ib
opcode_map[0xE6] = function(self, opcode)
    cpu_out(self, false, fetch_byte(self), band(self.regs[REG_AX], 0xFF))
end

-- OUT AX, Ib
opcode_map[0xE7] = function(self, opcode)
    cpu_out(self, true, fetch_byte(self), self.regs[REG_AX])
end

-- CALL rel16
opcode_map[0xE8] = function(self, opcode)
    local offset = to_sign_16(fetch_word(self))
    cpu_push16(self, self.ip)
    self.ip = band(self.ip + offset, 0xFFFF)
end

-- JMP rel16
opcode_map[0xE9] = function(self, opcode)
    local offset = to_sign_16(fetch_word(self))
    self.ip = band(self.ip + offset, 0xFFFF)
end

-- JMP ptr
opcode_map[0xEA] = function(self, opcode)
    local new_ip = fetch_word(self)
    local new_cs = fetch_word(self)
    self.ip = new_ip
    self.segments[SEG_CS] = new_cs
end

-- JMP rel8
opcode_map[0xEB] = function(self, opcode)
    local offset = to_sign_8(fetch_byte(self))
    self.ip = band(self.ip + offset, 0xFFFF)
end

-- IN AL, DX
opcode_map[0xEC] = function(self, opcode)
    self.regs[REG_AX] = bor(band(self.regs[REG_AX], 0xFF00), cpu_in(self, false, self.regs[REG_DX]))
end

-- IN AX, DX
opcode_map[0xED] = function(self, opcode)
    self.regs[REG_AX] = cpu_in(self, true, self.regs[REG_DX])
end

-- OUT AL, DX
opcode_map[0xEE] = function(self, opcode)
    cpu_out(self, false, self.regs[REG_DX], band(self.regs[REG_AX], 0xFF))
end

-- OUT AX, DX
opcode_map[0xEF] = function(self, opcode)
    cpu_out(self, true, self.regs[REG_DX], self.regs[REG_AX])
end

-- LOCK
opcode_map[0xF0] = function(self, opcode)
end
opcode_map[0xF1] = opcode_map[0xF0]

-- REPNZ
opcode_map[0xF2] = function(self, opcode)
    self.rep_type = 1
    self.completed = false
end

-- REPZ
opcode_map[0xF3] = function(self, opcode)
    self.rep_type = 2
    self.completed = false
end

-- HLT
opcode_map[0xF4] = function(self, opcode)
    if irq_pending(self) then
        check_interrupts(self)
    else
        self.repeating = true
        self.completed = false
    end
end

-- CMC
opcode_map[0xF5] = function(self, opcode)
    self.flags = bxor(self.flags, FLAG_C)
end

-- GRP3
local grp3_table = {
    [0] = function(self, opcode, val) -- TEST
        local bits = lshift(8, band(opcode, 0x01))
        local result = band(val, fetch(self, band(opcode, 0x01) == 0x01))
        set_flags_bit(self, bits, result)
    end,
    [1] = function(self, opcode, val) -- TEST
        local bits = lshift(8, band(opcode, 0x01))
        local result = band(val, fetch(self, band(opcode, 0x01) == 0x01))
        set_flags_bit(self, bits, result)
    end,
    [2] = function(self, opcode, val) -- NOT
        write_rm(self, opcode, bnot(val))
    end,
    [3] = function(self, opcode, val) -- NEG
        local result = cpu_sub(self, opcode, 0, 0, val)
        write_rm(self, opcode, result)
    end,
    [4] = function(self, opcode, val) -- MUL
        local bits = lshift(8, band(opcode, 0x01))

        if bits == 8 then
            local result = cpu_mul(self, bits, band(self.regs[REG_AX], 0xFF), val)

            self.regs[REG_AX] = band(result, 0xFFFF)

            set_pzs(self, bits, rshift(self.regs[REG_AX], 8))
        else
            local result = cpu_mul(self, bits, self.regs[REG_AX], val)

            self.regs[REG_AX] = band(result, 0xFFFF)
            self.regs[REG_DX] = band(rshift(result, 16), 0xFFFF)

            set_pzs(self, bits, self.regs[REG_DX])
        end

        clear_flag(self, FLAG_A)
    end,
    [5] = function(self, opcode, val) -- IMUL
        local bits = lshift(8, band(opcode, 0x01))

        if bits == 8 then
            local result = cpu_imul(self, bits, band(self.regs[REG_AX], 0xFF), val)

            self.regs[REG_AX] = band(result, 0xFFFF)
        else
            local result = cpu_imul(self, bits, self.regs[REG_AX], val)

            self.regs[REG_AX] = band(result, 0xFFFF)
            self.regs[REG_DX] = band(rshift(result, 16), 0xFFFF)
        end
    end,
    [6] = function(self, opcode, val)
        local bits = lshift(8, band(opcode, 0x01))

        if bits == 16 then
            local result = cpu_div(self, bits, self.regs[REG_DX], self.regs[REG_AX], val)

            if result then
                self.regs[REG_DX] = band(result[1], 0xFFFF)
                self.regs[REG_AX] = band(result[2], 0xFFFF)
            end
        else
            local oper1 = self.regs[REG_AX]
            local result = cpu_div(self, bits, rshift(oper1, 8), band(oper1, 0xFF), val)

            if result then
                self.regs[REG_AX] = bor(band(result[2], 0xFF), lshift(band(result[1], 0xFF), 8))
            end
        end
    end,
    [7] = function(self, opcode, val)
        local bits = lshift(8, band(opcode, 0x01))
        local negate = self.rep_type ~= 0

        if bits == 16 then
            local result = cpu_idiv(self, bits, self.regs[REG_DX], self.regs[REG_AX], val, negate)

            if result then
                self.regs[REG_DX] = band(result[1], 0xFFFF)
                self.regs[REG_AX] = band(result[2], 0xFFFF)
            end
        else
            local oper1 = self.regs[REG_AX]
            local result = cpu_idiv(self, bits, rshift(oper1, 8), band(oper1, 0xFF), val, negate)

            if result then
                self.regs[REG_AX] = bor(band(result[2], 0xFF), lshift(band(result[1], 0xFF), 8))
            end
        end
    end
}

opcode_map[0xF6] = function(self, opcode)
    do_mod_rm(self)
    grp3_table[self.reg](self, opcode, read_rm(self, opcode))
end
opcode_map[0xF7] = opcode_map[0xF6]

opcode_map[0xF8] = function(self, opcode) self.flags = band(self.flags, bnot(FLAG_C)) end
opcode_map[0xF9] = function(self, opcode) self.flags = bor(self.flags, FLAG_C) end

opcode_map[0xFA] = function(self, opcode) self.flags = band(self.flags, bnot(FLAG_I)) end
opcode_map[0xFB] = function(self, opcode) self.flags = bor(self.flags, FLAG_I) end

opcode_map[0xFC] = function(self, opcode) self.flags = band(self.flags, bnot(FLAG_D)) end
opcode_map[0xFD] = function(self, opcode) self.flags = bor(self.flags, FLAG_D) end

local grp4_grp5_table = {
    [0] = function(self, opcode) -- INC rm
        local bits = lshift(8, band(opcode, 0x01))
        local val = read_rm(self, opcode)
        local result = val + 1

        set_of_add(self, bits, val, 1, result)
        set_apzs(self, bits, val, 1, result)
        write_rm(self, opcode, result)
    end,
    [1] = function(self, opcode) -- DEC rm
        local bits = lshift(8, band(opcode, 0x01))
        local val = read_rm(self, opcode)
        local result = val - 1

        set_of_sub(self, bits, val, 1, result)
        set_apzs(self, bits, val, 1, result)
        write_rm(self, opcode, result)
    end,
    [2] = function(self, opcode) -- CALL near abs
        local new_ip = read_rm(self, opcode)
        cpu_push16(self, self.ip)
        self.ip = new_ip
    end,
    [3] = function(self, opcode) -- CALL abs near
        local new_ip = read_memory(self, opcode, self.ea_seg, self.ea_addr)
        local new_cs = read_memory(self, opcode, self.ea_seg, self.ea_addr + 2)

        cpu_push16(self, self.segments[SEG_CS])
        cpu_push16(self, self.ip)

        self.ip = new_ip
        self.segments[SEG_CS] = new_cs
    end,
    [4] = function(self, opcode) -- JMP near abs
        self.ip = read_rm(self, opcode)
    end,
    [5] = function(self, opcode) -- JMP far
        self.ip = read_memory(self, opcode, self.ea_seg, self.ea_addr)
        self.segments[SEG_CS] = read_memory(self, opcode, self.ea_seg, self.ea_addr + 2)
    end,
    [6] = function(self, opcode) -- PUSH rm
        if (band(opcode, 0x01) == 0x01) and (self.mode == 3) and (self.rm == 4) then -- SP
            cpu_push16(self, self.regs[REG_SP] - 2)
        else
            cpu_push16(self, read_rm(self, opcode))
        end
    end,
    [7] = function(self, opcode) -- PUSH rm
        if (band(opcode, 0x01) == 0x01) and (self.mode == 3) and (self.rm == 4) then -- SP
            cpu_push16(self, self.regs[REG_SP] - 2)
        else
            cpu_push16(self, read_rm(self, opcode))
        end
    end
}

-- GRP4 / GRP5
opcode_map[0xFE] = function(self, opcode)
    do_mod_rm(self)
    grp4_grp5_table[self.reg](self, opcode)
end
opcode_map[0xFF] = opcode_map[0xFE]

local function step(self)
    if not self.repeating then
        self.opcode = fetch_byte(self)
    end

    local instruction = opcode_map[self.opcode]

    self.completed = true

    if instruction then
        instruction(self, self.opcode)
    else
        logger:error("i8086: Illegal opcode: 0x%02X", self.opcode)
    end

    if self.completed then
        self.repeating = false
        self.segment_mode = nil
        self.rep_type = 0
        check_interrupts(self)
        self.no_int = false
    end
end

local function set_reset_vector(self, cs, ip)
    self.reset_cs = band(cs, 0xFFFF)
    self.reset_ip = band(ip, 0xFFFF)
end

local function get_io(self)
    return self.io
end

local function reset(self)
    for i = 1, 8, 1 do
        self.regs[i] = 0
    end

    self.segments[1] = 0x0000
    self.segments[2] = self.reset_cs
    self.segments[3] = 0x0000
    self.segments[4] = 0x0000
    self.ip = self.reset_ip
    self.flags = 0
    self.segment_mode = nil
    self.rep_type = 0
    self.no_int = false
    self.completed = false
    self.repeating = false
    self.nmi_mask = false
    self.nmi_enable = false
    self.nmi = false
end

function cpu.new(memory)
    local self = {
        memory = memory,
        pic = {},
        regs = {0, 0, 0, 0, 0, 0, 0, 0}, -- AX, CX, DX, BX, SP, BP, SI, DI
        segments = {0, 0, 0, 0}, -- ES, CS, SS, DS
        flags = 0,
        ip = 0,
        ea_addr = 0,
        ea_seg = 0,
        mode = 0,
        rm = 0,
        reg = 0,
        opcode = 0,
        rep_type = 0,
        reset_ip = 0,
        reset_cs = 0,
        segment_mode = nil,
        no_int = false,
        completed = false,
        repeating = false,
        nmi = false,
        nmi_mask = false,
        nmi_enable = false,
        set_reset_vector = set_reset_vector,
        set_flag = set_flag,
        clear_flag = clear_flag,
        write_flag = write_flag,
        call_interrupt = call_interrupt,
        step = step,
        reset = reset,
        get_io = get_io
    }

    self.io = io_ports.new(self)
    self.io:set_port_out(0xA0, function(_, _, val)
        self.nmi_mask = band(val, 0x80) ~= 0
    end)

    return self
end

return cpu
