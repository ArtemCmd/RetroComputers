local logger = require("retro_computers:logger")
local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

local parity_table = {
    [0] = 4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4, 0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0,
    0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0, 4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4,
    0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0, 4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4,
    4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4, 0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0,
    0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0, 4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4,
    4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4, 0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0,
    4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4, 0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0,
    0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0, 4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4
}

local rm_seg_table = {
    [0] = 4,
    [1] = 4,
    [2] = 3,
    [3] = 3,
    [4] = 4,
    [5] = 4,
    [6] = 3,
    [7] = 4
}

local jmp_conds = {
    [0] = function(self) return band(self.flags, 0x0800) ~= 0 end, -- OF
    function(self) return band(self.flags, 0x0800) == 0 end, -- OF
    function(self) return band(self.flags, 0x0001) ~= 0 end, -- CF
    function(self) return band(self.flags, 0x0001) == 0 end, -- CF
    function(self) return band(self.flags, 0x0040) ~= 0 end, -- ZF
    function(self) return band(self.flags, 0x0040) == 0 end, -- ZF
    function(self) return (band(self.flags, 0x0001) ~= 0) or (band(self.flags, 0x0040) ~= 0) end, -- CF / ZF
    function(self) return (band(self.flags, 0x0001) == 0) and (band(self.flags, 0x0040) == 0) end, --  CF / ZF
    function(self) return band(self.flags, 0x0080) ~= 0 end, -- SF
    function(self) return band(self.flags, 0x0080) == 0 end, -- SF
    function(self) return band(self.flags, 0x0004) ~= 0 end, -- PF
    function(self) return band(self.flags, 0x0004) == 0 end, -- PF
    function(self) return (band(self.flags, 0x0800) ~= 0) ~= (band(self.flags, 0x0080) ~= 0) end, -- OF / SF
    function(self) return (band(self.flags, 0x0800) ~= 0) == (band(self.flags, 0x0080) ~= 0) end, -- OF / SF
    function(self) return (band(self.flags, 0x0040) ~= 0) or ((band(self.flags, 0x0080) ~= 0) ~= (band(self.flags, 0x0800) ~= 0)) end, -- ZF or (SF != OF)
    function(self) return (band(self.flags, 0x0040) == 0) and ((band(self.flags, 0x0080) ~= 0) == (band(self.flags, 0x0800) ~= 0)) end -- ZF and (SF == OF)
}

local function to_sign_8(value)
    if value >= 0x80 then
        return value - 0x100
    else
        return value
    end
end

local function to_sign_16(value)
    if value >= 0x8000 then
        return value - 0x10000
    else
        return value
    end
end

local function to_sign_32(value)
    if value >= 0x80000000 then
        return value - 0x100000000
    else
        return value
    end
end

local function clear_flag(self, index)
    self.flags = band(self.flags, bnot(lshift(1, index)))
end

local function set_flag(self, index)
    self.flags = bor(self.flags, lshift(1, index))
end

local function write_flag(self, num, val)
    if val then
        set_flag(self, num)
    else
        clear_flag(self, num)
    end
end

local function set_of_add(self, opcode, oper1, oper2, result)
    if band(opcode, 0x01) == 0x01 then
        write_flag(self, 11, band(band(bxor(result, oper2), bxor(result, oper1)), 0x8000) ~= 0)
    else
        write_flag(self, 11, band(band(bxor(result, oper2), bxor(result, oper1)), 0x80) ~= 0)
    end
end

local function set_of_sub(self, opcode, oper1, oper2, result)
    if band(opcode, 0x01) == 0x01 then
        write_flag(self, 11, band(band(bxor(oper1, oper2), bxor(result, oper1)), 0x8000) ~= 0)
    else
        write_flag(self, 11, band(band(bxor(oper1, oper2), bxor(result, oper1)), 0x80) ~= 0)
    end
end

local function set_of_rot(self, opcode, val, result)
    if band(opcode, 0x01) == 0x01 then
        write_flag(self, 11, band(bxor(result, val), 0x8000) ~= 0)
    else
        write_flag(self, 11, band(bxor(result, val), 0x80) ~= 0)
    end
end

local function set_pzs(self, opcode, result)
    if band(opcode, 0x01) == 0x01 then
        write_flag(self, 6, band(result, 0xFFFF) == 0) -- ZF
        write_flag(self, 7, band(result, 0x8000) ~= 0) -- SF
    else
        write_flag(self, 6, band(result, 0xFF) == 0) -- ZF
        write_flag(self, 7, band(result, 0x80) ~= 0) -- SF
    end

    self.flags = bor(band(self.flags, 0xFFFB), parity_table[band(result, 0xFF)]) -- PF
end

local function set_apzs(self, opcode, oper1, oper2, result)
    set_pzs(self, opcode, result)
    write_flag(self, 4, band(bxor(bxor(result, oper2), oper1), 0x10) ~= 0)
end

local function set_flags_bit(self, opcode, result)
    self.flags = band(self.flags, bnot(0x0811))
    set_pzs(self, opcode, result)
end

local function fetch_byte(self)
    local ip = lshift(self.segments[2], 4) + self.ip
    self.ip = band(self.ip + 1, 0xFFFF)
    return self.memory[ip]
end

local function fetch_word(self)
    local ip = lshift(self.segments[2], 4) + self.ip
    self.ip = band(self.ip + 2, 0xFFFF)
    return self.memory:r16(ip)
end

local function fetch(self, word)
    if word then
        return fetch_word(self)
    else
        return fetch_byte(self)
    end
end

local function cpu_set_ip(self, cs, ip)
    self.segments[2] = band(cs, 0xFFFF)
    self.ip = band(ip, 0xFFFF)
end

local function get_reg_byte(self, reg)
    local reg_index = band(reg, 0x03) + 1

    if reg > 3 then
        return rshift(self.regs[reg_index], 8)
    else
        return band(self.regs[reg_index], 0xFF)
    end
end

local function get_reg(self, opcode, reg)
    if band(opcode, 0x1) == 0x1 then
        return self.regs[reg + 1]
    else
        return get_reg_byte(self, reg)
    end
end

local function set_reg_byte(self, reg, val)
    local reg_index = band(reg, 0x03) + 1

    if reg > 3 then
        self.regs[reg_index] = bor(band(self.regs[reg_index], 0xFF), lshift(band(val, 0xFF), 8))
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

local mod_rm = {
    [0] = function(self) return self.regs[4] + self.regs[7] end, -- BX + SI
    [1] = function(self) return self.regs[4] + self.regs[8] end, -- BX + DI
    [2] = function(self) return self.regs[6] + self.regs[7] end, -- BP + SI
    [3] = function(self) return self.regs[6] + self.regs[8] end, -- BP + DI
    [4] = function(self) return self.regs[7] end, -- SI
    [5] = function(self) return self.regs[8] end, -- DIв
    [6] = function(self) return self.regs[6] end, -- BP
    [7] = function(self) return self.regs[4] end  -- BX
}

local function do_mod_rm(self)
    local rm_data = fetch_byte(self)
    self.reg = band(rshift(rm_data, 0x03), 0x07)
    self.mode = band(rshift(rm_data, 0x06), 0x03)
    self.rm = band(rm_data, 0x07)

    if self.mode == 3 then
        return
    end

    if band(rm_data, 0xC7) == 0x06 then -- 0 mode, 6 R/M
        self.ea_addr = fetch_word(self)
        self.ea_seg = lshift(self.segments[self.segment_mode or 4], 4)
    else
        local temp_ea = mod_rm[self.rm](self)

        if self.mode == 1 then -- 1 mode
            temp_ea = temp_ea + to_sign_8(fetch_byte(self))
        elseif self.mode == 2 then -- 2 mode
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

    return self.memory[self.ea_seg + self.ea_addr]
end

local function read_rm_word(self)
    if self.mode == 3 then
        return self.regs[self.rm + 1]
    end

    return self.memory:r16(self.ea_seg + self.ea_addr)
end

local function write_rm_byte(self, val)
    if self.mode == 3 then
        set_reg_byte(self, self.rm, band(val, 0xFF))
    else
        self.memory[self.ea_seg + self.ea_addr] = band(val, 0xFF)
    end
end

local function write_rm_word(self, val)
    if self.mode == 3 then
        self.regs[self.rm + 1] = band(val, 0xFFFF)
    else
        self.memory:w16(self.ea_seg + self.ea_addr, band(val, 0xFFFF))
    end
end

local function read_rm(self, opcode)
    if band(opcode, 0x1) == 0x1 then
        return read_rm_word(self)
    else
        return read_rm_byte(self)
    end
end

local function write_rm(self, opcode, val)
    if band(opcode, 0x1) == 0x1 then
        write_rm_word(self, val)
    else
        write_rm_byte(self, val)
    end
end

local function cpu_push16(self, val)
    self.regs[5] = band(self.regs[5] - 2, 0xFFFF)
    self.memory:w16(lshift(self.segments[3], 4) + self.regs[5], band(val, 0xFFFF))
end

local function cpu_pop16(self)
    local sp = self.regs[5]
    self.regs[5] = band(self.regs[5] + 2, 0xFFFF)
    return self.memory:r16(lshift(self.segments[3], 4) + sp)
end

local function cpu_in(self, port)
    local handler = self.io_ports[port]

    if handler ~= nil then
        return handler(self, port, nil)
    else
        -- logger.warning("i8086: IN: port 0x%02X not found", port)
        return 0xFF
    end
end

local function cpu_out(self, port, val)
    local handler = self.io_ports[port]

    if handler ~= nil then
        handler(self, port, val)
    -- else
    --     logger.warning("i8086: OUT: port 0x%02X not found", port)
    end
end

local function call_interrupt_fake(self, id)
    local ax = self.regs[1]
    local ah = rshift(ax, 8)
    local al = band(ax, 0xFF)

    local handler = self.interrupt_handlers[id]

    if handler then
        local result = handler(self, ax, ah, al)

        if result then
            return result
        end
    end

    logger.warning("i8086: Unknown interrupt: %02Xh, AX = 0x%04X", id, ax)
end

local function call_interrupt(self, id)
    local addr = lshift(id, 2)

    cpu_push16(self, band(self.flags, 0x0FD7))
    cpu_push16(self, self.segments[2])
    cpu_push16(self, self.ip)

    self.ip = self.memory:r16(addr)
    self.segments[2] = self.memory:r16(addr + 2)

    self.flags = band(self.flags, bnot(0x0300)) -- IF, TF
end

local function irq_pending(self)
    return ((band(self.flags, 0x0100) ~= 0) or ((band(self.flags, 0x0200) ~= 0) and self.pic.int_pending))and (not self.no_int)
end

local function check_interrupts(self)
    if (band(self.flags, 0x0100) ~= 0) and (not self.no_int) then
        call_interrupt(self, 1)
        return
    end

    if (band(self.flags, 0x0200) ~= 0) and self.pic.int_pending and (not self.no_int) then
        self.repeating = false
        self.completed = true
        self.segment_mode = nil
        self.pic:irq_ack()
        local interrupt = self.pic:irq_ack()
        self.opcode = 0x00
        call_interrupt(self, interrupt)
    end
end

local function cpu_add(self, opcode, alu_opcode, oper1, oper2)
    local result = oper1 + oper2
    local size_mask = lshift(1, lshift(8, band(opcode, 0x01))) - 1
    local carry = 0

    if (alu_opcode == 2) and (band(self.flags, 0x01) == 0x01) then
        carry = 1
    end

    set_of_add(self, opcode, oper1, oper2 - carry, result)
    set_apzs(self, opcode, oper1, oper2 - carry, result)
    write_flag(self, 0, (band(oper2, size_mask) > band(result, size_mask)) or ((alu_opcode == 2) and (band(oper2, size_mask) == 0) and (band(self.flags, 0x01) ~= 0))) -- CF

    return result
end

local function cpu_or(self, opcode, alu_opcode, oper1, oper2)
    local result = bor(oper1, oper2)
    set_flags_bit(self, opcode, result)
    return result
end

local function cpu_test(self, opcode, alu_opcode, oper1, oper2)
    local result = band(oper1, oper2)
    set_flags_bit(self, opcode, result)
    return result
end

local function cpu_xor(self, opcode, alu_opcode, oper1, oper2)
    local result = bxor(oper1, oper2)
    set_flags_bit(self, opcode, result)
    return result
end

local function cpu_sub(self, opcode, alu_opcode, oper1, oper2)
    local result = oper1 - oper2
    local size_mask = lshift(1, lshift(8, band(opcode, 0x01))) - 1
    local carry = 0

    if (alu_opcode == 3) and (band(self.flags, 0x01) ~= 0) then
        carry = 1
    end

    set_apzs(self, opcode, oper1, oper2 - carry, result)
    set_of_sub(self, opcode, oper1, oper2 - carry, result)
    write_flag(self, 0, (band(oper2, size_mask) > band(oper1, size_mask)) or ((alu_opcode == 3) and (band(oper2, size_mask) == 0) and (band(self.flags, 0x01) ~= 0))) -- CF

    return result
end

local function cpu_rotate(self, opcode, oper1, mode)
    if mode == 0 then -- ROL
        if band(opcode, 0x01) == 0x01 then
            write_flag(self, 0, band(oper1, 0x8000) ~= 0) -- CF
        else
            write_flag(self, 0, band(oper1, 0x80) ~= 0) -- CF
        end

        local result = bor(lshift(oper1, 1), band(self.flags, 0x01))

        set_of_rot(self, opcode, oper1, result)
        return result
    elseif mode == 1 then -- ROR
        write_flag(self, 0, band(oper1, 0x01) ~= 0) -- CF

        local result = rshift(oper1, 1)

        if band(self.flags, 0x01) == 0x01 then
            if band(opcode, 0x01) == 0x01 then
                result = bor(result, 0x8000)
            else
                result = bor(result, 0x80)
            end
        end

        set_of_rot(self, opcode, oper1, result)
        return result
    elseif mode == 2 then -- RCL
        local result = bor(lshift(oper1, 1), band(self.flags, 0x01))

        if band(opcode, 0x01) == 0x01 then
            write_flag(self, 0, band(oper1, 0x8000) ~= 0) -- CF
        else
            write_flag(self, 0, band(oper1, 0x80) ~= 0) -- CF
        end

        set_of_rot(self, opcode, oper1, result)
        return result
    elseif mode == 3 then -- RCR
        local result = rshift(oper1, 1)

        if band(self.flags, 0x01) == 0x01 then
            if band(opcode, 0x01) == 0x01 then
                result = bor(result, 0x8000)
            else
                result = bor(result, 0x80)
            end
        end

        set_of_rot(self, opcode, oper1, result)
        write_flag(self, 0, band(oper1, 0x01) ~= 0) -- CF
        return result
    end
end

local function cpu_shl(self, opcode, val)
    local result = lshift(val, 1)

    if band(opcode, 0x01) == 0x01 then
        write_flag(self, 0, band(val, 0x8000) ~= 0) -- CF
    else
        write_flag(self, 0, band(val, 0x80) ~= 0) -- CF
    end

    set_of_rot(self, opcode, val, result)
    write_flag(self, 4, band(result, 0x10) ~= 0) -- AF
    set_pzs(self, opcode, result)

    return result
end

local function cpu_shr(self, opcode, val)
    local result = rshift(val, 1)

    write_flag(self, 0, band(val, 0x01) ~= 0) -- CF
    set_of_rot(self, opcode, val, result)
    clear_flag(self, 4) -- AF
    set_pzs(self, opcode, result)

    return result
end

local function cpu_setmo(self, opcode, val)
    clear_flag(self, 0) -- CF
    clear_flag(self, 4) -- AF
    clear_flag(self, 11) -- OF
    set_pzs(self, opcode, 0xFFFF)
    return 0xFFFF
end

local function cpu_sar(self, opcode, val)
    local result = rshift(val, 1)

    if band(opcode, 0x01) == 0x01 then
        result = bor(result, band(val, 0x8000))
    else
        result = bor(result, band(val, 0x80))
    end

    set_of_rot(self, opcode, val, result)
    write_flag(self, 0, band(val, 0x1) ~= 0) -- CF
    clear_flag(self, 4) -- AF
    set_pzs(self, opcode, result)

    return result
end

local function cpu_mul(self, opcode, oper1, oper2)
    local result = oper1 * oper2
    local high = 0

    if band(opcode, 0x01) == 1 then
        result = band(result, 0xFFFFFFFF)
        self.regs[1] = band(result, 0xFFFF) -- AX
        self.regs[3] = rshift(result, 16) -- DX
        high = rshift(result, 16)
    else
        result = band(result, 0xFFFF)
        self.regs[1] = result -- AX
        high = rshift(result, 8)
    end

    write_flag(self, 0, high ~= 0) -- CF
    write_flag(self, 11, high ~= 0) -- OF
end

local function cpu_imul(self, opcode, oper1, oper2)
    if band(opcode, 0x01) == 1 then
        local result = to_sign_16(oper1) * to_sign_16(oper2)
        self.regs[3] = band(rshift(result, 16), 0xFFFF)
        self.regs[1] = band(result, 0xFFFF)

        write_flag(self, 0, (result < -0x8000) or (result >= 0x8000)) -- CF
        write_flag(self, 11, (result < -0x8000) or (result >= 0x8000)) -- OF
    else
        local result = to_sign_8(oper1) * to_sign_8(oper2)
        self.regs[1] = band(result, 0xFFFF)

        write_flag(self, 0, (result < -0x80) or (result >= 0x80)) -- CF
        write_flag(self, 11, (result < -0x80) or (result >= 0x80)) -- OF
    end
end

local function cpu_div(self, opcode, oper2)
    local high = self.regs[3]
    local low = self.regs[1]
    local bits = 8
    local hbit = 0x80
    local mask = 0xFF
    local carry = true

    if band(opcode, 0x01) == 0x01 then
        hbit = 0x8000
        bits = 16
        mask = 0xFFFF
    else
        high = rshift(self.regs[1], 8)
        low = band(self.regs[1], 0xFF)
    end

    local new_oper2 = band(oper2, mask)

    if high >= new_oper2 then
        call_interrupt(self, 0x00)
    end

    for _ = 1, bits, 1 do
        local new_low = lshift(low, 1)

        if carry then
            new_low = new_low + 1
        end

        carry = band(low, hbit) ~= 0
        low = new_low

        local new_high = lshift(high, 1)

        if carry then
            new_high = new_high + 1
        end

        carry = band(high, hbit) ~= 0
        high = new_high

        if carry then
            carry = false
            high = high - new_oper2
        else
            carry = new_oper2 > high

            if not carry then
                high = high - new_oper2
            end
        end
    end

    low = lshift(low, 1)

    if carry then
        low = low + 1
    end

    low = bnot(low)

    if band(opcode, 0x01) == 0x01 then
        self.regs[3] = band(high, 0xFFFF)
        self.regs[1] = band(low, 0xFFFF)
    else
        self.regs[1] = bor(lshift(band(high, 0xFF), 8), band(low, 0xFF))
    end
end

local function cpu_idiv(self, opcode, val2)
    if band(opcode, 0x01) == 0x01 then
        local val1 = to_sign_32(bor(lshift(self.regs[3], 16), self.regs[1]))
        val2 = to_sign_16(val2)

        if val2 == 0 then
            call_interrupt(self, 0)
            return
        end

        local vall = val1 / val2

        if vall >= 0 then
            vall = math.floor(vall)
        else
            vall = math.ceil(vall)
        end

        local valh = math.fmod(val1, val2)

        if (vall >= 0x8000) or (vall < -0x8000) then
            call_interrupt(self, 0)
            return
        end

        self.regs[3] = band(valh, 0xFFFF)
        self.regs[1] = band(vall, 0xFFFF)
    else
        local val1 = to_sign_16(self.regs[1])

        val2 = to_sign_8(val2)

        if val2 == 0 then
            call_interrupt(self, 0)
            return
        end

        local vall = math.floor(val1 / val2)

        if vall >= 0 then
            vall = math.floor(vall)
        else
            vall = math.ceil(vall)
        end

        local valh = math.fmod(val1, val2)

        if (vall >= 0x80) or (vall < -0x80) then
            call_interrupt(self, 0)
            return
        end

        self.regs[1] = bor(lshift(band(valh, 0xFF), 8), band(vall, 0xFF))
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

    if self.regs[2] == 0 then
        self.completed = true
        self.repeating = false
        return true
    end

    self.regs[2] = band(self.regs[2] - 1, 0xFFFF)
    self.completed = false
    return false
end

local function string_increment(self, opcode, val)
    local amount = lshift(1, band(opcode, 0x1))

    if band(self.flags, 0x400) ~= 0 then
        return band(val - amount, 0xFFFF)
    else
        return band(val + amount, 0xFFFF)
    end
end

local function cpu_loads(self, opcode)
    local old_si = self.regs[7]

    self.regs[7] = string_increment(self, opcode, self.regs[7])

    if band(opcode, 0x01) == 0x01 then
        return self.memory:r16(lshift(self.segments[self.segment_mode or 4], 4) + old_si)
    else
        return self.memory[lshift(self.segments[self.segment_mode or 4], 4) + old_si]
    end
end

local function cpu_stos(self, opcode, val)
    if band(opcode, 0x01) == 0x01 then
        self.memory:w16(lshift(self.segments[1], 4) + self.regs[8], band(val, 0xFFFF))
    else
        self.memory[lshift(self.segments[1], 4) + self.regs[8]] = band(val, 0xFF)
    end

    self.regs[8] = string_increment(self, opcode, self.regs[8])
end

local function read_memory(self, opcode, addr)
    if band(opcode, 0x01) == 0x01 then
        return self.memory:r16(addr)
    else
        return self.memory[addr]
    end
end

local alu_opcodes = {
    [0] = cpu_add,
    [1] = cpu_or,
    [2] = function(self, opcode, alu_opcode, oper1, oper2) -- ADC
        return cpu_add(self, opcode, alu_opcode, oper1, oper2 + band(self.flags, 0x01))
    end,
    [3] = function(self, opcode, alu_opcode, oper1, oper2) -- SBB
        return cpu_sub(self, opcode, alu_opcode, oper1, oper2 + band(self.flags, 0x01))
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
    local alu_opcode = band(rshift(opcode, 0x03), 0x07)
    local result = 0

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
    local oper1, oper2 = 0, 0

    if band(opcode, 0x01) == 0x01 then
        oper1 = self.regs[1]
        oper2 = fetch_word(self)
    else
        oper1 = band(self.regs[1], 0xFF)
        oper2 = fetch_byte(self)
    end

    local alu_opcode = band(rshift(opcode, 0x03), 0x07)
    local result = alu_opcodes[alu_opcode](self, opcode, alu_opcode, oper1, oper2)

    if alu_opcode ~= 7 then
        if band(opcode, 0x01) == 0x01 then
            self.regs[1] = band(result, 0xFFFF)
        else
            self.regs[1] = bor(band(self.regs[1], 0xFF00), band(result, 0xFF))
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
opcode_map[0x06] = function(self, opcode) cpu_push16(self, self.segments[1]) end -- ES
opcode_map[0x0E] = function(self, opcode) cpu_push16(self, self.segments[2]) end -- CS
opcode_map[0x16] = function(self, opcode) cpu_push16(self, self.segments[3]) end -- SS
opcode_map[0x1E] = function(self, opcode) cpu_push16(self, self.segments[4]) end -- DS

-- POP seg
opcode_map[0x07] = function(self, opcode) -- ES
    self.segments[1] = cpu_pop16(self)
    self.no_int = true
end
opcode_map[0x0F] = function(self, opcode) -- CS
    self.segments[2] = cpu_pop16(self)
    self.no_int = true
end
opcode_map[0x17] = function(self, opcode) -- SS
    self.segments[3] = cpu_pop16(self)
    self.no_int = true
end
opcode_map[0x1F] = function(self, opcode) -- DS
    self.segments[4] = cpu_pop16(self)
    self.no_int = true
end

-- ES:
opcode_map[0x26] = function(self, opcode)
    self.segment_mode = 1
    self.completed = false
end

-- CS:
opcode_map[0x2E] = function(self, opcode)
    self.segment_mode = 2
    self.completed = false
end

-- SS:
opcode_map[0x36] = function(self, opcode)
    self.segment_mode = 3
    self.completed = false
end

-- DS:
opcode_map[0x3E] = function(self, opcode)
    self.segment_mode = 4
    self.completed = false
end

-- DAA
opcode_map[0x27] = function(self, opcode)
    local al = band(self.regs[1], 0xFF)
    local old_al = al
    local old_af = band(self.flags, 0x10) == 0x10

    clear_flag(self, 11) -- OF

    if (band(self.flags, 0x10) == 0x10) or (band(old_al, 0x0F) > 9) then
        al = al + 6
        set_of_add(self, 0, old_al, 6, al)
        set_flag(self, 4) -- AF
    end

    if (band(self.flags, 0x01) == 0x01) or ((old_af and (al > 0x9F)) or (al > 0x99)) then
        al = al + 0x60
        set_of_add(self, 0, old_al, 6, al)
        set_flag(self, 0) -- CF
    end

    self.regs[1] = bor(band(self.regs[1], 0xFF00), band(al, 0xFF))
    set_pzs(self, 0, al)
end

-- DAS
opcode_map[0x2F] = function(self, opcode)
    local al = band(self.regs[1], 0xFF)
    local old_al = al
    local old_af = band(self.flags, 0x10) == 0x10

    clear_flag(self, 11) -- OF

    if (band(self.flags, 0x10) == 0x10) or (band(old_al, 0x0F) > 9) then
        al = al - 6
        set_of_sub(self, 0, old_al, 6, al)
        set_flag(self, 4) -- AF
    end

    if (band(self.flags, 0x01) == 0x01) or ((old_af and (al > 0x9F)) or (al > 0x99)) then
        al = al - 0x60
        set_of_sub(self, 0, old_al, 6, al)
        set_flag(self, 0) -- CF
    end

    self.regs[1] = bor(band(self.regs[1], 0xFF00), band(al, 0xFF))
    set_pzs(self, 0, al)
end

-- AAA
opcode_map[0x37] = function(self, opcode)
    local al = band(self.regs[1], 0xFF)

    if (band(self.flags, 0x10) == 0x10) or (band(al, 0xF) >= 9) then
        self.regs[1] = band(self.regs[1] + 0x106, 0xFFFF)
        self.flags = bor(self.flags, 0x11) -- AF, CF
        set_of_add(self, 0, al, 6, band(self.regs[1], 0xFF))
    else
        self.flags = band(self.flags, bnot(0x11)) -- AF, CF
        set_of_add(self, 0, al, 0, al)
    end

    self.regs[1] = band(self.regs[1], 0xFF0F)
end

-- AAS
opcode_map[0x3F] = function(self, opcode)
    local al = band(self.regs[1], 0xFF)

    if (band(self.flags, 0x10) == 0x10) or (band(al, 0xF) >= 9) then
        self.regs[1] = band(self.regs[1] - 0x106, 0xFFFF)
        self.flags = bor(self.flags, 0x11) -- AF, CF
        set_of_sub(self, 0, al, 6, band(self.regs[1], 0xFF))
    else
        self.flags = band(self.flags, bnot(0x11)) -- AF, CF
        set_of_sub(self, 0, al, 0, al)
    end

    self.regs[1] = band(self.regs[1], 0xFF0F)
end

-- INC r16
opcode_map[0x40] = function(self, opcode)
    local reg = band(opcode, 0x07) + 1
    local val = self.regs[reg]
    local result = val + 1

    set_of_add(self, 1, val, 1, result)
    set_apzs(self, 1, val, 1, result)

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

    set_of_sub(self, 1, val, 1, result)
    set_apzs(self, 1, val, 1, result)

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
opcode_map[0x50] = function(self, opcode) cpu_push16(self, self.regs[1]) end
opcode_map[0x51] = function(self, opcode) cpu_push16(self, self.regs[2]) end
opcode_map[0x52] = function(self, opcode) cpu_push16(self, self.regs[3]) end
opcode_map[0x53] = function(self, opcode) cpu_push16(self, self.regs[4]) end
opcode_map[0x54] = function(self, opcode) cpu_push16(self, self.regs[5]) end
opcode_map[0x55] = function(self, opcode) cpu_push16(self, self.regs[6]) end
opcode_map[0x56] = function(self, opcode) cpu_push16(self, self.regs[7]) end
opcode_map[0x57] = function(self, opcode) cpu_push16(self, self.regs[8]) end

-- POP r16
opcode_map[0x58] = function(self, opcode) self.regs[1] = cpu_pop16(self) end
opcode_map[0x59] = function(self, opcode) self.regs[2] = cpu_pop16(self) end
opcode_map[0x5A] = function(self, opcode) self.regs[3] = cpu_pop16(self) end
opcode_map[0x5B] = function(self, opcode) self.regs[4] = cpu_pop16(self) end
opcode_map[0x5C] = function(self, opcode) self.regs[5] = cpu_pop16(self) end
opcode_map[0x5D] = function(self, opcode) self.regs[6] = cpu_pop16(self) end
opcode_map[0x5E] = function(self, opcode) self.regs[7] = cpu_pop16(self) end
opcode_map[0x5F] = function(self, opcode) self.regs[8] = cpu_pop16(self) end

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
    local oper2 = 0

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
    local result = band(read_rm(self, opcode), get_reg(self, opcode, self.reg))
    set_flags_bit(self, opcode, result)
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
    self.regs[reg] = self.regs[1]
    self.regs[1] = temp
end
opcode_map[0x92] = opcode_map[0x91]
opcode_map[0x93] = opcode_map[0x91]
opcode_map[0x94] = opcode_map[0x91]
opcode_map[0x95] = opcode_map[0x91]
opcode_map[0x96] = opcode_map[0x91]
opcode_map[0x97] = opcode_map[0x91]

-- CBW
opcode_map[0x98] = function(self, opcode)
    local val = band(self.regs[1], 0xFF)

    if val >= 0x80 then
        val = bor(val, 0xFF00)
    end

    self.regs[1] = val
end

-- CWD
opcode_map[0x99] = function(self, opcode)
    if self.regs[1] >= 0x8000 then
        self.regs[3] = 0xFFFF
    else
        self.regs[3] = 0x0000
    end
end

-- CALL far
opcode_map[0x9A] = function(self, opcode)
    local new_ip = fetch_word(self)
    local new_cs = fetch_word(self)

    cpu_push16(self, self.segments[2])
    cpu_push16(self, self.ip)

    self.ip = new_ip
    self.segments[2] = new_cs
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
    self.flags = bor(cpu_pop16(self), 0x0002)
end

-- SAHF
opcode_map[0x9E] = function(self, opcode)
    self.flags = bor(band(self.flags, 0xFF02), rshift(band(self.regs[1], 0xFF00), 8))
end

-- LAHF
opcode_map[0x9F] = function(self, opcode)
    self.regs[1] = bor(band(self.regs[1], 0xFF), lshift(band(self.flags, 0xD7), 8))
end

-- MOV AL, offset8
opcode_map[0xA0] = function(self, opcode)
    local addr = fetch_word(self)
    self.regs[1] = bor(band(self.regs[1], 0xFF00), self.memory[lshift(self.segments[self.segment_mode or 4], 4) + addr])
end

-- MOV AX, offset16
opcode_map[0xA1] = function(self, opcode)
    local addr = fetch_word(self)
    self.regs[1] = self.memory:r16(lshift(self.segments[self.segment_mode or 4], 4) + addr)
end

-- MOV offset8, AL
opcode_map[0xA2] = function(self, opcode)
    local addr = fetch_word(self)
    self.memory[lshift(self.segments[self.segment_mode or 4], 4) + addr] = band(self.regs[1], 0xFF)
end

-- MOV offset16, AL
opcode_map[0xA3] = function(self, opcode)
    local addr = fetch_word(self)
    self.memory:w16(lshift(self.segments[self.segment_mode or 4], 4) + addr, self.regs[1])
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
        local oper2 = read_memory(self, opcode, lshift(self.segments[1], 4) + self.regs[8])

        self.regs[8] = string_increment(self, opcode, self.regs[8])

        cpu_sub(self, opcode, 0, oper1, oper2)

        if self.rep_type ~= 0 then
            if (band(self.flags, 0x40) ~= 0) == (self.rep_type == 1) then
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
    set_flags_bit(self, 0, band(band(self.regs[1], 0xFF), fetch_byte(self)))
end
-- TEST AX, imm16
opcode_map[0xA9] = function(self, opcode)
    set_flags_bit(self, 1, band(self.regs[1], fetch_word(self)))
end

-- STOSB/STOSW
opcode_map[0xAA] = function(self, opcode)
    if not rep_action(self) then
        cpu_stos(self, opcode, self.regs[1])

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

        if band(opcode, 0x1) == 0x1 then
            self.regs[1] = val
        else
            self.regs[1] = bor(band(self.regs[1], 0xFF00), band(val, 0xFF))
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
        local oper1 = 0
        local oper2 = read_memory(self, opcode, lshift(self.segments[1], 4) + self.regs[8])

        if band(opcode, 0x01) == 0x01 then
            oper1 = self.regs[1]
        else
            oper1 = band(self.regs[1], 0xFF)
        end

        self.regs[8] = string_increment(self, opcode, self.regs[8])

        cpu_sub(self, opcode, 0, oper1, oper2)

        if self.rep_type ~= 0 then
            if (band(self.flags, 0x40) ~= 0) == (self.rep_type == 1) then
                self.completed = true
                return
            end

            self.repeating = true
        end
    end
end
opcode_map[0xAF] = opcode_map[0xAE]

-- MOV reg, imm8
opcode_map[0xB0] = function(self, opcode) self.regs[1] = bor(band(self.regs[1], 0xFF00), fetch_byte(self)) end
opcode_map[0xB1] = function(self, opcode) self.regs[2] = bor(band(self.regs[2], 0xFF00), fetch_byte(self)) end
opcode_map[0xB2] = function(self, opcode) self.regs[3] = bor(band(self.regs[3], 0xFF00), fetch_byte(self)) end
opcode_map[0xB3] = function(self, opcode) self.regs[4] = bor(band(self.regs[4], 0xFF00), fetch_byte(self)) end
opcode_map[0xB4] = function(self, opcode) self.regs[1] = bor(band(self.regs[1], 0xFF), lshift(fetch_byte(self), 8)) end
opcode_map[0xB5] = function(self, opcode) self.regs[2] = bor(band(self.regs[2], 0xFF), lshift(fetch_byte(self), 8)) end
opcode_map[0xB6] = function(self, opcode) self.regs[3] = bor(band(self.regs[3], 0xFF), lshift(fetch_byte(self), 8)) end
opcode_map[0xB7] = function(self, opcode) self.regs[4] = bor(band(self.regs[4], 0xFF), lshift(fetch_byte(self), 8)) end

-- MOV reg, imm16
opcode_map[0xB8] = function(self, opcode) self.regs[1] = fetch_word(self) end
opcode_map[0xB9] = function(self, opcode) self.regs[2] = fetch_word(self) end
opcode_map[0xBA] = function(self, opcode) self.regs[3] = fetch_word(self) end
opcode_map[0xBB] = function(self, opcode) self.regs[4] = fetch_word(self) end
opcode_map[0xBC] = function(self, opcode) self.regs[5] = fetch_word(self) end
opcode_map[0xBD] = function(self, opcode) self.regs[6] = fetch_word(self) end
opcode_map[0xBE] = function(self, opcode) self.regs[7] = fetch_word(self) end
opcode_map[0xBF] = function(self, opcode) self.regs[8] = fetch_word(self) end

-- RET
opcode_map[0xC0] = function(self, opcode)
    local btp = fetch_word(self)
    self.ip = cpu_pop16(self)
    self.regs[5] = self.regs[5] + btp
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
    local addr = self.ea_seg + self.ea_addr
    self.regs[self.reg + 1] = self.memory:r16(addr)
    local val = self.memory:r16(addr + 2)

    if opcode == 0xC5 then
        self.segments[4] = val
    else
        self.segments[1] = val
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
    local btp = fetch_word(self)
    self.ip = cpu_pop16(self)
    self.segments[2] = cpu_pop16(self)
    self.regs[5] = self.regs[5] + btp
end
opcode_map[0xC8] = opcode_map[0xCA]

-- RET far
opcode_map[0xCB] = function(self, opcode)
    self.ip = cpu_pop16(self)
    self.segments[2] = cpu_pop16(self)
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
    self.segments[2] = cpu_pop16(self)
    self.flags = bor(cpu_pop16(self), 0x2)
    self.no_int = true
    self.nmi_enable = true
end

local grp2_table = {
    [0] = function(self, opcode, val) return cpu_rotate(self, opcode, val, 0) end, -- ROL
    [1] = function(self, opcode, val) return cpu_rotate(self, opcode, val, 1) end, -- ROR
    [2] = function(self, opcode, val) return cpu_rotate(self, opcode, val, 2) end, -- RCL
    [3] = function(self, opcode, val) return cpu_rotate(self, opcode, val, 3) end, -- RCR
    [4] = function(self, opcode, val) return cpu_shl(self, opcode, val) end, -- SHL
    [5] = function(self, opcode, val) return cpu_shr(self, opcode, val) end, -- SHR
    [6] = function(self, opcode, val) return cpu_setmo(self, opcode, val) end, -- SETMO
    [7] = function(self, opcode, val) return cpu_sar(self, opcode, val) end -- SAR
}

-- GRP2
opcode_map[0xD0] = function(self, opcode)
    do_mod_rm(self)
    local result = read_rm(self, opcode)

    if band(opcode, 0x2) == 0x2 then
        local count = band(self.regs[2], 0xFF) -- CL

        while count ~= 0 do
            result = grp2_table[self.reg](self, opcode, result)
            count = count - 1
        end
    else
        result = grp2_table[self.reg](self, opcode, result)
    end

    write_rm(self, opcode, result)
end
opcode_map[0xD1] = opcode_map[0xD0]
opcode_map[0xD2] = opcode_map[0xD0]
opcode_map[0xD3] = opcode_map[0xD0]

-- AAM
opcode_map[0xD4] = function(self, opcode)
    local val = fetch_byte(self)
    local al = band(self.regs[1], 0xFF)

    if val == 0 then -- Divide by zero
        return
    end

    local new_ah = math.floor(al / val)
    local new_al = al % val
    self.regs[1] = bor(lshift(band(new_ah, 0xFF), 8), band(new_al, 0xFF))
    set_pzs(self, 0, new_al)
end

-- AAD
opcode_map[0xD5] = function(self, opcode)
    local val = fetch_byte(self)
    local al = band(self.regs[1], 0xFF)
    local ah = band(rshift(self.regs[1], 8), 0xFF)
    local result = band(ah * val + al, 0xFF)

    self.regs[1] = result
    set_pzs(self, 0, result)
end

-- SALC
opcode_map[0xD6] = function(self, opcode)
    if band(self.flags, 0x01) ~= 0 then
        self.regs[1] = bor(self.regs[1], 0xFF)
    else
        self.regs[1] = band(self.regs[1], 0xFF00)
    end
end

-- XLAT
opcode_map[0xD7] = function(self, opcode)
    local addr = band(self.regs[4] + band(self.regs[1], 0xFF), 0xFFFF)
    self.regs[1] = bor(band(self.regs[1], 0xFF00), self.memory[lshift(self.segments[self.segment_mode or 4], 4) + addr])
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
    self.regs[2] = band(self.regs[2] - 1, 0xFFFF)

    if (self.regs[2] ~= 0) and (band(self.flags, 0x40) == 0) then
        self.ip = band(self.ip + offset, 0xFFFF)
    end
end

-- LOOPZ r8
opcode_map[0xE1] = function(self, opcode)
    local offset = to_sign_8(fetch_byte(self))
    self.regs[2] = band(self.regs[2] - 1, 0xFFFF)

    if (self.regs[2] ~= 0) and (band(self.flags, 0x40) ~= 0) then
        self.ip = band(self.ip + offset, 0xFFFF)
    end
end

-- LOOP r8
opcode_map[0xE2] = function(self, opcode)
    local offset = to_sign_8(fetch_byte(self))
    self.regs[2] = band(self.regs[2] - 1, 0xFFFF)

    if self.regs[2] ~= 0 then
        self.ip = band(self.ip + offset, 0xFFFF)
    end
end

-- JCXZ r8
opcode_map[0xE3] = function(self, opcode)
    local offset = to_sign_8(fetch_byte(self))

    if self.regs[2] == 0 then
        self.ip = band(self.ip + offset, 0xFFFF)
    end
end

-- IN AL, Ib
opcode_map[0xE4] = function(self, opcode)
    self.regs[1] = bor(band(self.regs[1], 0xFF00), band(cpu_in(self, fetch_byte(self)), 0xFF))
end

-- IN AX, Ib
opcode_map[0xE5] = function(self, opcode)
    self.regs[1] = band(cpu_in(self, fetch_byte(self)), 0xFFFF)
end

-- OUT AL, Ib
opcode_map[0xE6] = function(self, opcode)
    cpu_out(self, fetch_byte(self), band(self.regs[1], 0xFF))
end

-- OUT AX, Ib
opcode_map[0xE7] = function(self, opcode)
    cpu_out(self, fetch_byte(self), self.regs[1])
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
    self.segments[2] = new_cs
end

-- JMP rel8
opcode_map[0xEB] = function(self, opcode)
    local offset = to_sign_8(fetch_byte(self))
    self.ip = band(self.ip + offset, 0xFFFF)
end

-- IN AL, DX
opcode_map[0xEC] = function(self, opcode)
    self.regs[1] = bor(band(self.regs[1], 0xFF00), band(cpu_in(self, self.regs[3]), 0xFF))
end

-- IN AX, DX
opcode_map[0xED] = function(self, opcode)
    self.regs[1] = band(cpu_in(self, self.regs[3]), 0xFFFF)
end

-- OUT AL, DX
opcode_map[0xEE] = function(self, opcode)
    cpu_out(self, self.regs[3], band(self.regs[1], 0xFF))
end

-- OUT AX, DX
opcode_map[0xEF] = function(self, opcode)
    cpu_out(self, self.regs[3], self.regs[1])
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
    self.flags = bxor(self.flags, 0x1)
end

-- GRP3
local grp3_table = {
    [0] = function(self, opcode, val) -- TEST
        local result = band(val, fetch(self, band(opcode, 0x01) == 0x01))
        set_flags_bit(self, opcode, result)
    end,
    [1] = function(self, opcode, val) -- TEST
        local result = band(val, fetch(self, band(opcode, 0x01) == 0x01))
        set_flags_bit(self, opcode, result)
    end,
    [2] = function(self, opcode, val) -- NOT
        write_rm(self, opcode, bnot(val))
    end,
    [3] = function(self, opcode, val) -- NEG
        local result = cpu_sub(self, opcode, 0, 0, val)
        write_rm(self, opcode, result)
    end,
    [4] = function(self, opcode, val) -- MUL
        if band(opcode, 0x01) == 0x01 then
            cpu_mul(self, opcode, self.regs[1], val)
        else
            cpu_mul(self, opcode, band(self.regs[1], 0xFF), val)
        end
    end,
    [5] = function(self, opcode, val) -- IMUL
        if band(opcode, 0x01) == 0x01 then
            cpu_imul(self, opcode, self.regs[1], val)
        else
            cpu_imul(self, opcode, band(self.regs[1], 0xFF), val)
        end
    end,
    [6] = function(self, opcode, val)
        cpu_div(self, opcode, val)
    end,
    [7] = function(self, opcode, val)
        cpu_idiv(self, opcode, val)
    end
}

opcode_map[0xF6] = function(self, opcode)
    do_mod_rm(self)
    grp3_table[self.reg](self, opcode, read_rm(self, opcode))
end
opcode_map[0xF7] = opcode_map[0xF6]

opcode_map[0xF8] = function(self, opcode) self.flags = band(self.flags, bnot(0x01)) end -- CF
opcode_map[0xF9] = function(self, opcode) self.flags = bor(self.flags, 0x01) end

opcode_map[0xFA] = function(self, opcode) self.flags = band(self.flags, bnot(0x200)) end -- IF
opcode_map[0xFB] = function(self, opcode) self.flags = bor(self.flags, 0x200) end

opcode_map[0xFC] = function(self, opcode) self.flags = band(self.flags, bnot(0x400)) end -- DF
opcode_map[0xFD] = function(self, opcode) self.flags = bor(self.flags, 0x400) end

local grp4_grp5_table = {
    [0] = function(self, opcode) -- INC rm
        local val = read_rm(self, opcode)
        local result = val + 1

        set_of_add(self, opcode, val, 1, result)
        set_apzs(self, opcode, val, 1, result)
        write_rm(self, opcode, result)
    end,
    [1] = function(self, opcode) -- DEC rm
        local val = read_rm(self, opcode)
        local result = val - 1

        set_of_sub(self, opcode, val, 1, result)
        set_apzs(self, opcode, val, 1, result)
        write_rm(self, opcode, result)
    end,
    [2] = function(self, opcode) -- CALL near abs
        local new_ip = read_rm(self, opcode)
        cpu_push16(self, self.ip)
        self.ip = new_ip
    end,
    [3] = function(self, opcode) -- CALL abs near
        local addr = self.ea_seg + self.ea_addr
        local new_ip = read_memory(self, opcode, addr)
        local new_cs = read_memory(self, opcode, addr + 2)

        cpu_push16(self, self.segments[2])
        cpu_push16(self, self.ip)

        self.ip = new_ip
        self.segments[2] = new_cs
    end,
    [4] = function(self, opcode) -- JMP near abs
        self.ip = read_rm(self, opcode)
    end,
    [5] = function(self, opcode) -- JMP far
        local addr = self.ea_seg + self.ea_addr
        self.ip = read_memory(self, opcode, addr)
        self.segments[2] = read_memory(self, opcode, addr + 2)
    end,
    [6] = function(self, opcode) -- PUSH rm
        cpu_push16(self, read_rm(self, opcode))
    end,
    [7] = function(self, opcode) -- PUSH rm
        cpu_push16(self, read_rm(self, opcode))
    end
}

-- GRP4 / GRP5
opcode_map[0xFE] = function(self, opcode)
    do_mod_rm(self)
    grp4_grp5_table[self.reg](self, opcode)
end
opcode_map[0xFF] = opcode_map[0xFE]

local function step(self)
    if (band(self.ip, 0xFF00) == 0x1100) and (self.segments[2] == 0xF000) then
        self.flags = bor(self.flags, 0x0200)
        local intr = call_interrupt_fake(self, band(self.ip, 0xFF))

        if intr ~= -1 then
            self.ip = cpu_pop16(self)
            self.segments[2] = cpu_pop16(self)
            local old_flags = cpu_pop16(self)
            self.flags = bor(band(self.flags, bnot(0x0200)), band(old_flags, 0x0200))
            return
        else
            return
        end
    end

    if not self.repeating then
        self.opcode = fetch_byte(self)
    end

    local instruction = opcode_map[self.opcode]

    self.completed = true

    if instruction then
        instruction(self, self.opcode)
    else
        logger.error("i8086: Illegal opcode: 0x%02X", self.opcode)
    end

    if self.completed then
        self.repeating = false
        self.segment_mode = nil
        self.rep_type = 0
        check_interrupts(self)
        self.no_int = false
    end

    return 0
end

local function reset(self)
    for i = 1, 8, 1 do
        self.regs[i] = 0
    end

    for i = 1, 4, 1 do
        self.segments[i] = 0
    end

    self.ip = 0
    self.flags = 0
    self.segment_mode = nil
    self.rep_type = 0
    self.no_int = false
    self.completed = true
    self.repeating = false
    self.nmi_mask = false
    self.nmi_enable = false
end

local function bytes_to_uint16(byte1, byte2)
    return bor(lshift(byte1, 8), byte2)
end

local function save_state(self, stream)
    stream:write_uint32(32) -- Chunk Size

    for i = 1, #self.regs, 1 do
        stream:write_uint16(self.regs[i])
    end

    for i = 1, 4, 1 do
        stream:write_uint16(self.segments[i])
    end

    stream:write_uint16(self.ip)
    stream:write_uint16(self.flags)
    stream:write(self.segment_mode or 0)
    stream:write(self.opcode)
    stream:write(self.rep_type)

    local flags = 0x00

    if self.no_int then
        flags = bor(flags, 0x01)
    end

    if self.completed then
        flags = bor(flags, 0x02)
    end

    if self.repeating then
        flags = bor(flags, 0x04)
    end

    if self.nmi_enable then
        flags = bor(flags, 0x08)
    end

    if self.nmi_mask then
        flags = bor(flags, 0x10)
    end

    stream:write(flags)
end

local function load_state(self, data)
    for i = 1, 8, 1 do
        self.regs[i] = bytes_to_uint16(data[i], data[i + 1])
    end

    for i = 1, 4, 1 do
        local offset = 16 + i
        self.segments[i] = bytes_to_uint16(data[offset], data[offset + 1])
    end

    self.ip = bytes_to_uint16(data[25], data[26]) -- IP
    self.flags = bytes_to_uint16(data[27], data[28]) -- Flags

    if data[29] == 0 then
        self.segment_mode = nil
    else
        self.segment_mode = data[29]
    end

    self.opcode = data[30]
    self.rep_type = data[31]

    local flags = data[32]

    self.no_int = band(flags, 0x01) ~= 0
    self.completed = band(flags, 0x02) ~= 0
    self.repeating = band(flags, 0x04) ~= 0
    self.nmi_enable = band(flags, 0x08) ~= 0
    self.nmi_mask = band(flags, 0x10) ~= 0
end

local function port_A0(self)
    return function(cpu, port, val)
        if val then
            self.nmi_mask = band(val, 0x80) ~= 0
        else
            return 0xFF
        end
    end
end

local function get_port(self, port)
    return self.io_ports[port]
end

local function set_port(self, port, handler)
    self.io_ports[port] = handler
end

local function set_interrupt_handler(self, id, handler)
    self.interrupt_handlers[id] = handler
end

local function get_interrupt_handler(self, id)
    return self.interrupt_handlers[id]
end

local function out_port(self, port, val)
    cpu_out(self, port, val)
end

local function in_port(self, port)
    return cpu_in(self, port)
end

local cpu = {}

function cpu.new(memory)
    local self = {
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
        segment_mode = nil,
        no_int = false,
        completed = true,
        repeating = false,
        nmi_mask = false,
        nmi_enable = false,
        memory = memory,
        pic = {},
        interrupt_handlers = {},
        io_ports = {},
        set_flag = set_flag,
        clear_flag = clear_flag,
        write_flag = write_flag,
        set_interrupt_handler = set_interrupt_handler,
        get_interrupt_handler = get_interrupt_handler,
        call_interrupt = call_interrupt,
        get_port = get_port,
        set_port = set_port,
        out_port = out_port,
        in_port = in_port,
        set_ip = cpu_set_ip,
        step = step,
        reset = reset,
        save_state = save_state,
        load_state = load_state
    }

    set_port(self, 0xA0, port_A0(self))

    return self
end

return cpu