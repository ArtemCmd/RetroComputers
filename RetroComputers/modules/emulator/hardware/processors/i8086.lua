-- TODO: Rewrite
local logger = require("retro_computers:logger")
local bit_converter = require("core:bit_converter")

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot
local run_one = function (self, a, b) end

local rm_seg_table = {
    3, 3,
    2, 2,
    3, 3,
    2, 3
}

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

local cpu_rm_addr = {
    function(self, data) return band((self.regs[4] + self.regs[7] + data.disp), 0xFFFF) end,
    function(self, data) return band((self.regs[4] + self.regs[8] + data.disp), 0xFFFF) end,
    function(self, data) return band((self.regs[6] + self.regs[7] + data.disp), 0xFFFF) end,
    function(self, data) return band((self.regs[6] + self.regs[8] + data.disp), 0xFFFF) end,
    function(self, data) return band((self.regs[7] + data.disp), 0xFFFF) end,
    function(self, data) return band((self.regs[8] + data.disp), 0xFFFF) end,
    function(self, data) return band((self.regs[6] + data.disp), 0xFFFF) end,
    function(self, data) return band((self.regs[4] + data.disp), 0xFFFF) end
}

local read_rm_table = {
    [0] = function(self, data) return self.regs[1] end,
    [1] = function(self, data) return self.regs[2] end,
    [2] = function(self, data) return self.regs[3] end,
    [3] = function(self, data) return self.regs[4] end,
    [4] = function(self, data) return self.regs[5] end,
    [5] = function(self, data) return self.regs[6] end,
    [6] = function(self, data) return self.regs[7] end,
    [7] = function(self, data) return self.regs[8] end,
    [8] = function(self, data) return self.memory:r16(lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[1](self, data)) end,
    [9] = function(self, data) return self.memory:r16(lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[2](self, data)) end,
    [10] = function(self, data) return self.memory:r16(lshift(self.segments[self.segment_mode or 3], 4) + cpu_rm_addr[3](self, data)) end,
    [11] = function(self, data) return self.memory:r16(lshift(self.segments[self.segment_mode or 3], 4) + cpu_rm_addr[4](self, data)) end,
    [12] = function(self, data) return self.memory:r16(lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[5](self, data)) end,
    [13] = function(self, data) return self.memory:r16(lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[6](self, data)) end,
    [14] = function(self, data) return self.memory:r16(lshift(self.segments[self.segment_mode or 3], 4) + cpu_rm_addr[7](self, data)) end,
    [15] = function(self, data) return self.memory:r16(lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[8](self, data)) end,
    [16] = function(self, data) return band(self.regs[1], 0xFF) end,
    [17] = function(self, data) return band(self.regs[2], 0xFF) end,
    [18] = function(self, data) return band(self.regs[3], 0xFF) end,
    [19] = function(self, data) return band(self.regs[4], 0xFF) end,
    [20] = function(self, data) return rshift(self.regs[1], 8) end,
    [21] = function(self, data) return rshift(self.regs[2], 8) end,
    [22] = function(self, data) return rshift(self.regs[3], 8) end,
    [23] = function(self, data) return rshift(self.regs[4], 8) end,
    [24] = function(self, data) return self.memory[lshift(self.segments[self.segment_mode or 4], 4) + data.disp] end,
    [25] = function(self, data) return self.memory:r16(lshift(self.segments[self.segment_mode or 4], 4) + data.disp) end,
    [26] = function(self, data) return self.segments[1] end,
    [27] = function(self, data) return self.segments[2] end,
    [28] = function(self, data) return self.segments[3] end,
    [29] = function(self, data) return self.segments[4] end,
    [30] = function(self, data) return self.segments[5] end,
    [31] = function(self, data) return self.segments[6] end,
    [32] = function(self, data) return self.memory[lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[1](self, data)] end,
    [33] = function(self, data) return self.memory[lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[2](self, data)] end,
    [34] = function(self, data) return self.memory[lshift(self.segments[self.segment_mode or 3], 4) + cpu_rm_addr[3](self, data)] end,
    [35] = function(self, data) return self.memory[lshift(self.segments[self.segment_mode or 3], 4) + cpu_rm_addr[4](self, data)] end,
    [36] = function(self, data) return self.memory[lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[5](self, data)] end,
    [37] = function(self, data) return self.memory[lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[6](self, data)] end,
    [38] = function(self, data) return self.memory[lshift(self.segments[self.segment_mode or 3], 4) + cpu_rm_addr[7](self, data)] end,
    [39] = function(self, data) return self.memory[lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[8](self, data)] end,
    [40] = function(self, data) return band(data.imm, 0xFF) end,
    [41] = function(self, data) return data.imm end
}

local write_rm_table = {
    [0] = function(self, data, val) self.regs[1] = val end,
    [1] = function(self, data, val) self.regs[2] = val end,
    [2] = function(self, data, val) self.regs[3] = val end,
    [3] = function(self, data, val) self.regs[4] = val end,
    [4] = function(self, data, val) self.regs[5] = val end,
    [5] = function(self, data, val) self.regs[6] = val end,
    [6] = function(self, data, val) self.regs[7] = val end,
    [7] = function(self, data, val) self.regs[8] = val end,
    [8] = function(self, data, val) self.memory:w16(lshift(self.segments[(self.segment_mode or 4)], 4) + cpu_rm_addr[1](self, data), val) end,
    [9] = function(self, data, val) self.memory:w16(lshift(self.segments[(self.segment_mode or 4)], 4) + cpu_rm_addr[2](self, data), val) end,
    [10] = function(self, data, val) self.memory:w16(lshift(self.segments[(self.segment_mode or 3)], 4) + cpu_rm_addr[3](self, data), val) end,
    [11] = function(self, data, val) self.memory:w16(lshift(self.segments[(self.segment_mode or 3)], 4) + cpu_rm_addr[4](self, data), val) end,
    [12] = function(self, data, val) self.memory:w16(lshift(self.segments[(self.segment_mode or 4)], 4) + cpu_rm_addr[5](self, data), val) end,
    [13] = function(self, data, val) self.memory:w16(lshift(self.segments[(self.segment_mode or 4)], 4) + cpu_rm_addr[6](self, data), val) end,
    [14] = function(self, data, val) self.memory:w16(lshift(self.segments[(self.segment_mode or 3)], 4) + cpu_rm_addr[7](self, data), val) end,
    [15] = function(self, data, val) self.memory:w16(lshift(self.segments[(self.segment_mode or 4)], 4) + cpu_rm_addr[8](self, data), val) end,
    [16] = function(self, data, val) self.regs[1] = bor(band(self.regs[1], 0xFF00), band(val, 0xFF)) end,
    [17] = function(self, data, val) self.regs[2] = bor(band(self.regs[2], 0xFF00), band(val, 0xFF)) end,
    [18] = function(self, data, val) self.regs[3] = bor(band(self.regs[3], 0xFF00), band(val, 0xFF)) end,
    [19] = function(self, data, val) self.regs[4] = bor(band(self.regs[4], 0xFF00), band(val, 0xFF)) end,
    [20] = function(self, data, val) self.regs[1] = bor(band(self.regs[1], 0xFF), lshift(band(val, 0xFF), 8)) end,
    [21] = function(self, data, val) self.regs[2] = bor(band(self.regs[2], 0xFF), lshift(band(val, 0xFF), 8)) end,
    [22] = function(self, data, val) self.regs[3] = bor(band(self.regs[3], 0xFF), lshift(band(val, 0xFF), 8)) end,
    [23] = function(self, data, val) self.regs[4] = bor(band(self.regs[4], 0xFF), lshift(band(val, 0xFF), 8)) end,
    [24] = function(self, data, val) self.memory[lshift(self.segments[self.segment_mode or 4], 4) + data.disp] = band(val, 0xFF) end,
    [25] = function(self, data, val) self.memory:w16((lshift(self.segments[self.segment_mode or 4], 4) + data.disp), val) end,
    [26] = function(self, data, val) self.segments[1] = val end,
    [27] = function(self, data, val) self.segments[2] = val end,
    [28] = function(self, data, val) self.segments[3] = val end,
    [29] = function(self, data, val) self.segments[4] = val end,
    [30] = function(self, data, val) self.segments[5] = val end,
    [31] = function(self, data, val) self.segments[6] = val end,
    [32] = function(self, data, val) self.memory[lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[1](self, data)] = band(val, 0xFF) end,
    [33] = function(self, data, val) self.memory[lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[2](self, data)] = band(val, 0xFF) end,
    [34] = function(self, data, val) self.memory[lshift(self.segments[self.segment_mode or 3], 4) + cpu_rm_addr[3](self, data)] = band(val, 0xFF) end,
    [35] = function(self, data, val) self.memory[lshift(self.segments[self.segment_mode or 3], 4) + cpu_rm_addr[4](self, data)] = band(val, 0xFF) end,
    [36] = function(self, data, val) self.memory[lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[5](self, data)] = band(val, 0xFF) end,
    [37] = function(self, data, val) self.memory[lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[6](self, data)] = band(val, 0xFF) end,
    [38] = function(self, data, val) self.memory[lshift(self.segments[self.segment_mode or 3], 4) + cpu_rm_addr[7](self, data)] = band(val, 0xFF) end,
    [39] = function(self, data, val) self.memory[lshift(self.segments[self.segment_mode or 4], 4) + cpu_rm_addr[8](self, data)] = band(val, 0xFF) end
}

local function emit_interrupt(self, v, nmi)
    nmi = (v == 2)

    if nmi then
        table.insert(self.intqueue, v + 256)
    else
        table.insert(self.intqueue, v)
    end

    self.hasint = true
end

local function seg(self, s, v)
    return lshift(self.segments[s + 1], 4) + v
end

local function advance_ip(self)
    local ip = (lshift(self.segments[2], 4) + self.ip)
    self.ip = band(self.ip + 1, 0xFFFF)
    return self.memory[ip]
end

local function advance_ip16(self)
    local ip = (lshift(self.segments[2], 4) + self.ip)
    self.ip = band(self.ip + 2, 0xFFFF)
    return self.memory:r16(ip)
end

local function to_8(value)
    if value >= 0x80 then
        return value - 0x100
    else
        return value
    end
end

local function to_16(value)
    if value >= 0x8000 then
        return value - 0x10000
    else
        return value
    end
end

local function to_32(value)
    if value >= 0x80000000 then
        return value - 0x100000000
    else
        return value
    end
end

local function cpu_clear_flag(self, t)
    self.flags = band(self.flags, bnot(lshift(1, t)))
end

local function cpu_set_flag(self, t)
    self.flags = bor(self.flags, lshift(1, t))
end

local function cpu_write_flag(self, num, val)
    if val then
        cpu_set_flag(self, num)
    else
        cpu_clear_flag(self, num)
    end
end

local function cpu_incdec_dir(self, t, amount)
    if (band(self.flags, lshift(1, (10))) ~= 0) then
        self.regs[t] = band(self.regs[t] - amount, 0xFFFF)
    else
        self.regs[t] = band(self.regs[t] + amount, 0xFFFF)
    end
end

local function cpu_set_ip(self, cs, ip)
    self.segments[2] = band(cs, 0xFFFF)
    self.ip = band(ip, 0xFFFF)
end

local function cpu_seg_rm(self, data, v)
    if (v >= 8) and (v < 16) then
        return rm_seg_table[v - 7]
    elseif (v >= 32) and (v < 40) then
        return rm_seg_table[v - 31]
    else
        return 3
    end
end

local function cpu_addr_rm(self, data, v)
    if (v >= 8) and (v < 16) then
        return cpu_rm_addr[v - 7](self, data)
    elseif (v >= 24) and (v <= 25) then
        return data.disp
    elseif (v >= 32) and (v < 40) then
        return cpu_rm_addr[v - 31](self, data)
    else
        return 0xFF
    end
end

local function cpu_read_rm(self, data, v)
    return read_rm_table[v](self, data)
end

local function cpu_write_rm(self, data, v, val)
    write_rm_table[v](self, data, val)
end

local mrm_table = {}
for i = 0, 2047, 1 do
    local is_seg = band(i, 1024) ~= 0
    local mod = band(rshift(i, 6), 0x03)
    local reg = band(rshift(i, 3), 0x07)
    local rm = band(i, 0x07)
    local d = band(rshift(i, 9), 0x01)
    local variant = band(rshift(i, 8), 0x01)

    if is_seg then
        variant = 1
    end

    local op1 = reg
    local op2 = rm

    if is_seg then
        op1 = (op1 % 6) + 26
    elseif variant == 0 then
        op1 = op1 + 16
    end

    if mod == 0 and rm == 6 then
        op2 = 24 + variant
    elseif mod ~= 3 then
        if variant == 0 then
            op2 = op2 + 32
        else
            op2 = op2 + 8
        end
    else
        if variant == 0 then
            op2 = op2 + 16
        end
    end

    local src, dst
    if d == 0 then
        src = op1
        dst = op2
    else
        src = op2
        dst = op1
    end

    local cdisp = 0
    if mod == 2 then
        cdisp = 2
    elseif mod == 1 then
        cdisp = 1
    elseif mod == 0 and rm == 6 then
        cdisp = 3
    end

    mrm_table[i] = {src = src, dst = dst, cdisp = cdisp, disp = 0}
end

local function cpu_mod_rm(self, opcode, is_seg)
    local modrm = bor(bor(advance_ip(self), lshift(band(opcode, 3), 8)), is_seg or 0)
    local data = mrm_table[modrm]

    if data.cdisp == 0 then
        return data
    elseif data.cdisp == 2 then
        data.disp = to_16(advance_ip16(self))
    elseif data.cdisp == 1 then
        data.disp = to_8(advance_ip(self))
    elseif data.cdisp == 3 then
        data.disp = advance_ip16(self)
    end

    return data
end

local function cpu_mrm_copy(data)
    return {src = data.src, dst = data.dst, disp = data.disp}
end

local mrm6_4 = {src = 40, dst = 16, imm = 0}
local mrm6_5 = {src = 41, dst = 0, imm = 0}

local mrm6_table = {
    [0] = cpu_mod_rm,
    [1] = cpu_mod_rm,
    [2] = cpu_mod_rm,
    [3] = cpu_mod_rm,
    [4] = function(self, v)
        mrm6_4.imm = advance_ip(self)
        return mrm6_4
    end,
    [5] = function(self, v)
        mrm6_5.imm = advance_ip16(self)
        return mrm6_5
    end,
    [6] = cpu_mod_rm,
    [7] = cpu_mod_rm
}

local function cpu_push16(self, val)
    self.regs[5] = band(self.regs[5] - 2, 0xFFFF)
    self.memory:w16((lshift(self.segments[3], 4) + self.regs[5]), band(val, 0xFFFF))
end

local function cpu_pop16(self)
    local old_sp = self.regs[5]
    self.regs[5] = band(old_sp + 2, 0xFFFF)
    return self.memory:r16(lshift(self.segments[3], 4) + old_sp)
end

local function cpu_mov(self, mrm)
    local val1 = cpu_read_rm(self, mrm, mrm.src)
    cpu_write_rm(self, mrm, mrm.dst, val1)
end

local function cpu_zsp(self, result, opc)
    if band(opc, 0x01) == 1 then
        cpu_write_flag(self, 6, band(result, 0xFFFF) == 0)
        cpu_write_flag(self, 7, band(result, 0x8000) ~= 0)
        self.flags = bor(band(self.flags, 0xFFFB), parity_table[band(result, 0xFF)])
    else
        cpu_write_flag(self, 6, band(result, 0xFF) == 0)
        cpu_write_flag(self, 7, band(result, 0x80) ~= 0)
        self.flags = bor(band(self.flags, 0xFFFB), parity_table[band(result, 0xFF)])
    end
end

local function cpu_inc(self, result, opc)
    cpu_zsp(self, result, opc)
    cpu_write_flag(self, 4, band(result, 0xF) == 0x0)
    if band(opc, 0x01) == 1 then
        cpu_write_flag(self, 11, result == 0x8000)
    else
        cpu_write_flag(self, 11, result == 0x80)
    end
end

local function cpu_dec(self, result, opc)
    cpu_zsp(self, result, opc)
    cpu_write_flag(self, 4, band(result, 0xF) == 0xF)
    if band(opc, 0x01) == 1 then
        cpu_write_flag(self, 11, result == 0x7FFF)
    else
        cpu_write_flag(self, 11, result == 0x7F)
    end
end

local function cpu_uf_add(self, val1, val2, vc, result, opc)
    cpu_write_flag(self, 4, (band(val1, 0xF) + band(val2, 0xF) + vc) >= 0x10)
    if band(opc, 0x01) == 1 then
        cpu_write_flag(self, 0, band(result, 0xFFFF) ~= result)
        cpu_write_flag(self, 11, (band(val1, 0x8000) == band(val2, 0x8000)) and (band(result, 0x8000) ~= band(val1, 0x8000)))
    else
        cpu_write_flag(self, 0, band(result, 0xFF) ~= result)
        cpu_write_flag(self, 11, (band(val1, 0x80) == band(val2, 0x80)) and (band(result, 0x80) ~= band(val1, 0x80)))
    end
end

local function cpu_uf_sub(self, val1, val2, vb, result, opc)
    cpu_write_flag(self, 4, (band(val2, 0xF) - band(val1, 0xF) - vb) < 0)
    if band(opc, 0x01) == 1 then
        cpu_write_flag(self, 0, band(result, 0xFFFF) ~= result)
        cpu_write_flag(self, 11, (band(val1, 0x8000) ~= band(val2, 0x8000)) and (band(result, 0x8000) == band(val1, 0x8000)))
    else
        cpu_write_flag(self, 0, band(result, 0xFF) ~= result)
        cpu_write_flag(self, 11, (band(val1, 0x80) ~= band(val2, 0x80)) and (band(result, 0x80) == band(val1, 0x80)))
    end
end

local function cpu_uf_bit(self, result, opc)
    self.flags = band(self.flags, bnot(0x0801))
    cpu_zsp(self, result, opc)
end

local function cpu_shl(self, mrm, opcode)
    local val1 = band(cpu_read_rm(self, mrm, mrm.src), 0xFF)
    local mask = 0xFFFF

    if band(opcode, 0x01) == 0 then
        mask = 0xFF
    end

    local val2 = cpu_read_rm(self, mrm, mrm.dst)
    local msb = rshift(mask, 1) + 1
    local result = lshift(val2, val1)

    cpu_write_flag(self, 0, band(result, (mask + 1)) ~= 0)
    cpu_write_rm(self, mrm, mrm.dst, band(result, mask))
    cpu_zsp(self, band(result, mask), opcode)

    if val1 == 1 then
        local msb_result = band(result, msb) ~= 0
        cpu_write_flag(self, 11, (band(self.flags, 0x01) ~= 0) ~= msb_result)
    end
end

local function cpu_shr(self, mrm, opcode, arith)
    local mask = 0x8000
    if band(opcode, 0x01) == 0 then
        mask = 0x80
    end

    local val1 = band(cpu_read_rm(self, mrm, mrm.src), 0xFF)
    local val2 = cpu_read_rm(self, mrm, mrm.dst)
    local result = 0

    if arith then
        result = val2
        local shift = val1

        while shift > 0 do
            result = bor(band(result, mask), band(rshift(result, 1), (mask - 1)))
            shift = shift - 1
        end
    else
        result = rshift(val2, val1)
    end

    cpu_write_rm(self, mrm, mrm.dst, result)
    cpu_zsp(self, result, opcode)

    if lshift(1, (band(val1, 0x1F) - 1)) > mask then
        cpu_write_flag(self, 0, arith and (band(val2, mask) ~= 0))
    else
        cpu_write_flag(self, 0, band(val2, lshift(1, (val1 - 1))) ~= 0)
    end

    if val1 == 1 then
        cpu_write_flag(self, 11, (not arith) and (band(val2, mask) ~= 0))
    end
end

-- Modes: 
-- 0 - ROR
-- 1 - ROL
-- 2 - RCR
-- 3 - RCL
local function cpu_rotate(self, mrm, opcode, mode)
    local shift = 15

    if band(opcode, 0x01) == 0 then
        shift = 7
    end

    local val1 = band(cpu_read_rm(self, mrm, mrm.src), 0xFF)
    local val2 = cpu_read_rm(self, mrm, mrm.dst)
    local result = val2
    local cf = 0
    local of = 0

    if band(self.flags, 0x01) ~= 0 then
        cf = 1
    end

    local shifts = val1
    if shifts > 0 then
        if mode == 0 then
            shifts = band(shifts, shift)
            local shiftmask = lshift(1, shifts) - 1
            cf = band(rshift(result, band(shifts - 1, shift)), 0x01)
            result = bor(rshift(result, shifts), lshift(band(result, shiftmask), band(shift - shifts + 1, shift)))
            of = band(bxor(rshift(result, shift), rshift(result, shift - 1)), 0x01)
        elseif mode == 1 then
            shifts = band(shifts, shift)
            cf = band(rshift(result, band(shift - shifts + 1, shift)), 0x01)
            result = bor(band(lshift(result, shifts), lshift(1, shift + 1) - 1), rshift(result, band(shift - shifts + 1, shift)))
            of = band(bxor(rshift(result, shift), cf), 0x01)
        elseif mode == 2 then
            shifts = shifts % (shift + 2)

            while shifts > 0 do
                local new_cf = band(result, 0x01)
                result = bor(rshift(result, 1), lshift(cf, shift))
                shifts = shifts - 1
                cf = new_cf
            end

            of = band(bxor(rshift(result, shift), rshift(result, shift - 1)), 0x01)
        elseif mode == 3 then
            shifts = shifts % (shift + 2)

            while shifts > 0 do
                local new_cf = band(rshift(result, shift), 0x01)
                result = bor(band(lshift(result, 1), lshift(1, shift + 1) - 1), cf)
                shifts = shifts - 1
                cf = new_cf
            end

            of = band(bxor(rshift(result, shift), cf), 0x01)
        end

        cpu_write_rm(self, mrm, mrm.dst, band(result, 0xFFFF))
        cpu_write_flag(self, 0, cf == 1)

        if val1 == 1 then
            cpu_write_flag(self, 11, of == 1)
        end
    end
end

local function cpu_mul(self, mrm, opcode)
    local val1 = cpu_read_rm(self, mrm, mrm.src)
    local val2 = cpu_read_rm(self, mrm, mrm.dst)
    local result = val1 * val2
    local ret = 0

    if band(opcode, 0x01) == 1 then
        result = band(result, 0xFFFFFFFF)
        self.regs[3] = rshift(result, 16)
        self.regs[1] = band(result, 0xFFFF)
        ret = rshift(result, 16)
    else
        result = band(result, 0xFFFF)
        self.regs[1] = result
        ret = rshift(result, 8)
    end

    cpu_write_flag(self, 0, ret ~= 0)
    cpu_write_flag(self, 11, ret ~= 0)
end

local function cpu_imul(self, mrm, opcode)
    local val1 = cpu_read_rm(self, mrm, mrm.src)
    local val2 = cpu_read_rm(self, mrm, mrm.dst)
    local result = 0

    if band(opcode, 0x01) == 1 then
        result = (to_16(val1) * to_16(val2))
        self.regs[3] = band(rshift(result, 16), 0xFFFF)
        self.regs[1] = band(result, 0xFFFF)

        cpu_write_flag(self, 0, (result < -0x8000) or (result >= 0x8000))
        cpu_write_flag(self, 11, (result < -0x8000) or (result >= 0x8000))
    else
        result = (to_8(val1) * to_8(val2))
        self.regs[1] = band(result, 0xFFFF)

        cpu_write_flag(self, 0, (result < -0x80) or (result >= 0x80))
        cpu_write_flag(self, 11, (result < -0x80) or (result >= 0x80))
    end
end

local function cpu_div(self, mrm, opcode)
    local val2 = cpu_read_rm(self, mrm, mrm.dst)

    if band(opcode, 0x01) == 1 then
        local val = bor(lshift(self.regs[3], 16), self.regs[1])

        if val2 == 0 then
            logger:error("i8086: Divide %d by zero", val)
            emit_interrupt(self, 0, false)
            return
        end

        local vall = math.floor(val / val2)
        local valh = val % val2

        if vall > 0xFFFF then
            logger:error("i8086: Overflow: %d / %d = %d", val, val2, vall)
            emit_interrupt(self, 0, false)
            return
        end

        self.regs[3] = band(valh, 0xFFFF)
        self.regs[1] = band(vall, 0xFFFF)
    else
        local val = self.regs[1]

        if val2 == 0 then
            logger:error("i8086: Divide %d by zero", val)
            emit_interrupt(self, 0, false)
            return
        end

        local vall = math.floor(val / val2)
        local valh = val % val2

        if vall > 0xFF then
            logger:error("i8086: Overflow: %d / %d = %d", val, val2, vall)
            emit_interrupt(self, 0, false)
            return
        end

        self.regs[1] = bor(lshift(band(valh, 0xFF), 8), band(vall, 0xFF))
    end
end

local function cpu_idiv(self, mrm, opcode)
    local val2 = cpu_read_rm(self, mrm, mrm.dst)

    if band(opcode, 0x01) == 1 then
        local val1 = to_32(bor(lshift(self.regs[3], 16), self.regs[1]))
        val2 = to_16(val2)

        if val2 == 0 then
            logger:error("i8086: Divide %d by zero", val1)
            emit_interrupt(self, 0, false)
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
            logger:error("i8086: Overflow: %d / %d = %d", val1, val2, vall)
            emit_interrupt(self, 0, false)
            return
        end

        self.regs[3] = band(valh, 0xFFFF)
        self.regs[1] = band(vall, 0xFFFF)
    else
        local val1 = to_16(self.regs[1])

        val2 = to_8(val2)

        if val2 == 0 then
            logger:error("i8086: Divide %d by zero", val2)
            emit_interrupt(self, 0, false)
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
            logger:error("i8086: Overflow: %d / %d = %d", val1, val2, vall)
            emit_interrupt(self, 0, false)
            return
        end

        self.regs[1] = bor(lshift(band(valh, 0xFF), 8), band(vall, 0xFF))
    end
end

local function cpu_add(self, mrm, opcode, carry)
    local val1 = cpu_read_rm(self, mrm, mrm.src)
    local val2 = cpu_read_rm(self, mrm, mrm.dst)
    local cf = 0

    if carry and (band(self.flags, 0x01) ~= 0) then
        cf = 1
    end

    local result = val1 + val2 + cf

    if band(opcode, 0x01) == 0x01 then
        cpu_write_rm(self, mrm, mrm.dst, band(result, 0xFFFF))
    else
        cpu_write_rm(self, mrm, mrm.dst, band(result, 0xFF))
    end

    cpu_zsp(self, result, opcode)
    cpu_uf_add(self, val1, val2, cf, result, opcode)
end

local function cpu_cmp(self, val2, val1, opcode)
    local result = val2 - val1
    cpu_uf_sub(self, val1, val2, 0, result, opcode)
    cpu_zsp(self, result, opcode)
end

local function cpu_cmp_mrm(self, mrm, opcode)
    cpu_cmp(self, cpu_read_rm(self, mrm, mrm.dst), cpu_read_rm(self, mrm, mrm.src), opcode)
end

local function cpu_sub(self, mrm, opcode, borrow)
    local val1 = cpu_read_rm(self, mrm, mrm.src)
    local val2 = cpu_read_rm(self, mrm, mrm.dst)
    local bf = 0

    if borrow and (band(self.flags, 0x01) ~= 0) then
        bf = 1
    end

    local result = val2 - val1 - bf
    cpu_uf_sub(self, val1, val2, bf, result, opcode)

    if band(opcode, 0x01) == 0x01 then
        result = band(result, 0xFFFF)
    else
        result = band(result, 0xFF)
    end

    cpu_write_rm(self, mrm, mrm.dst, result)
    cpu_zsp(self, result, opcode)
end

local function cpu_xor(self, mrm, opc)
    local val1 = cpu_read_rm(self, mrm, mrm.src)
    local val2 = cpu_read_rm(self, mrm, mrm.dst)
    local result = bxor(val1, val2)
    cpu_write_rm(self, mrm, mrm.dst, result)
    cpu_uf_bit(self, result, opc)
end

local function cpu_and(self, mrm, opc)
    local val1 = cpu_read_rm(self, mrm, mrm.src)
    local val2 = cpu_read_rm(self, mrm, mrm.dst)
    local result = band(val1, val2)
    cpu_write_rm(self, mrm, mrm.dst, result)
    cpu_uf_bit(self, result, opc)
end

local function cpu_test(self, mrm, opc)
    local val1 = cpu_read_rm(self, mrm, mrm.src)
    local val2 = cpu_read_rm(self, mrm, mrm.dst)
    local result = band(val1, val2)
    cpu_uf_bit(self, result, opc)
end

local function cpu_or(self, mrm, opc)
    local val1 = cpu_read_rm(self, mrm, mrm.src)
    local val2 = cpu_read_rm(self, mrm, mrm.dst)
    local result = bor(val1, val2)
    cpu_write_rm(self, mrm, mrm.dst, result)
    cpu_uf_bit(self, result, opc)
end

local function cpu_rep(self, cond)
    local old_ip = self.ip
    local opcode = advance_ip(self)

    if (self.regs[2] == 0) then
        return true
    end

    self.ip = old_ip

    local pr_state = true
    local skip_opcodes = opcode ~= 0xA6 and opcode ~= 0xA7 and opcode ~= 0xAE and opcode ~= 0xAF

    while self.regs[2] ~= 0 do
        local r = run_one(self, true, pr_state)

        if not r then
            return false
        elseif r == false then
            logger:error("i8086: Chto to ne tak")
        end

        self.regs[2] = band((self.regs[2] - 1), 0xFFFF)
        if self.regs[2] == 0  then
            break
        end

        local condResult = skip_opcodes
        if not condResult then condResult = cond() end
        if condResult then
            self.ip = old_ip
            pr_state = false
        else
            break
        end
    end

    return true
end

local function cpu_in(self, port)
    local handler = self.io_ports[port]

    -- logger:debug("i8086: Cpu in port:%02X", port)

    if handler ~= nil then
        return handler(self, port, nil)
    else
        logger:warning("i8086: Cpu in: port:%02X not found", port)
        return 0xFFFF
    end
end

local function cpu_out(self, port, val)
    local handler = self.io_ports[port]

    -- logger:debug("i8086: Cpu out port:%02X", port)

    if handler ~= nil then
        handler(self, port, val)
    else
        logger:warning("i8086: Cpu out: port:%02X not found", port)
    end
end

local function out_port(self, port, val)
    cpu_out(self, port, val)
end

local function in_port(self, port)
    return cpu_in(self, port)
end

local function port_get(self, port)
    return self.io_ports[port]
end

local function port_set(self, port, handler)
    self.io_ports[port] = handler
end

local function register_interrupt_handler(self, id, handler)
    self.interrupt_handlers[id + 1] = handler
end

local function cpu_int_fake(self, id)
    local ax = self.regs[1]
    local ah = rshift(ax, 8)
    local al = band(ax, 0xFF)

    local handler = self.interrupt_handlers[id + 1]

    if handler then
        local result = handler(self, ax, ah, al)
        if result then
            return result
        end
    end

    logger:info("i8086: Unknown interrupt: %02X, AH = %02X", id, ah)
end

local function cpu_int(self, id)
    -- logger:debug("i8086: Interrupt %02X, AH = %02X", id, rshift(self.regs[1], 8))
    local addr = self.memory:r16(id * 4)
    local segment = self.memory:r16(id * 4 + 2)

    cpu_push16(self, self.flags)
    cpu_push16(self, self.segments[2])
    cpu_push16(self, self.ip)

    self.segments[2] = segment
    self.ip = addr
    self.halted = false

    self.flags = band(self.flags, bnot(bor(0x0200, 0x0100)))
end

local rel_jmp_conds = {
    function(self) return (band(self.flags, 0x0800) ~= 0) end, -- OF
    function(self) return (band(self.flags, 0x0800) == 0) end, -- OF
    function(self) return (band(self.flags, 0x0001) ~= 0) end, -- CF
    function(self) return (band(self.flags, 0x0001) == 0) end, -- CF
    function(self) return (band(self.flags, 0x0040) ~= 0) end, -- ZF
    function(self) return (band(self.flags, 0x0040) == 0) end, -- ZF
    function(self) return (band(self.flags, 0x0001) ~= 0) or (band(self.flags, 0x0040) ~= 0) end, -- CF / ZF
    function(self) return not ((band(self.flags, 0x0001) ~= 0) or (band(self.flags, 0x0040) ~= 0)) end, --  CF / ZF
    function(self) return (band(self.flags, 0x0080) ~= 0) end, -- SF
    function(self) return not (band(self.flags, 0x0080) ~= 0) end, -- SF
    function(self) return (band(self.flags, 0x0004) ~= 0) end, -- PF
    function(self) return not (band(self.flags, 0x0004) ~= 0) end, -- PF
    function(self) return (band(self.flags, 0x0800) ~= 0) ~= (band(self.flags, 0x0080) ~= 0) end, -- OF / SF
    function(self) return (band(self.flags, 0x0800) ~= 0) == (band(self.flags, 0x0080) ~= 0) end, -- OF / SF
    function(self) return ((band(self.flags, 0x0800) ~= 0) ~= (band(self.flags, 0x0080) ~= 0)) or (band(self.flags, 0x0040) ~= 0) end, -- OF / SF / ZF
    function(self) return not (((band(self.flags, 0x0800) ~= 0) ~= (band(self.flags, 0x0080) ~= 0)) or (band(self.flags, 0x0040) ~= 0)) end -- OF / SF / ZF
}

local opcode_map = {}

-- NOP
opcode_map[0x90] = function(self, opcode) end

-- ADD
opcode_map[0x00] = function(self, opcode)
    cpu_add(self, mrm6_table[band(opcode, 0x7)](self, opcode), opcode)
end
opcode_map[0x01] = opcode_map[0x00]
opcode_map[0x02] = opcode_map[0x00]
opcode_map[0x03] = opcode_map[0x00]
opcode_map[0x04] = opcode_map[0x00]
opcode_map[0x05] = opcode_map[0x00]

-- PUSH seg
opcode_map[0x06] = function(self, opcode) cpu_push16(self, self.segments[1]) end -- ES
opcode_map[0x0E] = function(self, opcode) cpu_push16(self, self.segments[2]) end -- CS
opcode_map[0x16] = function(self, opcode) cpu_push16(self, self.segments[3]) end -- SS
opcode_map[0x1E] = function(self, opcode) cpu_push16(self, self.segments[4]) end -- DS

-- POP seg
opcode_map[0x07] = function(self, opcode) self.segments[1] = cpu_pop16(self) end -- ES
opcode_map[0x0F] = function(self, opcode) self.segments[2] = cpu_pop16(self) end -- CS
opcode_map[0x17] = function(self, opcode) self.segments[3] = cpu_pop16(self) end -- SS
opcode_map[0x1F] = function(self, opcode) self.segments[4] = cpu_pop16(self) end -- DS

-- OR
opcode_map[0x08] = function(self, opcode)
    cpu_or(self, mrm6_table[band(opcode, 0x7)](self, opcode), opcode)
end
opcode_map[0x09] = opcode_map[0x08]
opcode_map[0x0A] = opcode_map[0x08]
opcode_map[0x0B] = opcode_map[0x08]
opcode_map[0x0C] = opcode_map[0x08]
opcode_map[0x0D] = opcode_map[0x08]

-- ADC
opcode_map[0x10] = function(self, opcode)
    cpu_add(self, mrm6_table[band(opcode, 0x7)](self, opcode), opcode, true)
end
opcode_map[0x11] = opcode_map[0x10]
opcode_map[0x12] = opcode_map[0x10]
opcode_map[0x13] = opcode_map[0x10]
opcode_map[0x14] = opcode_map[0x10]
opcode_map[0x15] = opcode_map[0x10]

-- SBB
opcode_map[0x18] = function(self, opcode)
    cpu_sub(self, mrm6_table[band(opcode, 0x7)](self, opcode), opcode, true)
end
opcode_map[0x19] = opcode_map[0x18]
opcode_map[0x1A] = opcode_map[0x18]
opcode_map[0x1B] = opcode_map[0x18]
opcode_map[0x1C] = opcode_map[0x18]
opcode_map[0x1D] = opcode_map[0x18]

-- AND
opcode_map[0x20] = function(self, opcode)
    cpu_and(self, mrm6_table[band(opcode, 0x7)](self, opcode), opcode)
end
opcode_map[0x21] = opcode_map[0x20]
opcode_map[0x22] = opcode_map[0x20]
opcode_map[0x23] = opcode_map[0x20]
opcode_map[0x24] = opcode_map[0x20]
opcode_map[0x25] = opcode_map[0x20]

-- ES:
opcode_map[0x26] = function(self, opcode)
    self.segment_mode = 1
    local r = run_one(self, true, true)
    self.segment_mode = nil
    return r
end

-- CS:
opcode_map[0x2E] = function(self, opcode)
    self.segment_mode = 2
    local r = run_one(self, true, true)
    self.segment_mode = nil
    return r
end

-- SS:
opcode_map[0x36] = function(self, opcode)
    self.segment_mode = 3
    local r = run_one(self, true, true)
    self.segment_mode = nil
    return r
end

-- DS:
opcode_map[0x3E] = function(self, opcode)
    self.segment_mode = 4
    local r = run_one(self, true, true)
    self.segment_mode = nil
    return r
end

-- DAA
opcode_map[0x27] = function(self, opcode)
    local al = band(self.regs[1], 0xFF)
    local old_al = al
    local old_cf = (band(self.flags, 0x01) == 0x01)

    if (band(self.flags, 0x10) == 0x10) or (band(old_al, 0x0F) > 0x9) then
        al = al + 0x6
        cpu_write_flag(self, 0, old_cf or (al > 0xFF))
        self.flags = bor(self.flags, 0x10)
    else
        self.flags = band(self.flags, bnot(0x10))
    end

    if old_cf or (old_al > 0x99) then
        al = al + 0x60
        self.flags = bor(self.flags, 0x01)
    end

    self.regs[1] = bor(band(self.regs[1], 0xFF00), band(al, 0xFF))
    cpu_zsp(self, al, 0)
end

-- DAS
opcode_map[0x2F] = function(self, opcode)
    local al = band(self.regs[1], 0xFF)
    local old_al = al
    local old_cf = (band(self.flags, 0x01) == 0x01)

    if (band(self.flags, 0x10) == 0x10) or (band(old_al, 0xF) > 0x9) then
        al = al - 0x6
        cpu_write_flag(self, 0, old_cf or (al > 0xFF))
        self.flags = bor(self.flags, 0x10)
    else
        self.flags = band(self.flags, bnot(0x10))
    end

    if old_cf or (old_al > 0x99) then
        al = al - 0x60
        self.flags = bor(self.flags, 0x01)
    end

    self.regs[1] = bor(band(self.regs[1], 0xFF00), band(al, 0xFF))
    cpu_zsp(self, al, 0)
end

-- AAA
opcode_map[0x37] = function(self, opcode)
    local al = band(self.regs[1], 0xFF)

    if (band(self.flags, 0x10) == 0x10) or (band(al, 0xF) >= 0x9) then
        self.regs[1] = band(self.regs[1] + 0x106, 0xFFFF)
        self.flags = bor(self.flags, 0x01) -- Set CF
        self.flags = bor(self.flags, 0x10) -- Set AF
    else
        self.flags = band(self.flags, bnot(0x01)) -- Clear CF
        self.flags = band(self.flags, bnot(0x10)) -- Clear AF
    end

    self.regs[1] = band(self.regs[1], 0xFF0F)
end

-- AAS
opcode_map[0x3F] = function(self, opcode)
    local al = band(self.regs[1], 0xFF)

    if (band(self.flags, 0x10) ~= 0) or (band(al, 0x0F) >= 0x9) then
        self.regs[1] = band((self.regs[1] - 0x006), 0xFFFF)
        local ah = rshift(band(self.regs[1], 0xFF00), 8)
        ah = band((ah - 1), 0xFF)
        self.regs[1] = bor(band(self.regs[1], 0xFF), lshift(ah, 8))
        self.flags = bor(self.flags, 0x01) -- Set CF
        self.flags = bor(self.flags, 0x10) -- Set AF
    else
        self.flags = band(self.flags, bnot(0x01)) -- Clear CF
        self.flags = band(self.flags, bnot(0x10)) -- Clear AF
    end

    self.regs[1] = band(self.regs[1], 0xFF0F)
end

-- INC
opcode_map[0x40] = function(self, opcode)
    local reg = band(opcode, 0x7) + 1
    local val = self.regs[reg]
    val = band(val + 1, 0xFFFF)
    self.regs[reg] = val
    cpu_inc(self, val, 1)
end
opcode_map[0x41] = opcode_map[0x40]
opcode_map[0x42] = opcode_map[0x40]
opcode_map[0x43] = opcode_map[0x40]
opcode_map[0x44] = opcode_map[0x40]
opcode_map[0x45] = opcode_map[0x40]
opcode_map[0x46] = opcode_map[0x40]
opcode_map[0x47] = opcode_map[0x40]

-- DEC
opcode_map[0x48] = function(self, opcode)
    local reg = band(opcode, 0x7) + 1
    local val = self.regs[reg]
    val = band(val - 1, 0xFFFF)
    self.regs[reg] = val
    cpu_dec(self, val, 1)
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

-- SUB
opcode_map[0x28] = function(self, opcode)
    cpu_sub(self, mrm6_table[band(opcode, 0x7)](self, opcode), opcode)
end
opcode_map[0x29] = opcode_map[0x28]
opcode_map[0x2A] = opcode_map[0x28]
opcode_map[0x2B] = opcode_map[0x28]
opcode_map[0x2C] = opcode_map[0x28]
opcode_map[0x2D] = opcode_map[0x28]

-- XOR
opcode_map[0x30] = function(self, opcode)
    cpu_xor(self, mrm6_table[band(opcode, 0x7)](self, opcode), opcode)
end
opcode_map[0x31] = opcode_map[0x30]
opcode_map[0x32] = opcode_map[0x30]
opcode_map[0x33] = opcode_map[0x30]
opcode_map[0x34] = opcode_map[0x30]
opcode_map[0x35] = opcode_map[0x30]

-- CMP
opcode_map[0x38] = function(self, opcode)
    cpu_cmp_mrm(self, mrm6_table[band(opcode, 0x7)](self, opcode), opcode)
end
opcode_map[0x39] = opcode_map[0x38]
opcode_map[0x3A] = opcode_map[0x38]
opcode_map[0x3B] = opcode_map[0x38]
opcode_map[0x3C] = opcode_map[0x38]
opcode_map[0x3D] = opcode_map[0x38]

-- JMP
for i = 0x70, 0x7F, 1 do
    local cond = rel_jmp_conds[i - 0x6F]
    opcode_map[i] = function(self, opcode)
        local offset = advance_ip(self)
        if cond(self) then
            self.ip = band(self.ip + to_8(offset), 0xFFFF)
        end
    end
end

for i = 0, 15, 1 do
    opcode_map[0x60 + i] = opcode_map[0x70 + i]
end

local grp1_table = {
    [0] = cpu_add,
    [1] = cpu_or,
    [2] = function(self, a,b) cpu_add(self, a, b, true) end,
    [3] = function(self, a,b) cpu_sub(self, a, b, true) end,
    [4] = cpu_and,
    [5] = function(self, a,b) cpu_sub(self, a, b, false) end,
    [6] = cpu_xor,
    [7] = function(self, a,b) cpu_cmp_mrm(self, a, b) end
}

-- GRP1
opcode_map[0x80] = function(self, opcode)
    local mrm = cpu_mrm_copy(cpu_mod_rm(self, 0))
    local v = band(mrm.src, 0x07)
    mrm.src = 40
    mrm.imm = advance_ip(self)
    grp1_table[v](self, mrm, opcode)
end
opcode_map[0x81] = function(self, opcode)
    local mrm = cpu_mrm_copy(cpu_mod_rm(self, 1))
    local v = band(mrm.src, 0x07)
    mrm.src = 41
    mrm.imm = advance_ip16(self)
    grp1_table[v](self, mrm, opcode)
end
opcode_map[0x82] = function(self, opcode)
    local mrm = cpu_mrm_copy(cpu_mod_rm(self, 0))
    local v = band(mrm.src, 0x07)
    mrm.src = 40
    mrm.imm = advance_ip(self)
    grp1_table[v](self, mrm, opcode)
end
opcode_map[0x83] = function(self, opcode)
    local mrm = cpu_mrm_copy(cpu_mod_rm(self, 1))
    local v = band(mrm.src, 0x07)
    mrm.src = 41
    mrm.imm = band(to_8(advance_ip(self)), 0xFFFF)
    grp1_table[v](self, mrm, opcode)
end

-- TEST
opcode_map[0x84] = function(self, opcode) cpu_test(self, cpu_mod_rm(self, 0), opcode) end
opcode_map[0x85] = function(self, opcode) cpu_test(self, cpu_mod_rm(self, 1), opcode) end

-- XCHG
opcode_map[0x86] = function(self, opcode)
    local mrm = cpu_mod_rm(self, band(opcode, 0x01))
    local t = cpu_read_rm(self, mrm, mrm.src)
    cpu_write_rm(self, mrm, mrm.src, cpu_read_rm(self, mrm, mrm.dst))
    cpu_write_rm(self, mrm, mrm.dst, t)
end
opcode_map[0x87] = opcode_map[0x86]

-- MOV mod/rm
opcode_map[0x88] = function(self, opcode) cpu_mov(self, cpu_mod_rm(self, 0)) end
opcode_map[0x89] = function(self, opcode) cpu_mov(self, cpu_mod_rm(self, 1)) end
opcode_map[0x8A] = function(self, opcode) cpu_mov(self, cpu_mod_rm(self, 2)) end
opcode_map[0x8B] = function(self, opcode) cpu_mov(self, cpu_mod_rm(self, 3)) end

-- MOV rm, seg
opcode_map[0x8C] = function(self, opcode)
    local mrm = cpu_mod_rm(self, opcode, 1024)
    cpu_mov(self, mrm)
    if mrm.dst == 28 then
        return run_one(self, true, true)
    end
end
opcode_map[0x8E] = opcode_map[0x8C]

-- LEA
opcode_map[0x8D] = function(self, opcode)
    local mrm = cpu_mod_rm(self, 3)
    cpu_write_rm(self, mrm, mrm.dst, cpu_addr_rm(self, mrm, mrm.src))
end

-- POPW
opcode_map[0x8F] = function(self, opcode)
    local mrm = cpu_mod_rm(self, 1)
    cpu_write_rm(self, mrm, mrm.dst, cpu_pop16(self))
end

-- XCHG
opcode_map[0x91] = function(self, opcode) local v = self.regs[2]; self.regs[2] = self.regs[1]; self.regs[1] = v; end
opcode_map[0x92] = function(self, opcode) local v = self.regs[3]; self.regs[3] = self.regs[1]; self.regs[1] = v; end
opcode_map[0x93] = function(self, opcode) local v = self.regs[4]; self.regs[4] = self.regs[1]; self.regs[1] = v; end
opcode_map[0x94] = function(self, opcode) local v = self.regs[5]; self.regs[5] = self.regs[1]; self.regs[1] = v; end
opcode_map[0x95] = function(self, opcode) local v = self.regs[6]; self.regs[6] = self.regs[1]; self.regs[1] = v; end
opcode_map[0x96] = function(self, opcode) local v = self.regs[7]; self.regs[7] = self.regs[1]; self.regs[1] = v; end
opcode_map[0x97] = function(self, opcode) local v = self.regs[8]; self.regs[8] = self.regs[1]; self.regs[1] = v; end

-- CBW
opcode_map[0x98] = function(self, opcode)
    local v = band(self.regs[1], 0xFF)

    if v >= 0x80 then
        v = bor(v, 0xFF00)
    end

    self.regs[1] = v
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
    local new_ip = advance_ip16(self)
    local new_cs = advance_ip16(self)

    cpu_push16(self, self.segments[2])
    cpu_push16(self, self.ip)

    self.ip = new_ip
    self.segments[2] = new_cs
end

-- PUSHF
opcode_map[0x9C] = function(self, opcode) cpu_push16(self, self.flags) end

-- POPF
opcode_map[0x9D] = function(self, opcode) self.flags = bor(cpu_pop16(self), 0xF002) end

-- SAHF
opcode_map[0x9E] = function(self, opcode)
    self.flags = bor(band(self.flags, 0xFF00), rshift(band(self.regs[1], 0xFF00), 8))
end

-- LAHF
opcode_map[0x9F] = function(self, opcode)
    self.regs[1] = bor(band(self.regs[1], 0xFF), lshift(band(self.flags, 0xFF), 8))
end

-- MOV offs->AL
opcode_map[0xA0] = function(self, opcode)
    local addr = advance_ip16(self)
    self.regs[1] = bor(band(self.regs[1], 0xFF00), self.memory[lshift(self.segments[(self.segment_mode or 4)], 4) + addr])
end

-- MOV offs->AX
opcode_map[0xA1] = function(self, opcode)
    local addr = advance_ip16(self)
    self.regs[1] = self.memory:r16(lshift(self.segments[self.segment_mode or 4], 4) + addr)
end

-- MOV AL->offs
opcode_map[0xA2] = function(self, opcode)
    local addr = advance_ip16(self)
    self.memory[lshift(self.segments[self.segment_mode or 4], 4) + addr] = band(self.regs[1], 0xFF)
end

-- MOV AX->offs
opcode_map[0xA3] = function(self, opcode)
    local addr = advance_ip16(self)
    self.memory:w16(lshift(self.segments[self.segment_mode or 4], 4) + addr, self.regs[1])
end

-- MOVSB/MOVSW
opcode_map[0xA4] = function(self, opcode)
    local addr_src = lshift(self.segments[self.segment_mode or 4], 4) + self.regs[7]
    local addr_dst = lshift(self.segments[1], 4) + self.regs[8]

    self.memory[addr_dst] = self.memory[addr_src]
    cpu_incdec_dir(self, 7, 1)
    cpu_incdec_dir(self, 8, 1)
end

opcode_map[0xA5] = function(self, opcode)
    local addr_src = lshift(self.segments[self.segment_mode or 4], 4) + self.regs[7]
    local addr_dst = lshift(self.segments[1], 4) + self.regs[8]

    self.memory:w16(addr_dst, self.memory:r16(addr_src))
    cpu_incdec_dir(self, 7, 2)
    cpu_incdec_dir(self, 8, 2)
end

-- CMPSB/CMPSW
opcode_map[0xA6] = function(self, opcode)
    local addr_src = lshift(self.segments[self.segment_mode or 4], 4) + self.regs[7]
    local addr_dst = lshift(self.segments[1], 4) + self.regs[8]

    cpu_cmp(self, self.memory[addr_src], self.memory[addr_dst], opcode)
    cpu_incdec_dir(self, 7, 1)
    cpu_incdec_dir(self, 8, 1)
end
opcode_map[0xA7] = function(self, opcode)
    local addr_src = lshift(self.segments[self.segment_mode or 4], 4) + self.regs[7]
    local addr_dst = lshift(self.segments[1], 4) + self.regs[8]

    cpu_cmp(self, self.memory:r16(addr_src), self.memory:r16(addr_dst), opcode)
    cpu_incdec_dir(self, 7, 2)
    cpu_incdec_dir(self, 8, 2)
end

-- TEST AL, imm8
opcode_map[0xA8] = function(self, opcode)
    cpu_uf_bit(self, band(band(self.regs[1], advance_ip(self)), 0xFF), 0)
end
-- TEST AX, imm16
opcode_map[0xA9] = function(self, opcode)
    cpu_uf_bit(self, band(self.regs[1], advance_ip16(self)), 1)
end

-- STOSB/STOSW
opcode_map[0xAA] = function(self, opcode)
    local addr_dst = lshift(self.segments[1], 4) + self.regs[8]

    self.memory[addr_dst] = band(self.regs[1], 0xFF)
    cpu_incdec_dir(self, 8, 1)
end
opcode_map[0xAB] = function(self, opcode)
    local addr_dst = lshift(self.segments[1], 4) + self.regs[8]

    self.memory:w16(addr_dst, self.regs[1])
    cpu_incdec_dir(self, 8, 2)
end

-- LODSB/LODSW
opcode_map[0xAC] = function(self, opcode)
    local addr_src = lshift(self.segments[self.segment_mode or 4], 4) + self.regs[7]

    self.regs[1] = bor(band(self.regs[1], 0xFF00), self.memory[addr_src])
    cpu_incdec_dir(self, 7, 1)
end
opcode_map[0xAD] = function(self, opcode)
    local addr_src = lshift(self.segments[self.segment_mode or 4], 4) + self.regs[7]

    self.regs[1] = self.memory:r16(addr_src)
    cpu_incdec_dir(self, 7, 2)
end

-- SCASB/SCASW
opcode_map[0xAE] = function(self, opcode)
    local addr_dst = lshift(self.segments[1], 4) + self.regs[8]

    cpu_cmp(self, band(self.regs[1], 0xFF), self.memory[addr_dst], opcode)
    cpu_incdec_dir(self, 8, 1)
end
opcode_map[0xAF] = function(self, opcode)
    local addr_dst = lshift(self.segments[1], 4) + self.regs[8]

    cpu_cmp(self, self.regs[1], self.memory:r16(addr_dst), opcode)
    cpu_incdec_dir(self, 8, 2)
end

-- MOV imm8
opcode_map[0xB0] = function(self, opcode) self.regs[1] = bor(band(self.regs[1], 0xFF00), (advance_ip(self))) end
opcode_map[0xB1] = function(self, opcode) self.regs[2] = bor(band(self.regs[2], 0xFF00), (advance_ip(self))) end
opcode_map[0xB2] = function(self, opcode) self.regs[3] = bor(band(self.regs[3], 0xFF00), (advance_ip(self))) end
opcode_map[0xB3] = function(self, opcode) self.regs[4] = bor(band(self.regs[4], 0xFF00), (advance_ip(self))) end
opcode_map[0xB4] = function(self, opcode) self.regs[1] = bor(band(self.regs[1], 0xFF), lshift(advance_ip(self), 8)) end
opcode_map[0xB5] = function(self, opcode) self.regs[2] = bor(band(self.regs[2], 0xFF), lshift(advance_ip(self), 8)) end
opcode_map[0xB6] = function(self, opcode) self.regs[3] = bor(band(self.regs[3], 0xFF), lshift(advance_ip(self), 8)) end
opcode_map[0xB7] = function(self, opcode) self.regs[4] = bor(band(self.regs[4], 0xFF), lshift(advance_ip(self), 8)) end

-- MOV imm16
opcode_map[0xB8] = function(self, opcode) self.regs[1] = advance_ip16(self) end
opcode_map[0xB9] = function(self, opcode) self.regs[2] = advance_ip16(self) end
opcode_map[0xBA] = function(self, opcode) self.regs[3] = advance_ip16(self) end
opcode_map[0xBB] = function(self, opcode) self.regs[4] = advance_ip16(self) end
opcode_map[0xBC] = function(self, opcode) self.regs[5] = advance_ip16(self) end
opcode_map[0xBD] = function(self, opcode) self.regs[6] = advance_ip16(self) end
opcode_map[0xBE] = function(self, opcode) self.regs[7] = advance_ip16(self) end
opcode_map[0xBF] = function(self, opcode) self.regs[8] = advance_ip16(self) end

-- RET near + pop
opcode_map[0xC2] = function(self, opcode)
    local btp = advance_ip16(self)
    self.ip = cpu_pop16(self)
    self.regs[5] = self.regs[5] + btp
end

-- RET near
opcode_map[0xC3] = function(self, opcode)
    self.ip = cpu_pop16(self)
end

-- LES/LDS
opcode_map[0xC4] = function(self, opcode)
    local mrm = cpu_mod_rm(self, 3)
    local addr = cpu_addr_rm(self, mrm, mrm.src)
    local defseg = cpu_seg_rm(self, mrm, mrm.src)

    cpu_write_rm(self, mrm, mrm.dst, self.memory:r16(lshift(self.segments[self.segment_mode or (defseg + 1)], 4) + addr))

    if opcode == 0xC5 then
        self.segments[4] = self.memory:r16((lshift(self.segments[(self.segment_mode or (defseg + 1))], 4) + (addr + 2)))
    else
        self.segments[1] = self.memory:r16((lshift(self.segments[(self.segment_mode or (defseg + 1))], 4) + (addr + 2)))
    end
end
opcode_map[0xC5] = opcode_map[0xC4]

-- MOV imm(rm)
opcode_map[0xC6] = function(self, opcode)
    local mrm = cpu_mod_rm(self, 0)
    cpu_write_rm(self, mrm, mrm.dst, advance_ip(self))
end
opcode_map[0xC7] = function(self, opcode)
    local mrm = cpu_mod_rm(self, 1)
    cpu_write_rm(self, mrm, mrm.dst, advance_ip16(self))
end

-- RET far + pop
opcode_map[0xCA] = function(self, opcode)
    local btp = advance_ip16(self)
    self.ip = cpu_pop16(self)
    self.segments[2] = cpu_pop16(self)
    self.regs[5] = self.regs[5] + btp
end

-- RET far
opcode_map[0xCB] = function(self, opcode)
    self.ip = cpu_pop16(self)
    self.segments[2] = cpu_pop16(self)
end

-- INT 3
opcode_map[0xCC] = function(self, opcode)
    self:emit_interrupt(0x03, false)
end

-- INT imm
opcode_map[0xCD] = function(self, opcode)
    cpu_int(self, advance_ip(self))
end

-- INTO
opcode_map[0xCE] = function(self, opcode)
    if band(self.flags, 0x800) ~= 0 then
        cpu_int(self, 4)
    end
end

-- IRET far
opcode_map[0xCF] = function(self, opcode)
    self.ip = cpu_pop16(self)
    self.segments[2] = cpu_pop16(self)
    self.flags = bor(cpu_pop16(self), 0x0002)
end

local grp2_table = {
    function(self, a,b) cpu_rotate(self, a, b, 1) end,
    function(self, a,b) cpu_rotate(self, a, b, 0) end,
    function(self, a,b) cpu_rotate(self, a, b, 3) end,
    function(self, a,b) cpu_rotate(self, a, b, 2) end,
    cpu_shl,
    cpu_shr,
    cpu_shl,
    function(self, a,b) cpu_shr(self, a, b, true) end
}

-- GRP2
opcode_map[0xD0] = function(self, opcode)
    local mrm = cpu_mrm_copy(cpu_mod_rm(self, band(opcode, 0x01)))
    local v = band(mrm.src, 0x07) + 1
    mrm.src = 40
    mrm.imm = 1
    grp2_table[v](self, mrm, opcode)
end
opcode_map[0xD2] = function(self, opcode)
    local mrm = cpu_mrm_copy(cpu_mod_rm(self, band(opcode, 0x01)))
    local v = band(mrm.src, 0x07) + 1
    mrm.src = 17
    grp2_table[v](self, mrm,opcode)
end

opcode_map[0xD1] = opcode_map[0xD0]
opcode_map[0xD3] = opcode_map[0xD2]

-- AAM
opcode_map[0xD4] = function(self, opcode)
    local base = advance_ip(self)
    local old_al = band(self.regs[1], 0xFF)
    local ah = math.floor(old_al / base)
    local al = old_al % base
    self.regs[1] = bor(lshift(band(ah, 0xFF), 8), band(al, 0xFF))
    cpu_zsp(self, al, 0)
end

-- AAD
opcode_map[0xD5] = function(self, opcode)
    local base = advance_ip(self)
    local old_al = band(self.regs[1], 0xFF)
    local old_ah = band(rshift(self.regs[1], 8), 0xFF)
    self.regs[1] = band(old_al + (old_ah * base), 0xFF)
    cpu_zsp(self, self.regs[1], 0)
end

-- SALC
opcode_map[0xD6] = function(self, opcode)
    if (band(self.flags, 0x01) ~= 0) then
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

-- LOOPNZ r8
opcode_map[0xE0] = function(self, opcode)
    local offset = to_8(advance_ip(self))
    self.regs[2] = self.regs[2] - 1

    if (self.regs[2] ~= 0) and (band(self.flags, 0x40) == 0) then
        self.ip = band((self.ip + offset), 0xFFFF)
    end
end

-- LOOPZ r8
opcode_map[0xE1] = function(self, opcode)
    local offset = to_8(advance_ip(self))
    self.regs[2] = self.regs[2] - 1

    if self.regs[2] ~= 0 and (band(self.flags, 0x40) ~= 0) then
        self.ip = band(self.ip + offset, 0xFFFF)
    end
end

-- LOOP r8
opcode_map[0xE2] = function(self, opcode)
    local offset = to_8(advance_ip(self))
    self.regs[2] = self.regs[2] - 1

    if self.regs[2] ~= 0 then
        self.ip = band(self.ip + offset, 0xFFFF)
    end
end

-- JCXZ r8
opcode_map[0xE3] = function(self, opcode)
    local offset = to_8(advance_ip(self))

    if self.regs[2] == 0 then
        self.ip = band(self.ip + offset, 0xFFFF)
    end
end

-- IN AL, Ib
opcode_map[0xE4] = function(self, opcode)
    self.regs[1] = bor(band(self.regs[1], 0xFF00), band(cpu_in(self, advance_ip(self)), 0xFF))
end

-- IN AX, Ib
opcode_map[0xE5] = function(self, opcode)
    self.regs[1] = band(cpu_in(self, advance_ip(self)), 0xFFFF)
end

-- OUT AL, Ib
opcode_map[0xE6] = function(self, opcode)
    cpu_out(self, advance_ip(self), band(self.regs[1], 0xFF))
end

-- OUT AX, Ib
opcode_map[0xE7] = function(self, opcode)
    cpu_out(self, advance_ip(self), self.regs[1])
end

-- CALL rel16
opcode_map[0xE8] = function(self, opcode)
    local offset = to_16(advance_ip16(self))
    cpu_push16(self, self.ip)
    self.ip = band(self.ip + offset, 0xFFFF)
end

-- JMP rel16
opcode_map[0xE9] = function(self, opcode)
    local offset = to_16(advance_ip16(self))
    self.ip = band(self.ip + offset, 0xFFFF)
end

-- JMP ptr
opcode_map[0xEA] = function(self, opcode)
    local new_ip = advance_ip16(self)
    local new_cs = advance_ip16(self)
    self.ip = new_ip
    self.segments[2] = new_cs
end

-- JMP r8
opcode_map[0xEB] = function(self, opcode)
    local offset = to_8(advance_ip(self))
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
    if not cpu_rep(self, function() return not (band(self.flags, 0x40) ~= 0) end) then
        return false
    end
end

-- REPZ
opcode_map[0xF3] = function(self, opcode)
    if not cpu_rep(self, function() return (band(self.flags, 0x40) ~= 0) end) then
        return false
    end
end

-- HLT
opcode_map[0xF4] = function(self, opcode)
    self.halted = true
end

-- CMC
opcode_map[0xF5] = function(self, opcode)
    self.flags = bxor(self.flags, 0x01)
end

-- GRP3
local grp3_table = {
    [0] = function(self, mrm, opcode)
        mrm = cpu_mrm_copy(mrm)
        if opcode == 0xF7 then
            mrm.src = 41
            mrm.imm = advance_ip16(self)
        else
            mrm.src = 40
            mrm.imm = advance_ip(self)
        end

        cpu_test(self, mrm, opcode)
    end,
    [1] = function()
        logger:error("i8086: Invalid opcode: GRP3/1")
    end,
    [2] = function(self, mrm, opcode) -- GRP3/NOT
        if opcode == 0xF7 then
            cpu_write_rm(self, mrm, mrm.dst, bxor(cpu_read_rm(self, mrm, mrm.dst), 0xFFFF))
        else
            cpu_write_rm(self, mrm, mrm.dst, bxor(cpu_read_rm(self, mrm, mrm.dst), 0xFF))
        end
    end,
    [3] = function(self, mrm, opcode) -- -- GRP3/NEG
        local src = cpu_read_rm(self, mrm, mrm.dst)
        local result = 0

        if opcode == 0xF7 then
            result = band((bxor(src, 0xFFFF) + 1), 0xFFFF)
            cpu_write_flag(self, 11, src == 0x8000)
        else
            result = band((bxor(src, 0xFF) + 1), 0xFF)
            cpu_write_flag(self, 11, src == 0x80)
        end

        cpu_write_rm(self, mrm, mrm.dst, result)
        cpu_write_flag(self, 0, src ~= 0)
        cpu_write_flag(self, 4, band(bxor(src, result), 0x10) ~= 0)
        cpu_zsp(self, result, opcode)
    end,
    [4] = cpu_mul,
    [5] = cpu_imul,
    [6] = cpu_div,
    [7] = cpu_idiv
}

opcode_map[0xF6] = function(self, opcode)
    local mrm = cpu_mod_rm(self, band(opcode, 0x01))
    local v = band(mrm.src, 0x07)
    if v >= 4 then
        mrm = cpu_mrm_copy(mrm)
        if opcode == 0xF7 then
            mrm.src = 0
        else
            mrm.src = 16
        end
    end
    grp3_table[v](self, mrm, opcode)
end
opcode_map[0xF7] = opcode_map[0xF6]

-- Flag setters
opcode_map[0xF8] = function(self, opcode) self.flags = band(self.flags, bnot(0x01)) end -- CF
opcode_map[0xF9] = function(self, opcode) self.flags = bor(self.flags, 0x01) end

opcode_map[0xFA] = function(self, opcode) self.flags = band(self.flags, bnot(0x200)) end -- IF
opcode_map[0xFB] = function(self, opcode) self.flags = bor(self.flags, 0x200) end

opcode_map[0xFC] = function(self, opcode) self.flags = band(self.flags, bnot(0x400)) end -- DF
opcode_map[0xFD] = function(self, opcode) self.flags = bor(self.flags, 0x400) end

-- GRP4
opcode_map[0xFE] = function(self, opcode)
    local mrm = cpu_mod_rm(self, 0)
    local val = band(mrm.src, 0x07)

    if val == 0 then -- INC
        local v = band((cpu_read_rm(self, mrm, mrm. dst) + 1), 0xFF)
        cpu_write_rm(self, mrm, mrm.dst, v)
        cpu_inc(self, v, 0)
    elseif val == 1 then -- DEC
        local v = band((cpu_read_rm(self, mrm, mrm.dst) - 1), 0xFF)
        cpu_write_rm(self, mrm, mrm.dst, v)
        cpu_dec(self, v, 0)
    end
end

-- GRP5
opcode_map[0xFF] = function(self, opcode)
    local mrm = cpu_mod_rm(self, 1)
    local val = band(mrm.src, 0x07)

    if val == 0 then -- INC
        local v = band((cpu_read_rm(self, mrm,mrm.dst) + 1), 0xFFFF)
        cpu_write_rm(self, mrm,mrm.dst,v)
        cpu_inc(self, v, 1)
    elseif val == 1 then -- DEC
        local v = band((cpu_read_rm(self, mrm,mrm.dst) - 1), 0xFFFF)
        cpu_write_rm(self, mrm,mrm.dst,v)
        cpu_dec(self, v, 1)
    elseif val == 2 then -- CALL near abs
        local new_ip = cpu_read_rm(self, mrm,mrm.dst)
        cpu_push16(self, self.ip)
        self.ip = new_ip
    elseif val == 3 then -- CALL far abs
        local addr = (lshift(self.segments[(self.segment_mode or (cpu_seg_rm(self, mrm,mrm.dst)+1))], 4) + (cpu_addr_rm(self, mrm,mrm.dst)))
        local new_ip = self.memory:r16(addr)
        local new_cs = self.memory:r16(addr+2)
        cpu_push16(self, self.segments[2])
        cpu_push16(self, self.ip)
        self.ip = new_ip
        self.segments[2] = new_cs
    elseif val == 4 then -- JMP near abs
        self.ip = cpu_read_rm(self, mrm,mrm.dst)
    elseif val == 5 then -- JMP far
        local addr = (lshift(self.segments[(self.segment_mode or (cpu_seg_rm(self, mrm,mrm.dst)+1))], 4) + (cpu_addr_rm(self, mrm,mrm.dst)))
        local new_ip = self.memory:r16(addr)
        local new_cs = self.memory:r16(addr+2)
        self.ip = new_ip
        self.segments[2] = new_cs
    elseif val == 6 then
        cpu_push16(self, cpu_read_rm(self, mrm,mrm.dst))
    end
end

-- 8087 FPU
opcode_map[0x9B] = function(self, opcode) end
for i = 0xD8, 0xDF, 1 do
    opcode_map[i] = function(self, opcode) cpu_mod_rm(self, 1) end
end

opcode_map[0xC0] = opcode_map[0xC2]
opcode_map[0xC1] = opcode_map[0xC3]
opcode_map[0xC8] = opcode_map[0xCA]
opcode_map[0xC9] = opcode_map[0xCB]

run_one = function(self)
    if self.hasint then
        local intr = self.intqueue[1]
        if intr ~= nil then
            if intr >= 256 or (band(self.flags, 0x0200) ~= 0) then
                table.remove(self.intqueue, 1)
                cpu_int(self, band(intr, 0xFF))
                if #self.intqueue == 0 then
                    self.hasint = false
                end
            end
        end
    end

    if (band(self.ip, 0xFF00) == 0x1100) and (self.segments[2] == 0xF000) then
        self.flags = bor(self.flags, 0x0200)
        local intr = cpu_int_fake(self, band(self.ip, 0xFF))

        if intr ~= -1 then
            self.ip = cpu_pop16(self)
            self.segments[2] = cpu_pop16(self)
            local old_flags = cpu_pop16(self)
            self.flags = bor(band(self.flags, bnot(0x0200)), band(old_flags, 0x0200))
            return true
        else
            return false
        end
    end

    -- if self.halted then
    --     return -1
    -- end

    local opcode = advance_ip(self)
    local om = opcode_map[opcode]

    -- logger:debug("i8086: Opcode %02X", opcode)

    if om ~= nil then
        local result = om(self, opcode)
        if result ~= nil then
            return result
        else
            return true
        end
    else
        logger:error("i8086: Unknown opcode: %02X", opcode)
        emit_interrupt(self, 6, false)
        return false
    end
end

local cpu = {}

local function reset(self)
    for i = 1, 8, 1 do
        self.regs[i] = 0
    end

    for i = 1, 8, 1 do
        self.segments[i] = 0
    end

    for i, _ in pairs(self.intqueue) do
        self.intqueue[i] = nil
    end

    self.ip = 0
    self.halted = false
    self.flags = 0
    self.segment_mode = nil
    self.hasint = false
end

local function save(self, stream)
    stream:write_bytes(bit_converter.uint32_to_bytes(30, "LE"))
    for i = 1, #self.regs, 1 do
        stream:write_bytes(bit_converter.uint16_to_bytes(self.regs[i], "BE"))
    end

    for i = 1, 4, 1 do
        stream:write_bytes(bit_converter.uint16_to_bytes(self.segments[i], "BE"))
    end

    stream:write_bytes(bit_converter.uint16_to_bytes(self.ip, "BE")) -- IP
    stream:write_bytes(bit_converter.uint16_to_bytes(self.flags, "BE")) -- Flags
    stream:write(self.hasint and 1 or 0) -- Interrupt
    stream:write(self.segment_mode or 0) -- Segment mode
end

local function load(self, data)
    self.regs[1] = bit_converter.bytes_to_uint16({data[1], data[2]}, "BE")
    self.regs[2] = bit_converter.bytes_to_uint16({data[3], data[4]}, "BE")
    self.regs[3] = bit_converter.bytes_to_uint16({data[5], data[6]}, "BE")
    self.regs[4] = bit_converter.bytes_to_uint16({data[7], data[8]}, "BE")
    self.regs[5] = bit_converter.bytes_to_uint16({data[9], data[10]}, "BE")
    self.regs[6] = bit_converter.bytes_to_uint16({data[11], data[12]}, "BE")
    self.regs[7] = bit_converter.bytes_to_uint16({data[13], data[14]}, "BE")
    self.regs[8] = bit_converter.bytes_to_uint16({data[15], data[16]}, "BE")

    self.segments[1] = bit_converter.bytes_to_uint16({data[17], data[18]}, "BE")
    self.segments[2] = bit_converter.bytes_to_uint16({data[19], data[20]}, "BE")
    self.segments[3] = bit_converter.bytes_to_uint16({data[21], data[22]}, "BE")
    self.segments[4] = bit_converter.bytes_to_uint16({data[23], data[24]}, "BE")

    self.ip = bit_converter.bytes_to_uint16({data[25], data[26]}, "BE") -- IP
    self.flags = bit_converter.bytes_to_uint16({data[27], data[28]}, "BE") -- Flags
    self.hasint = data[29] == 1 -- Interrupt

    if data[30] == 0 then
        self.segment_mode = nil -- Segment mode
    else
        self.segment_mode = data[30] -- Segment mode
    end
end

function cpu.new(memory)
    local self = {
        regs = {0, 0, 0, 0, 0, 0, 0, 0}, -- AX, CX, DX, BX, SP, BP, SI, DI
        segments = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, -- ES, CS, SS, DS, FS, GS

        flags = 0,
        ip = 0,
        hasint = false,
        segment_mode = nil,
        halted = false,
        memory = memory,
        intqueue = {},
        interrupt_handlers = {},
        io_ports = {},
        run_one = run_one,
        register_interrupt_handler = register_interrupt_handler,
        emit_interrupt = emit_interrupt,
        port_get = port_get,
        port_set = port_set,
        set_ip = cpu_set_ip,
        write_flag = cpu_write_flag,
        set_flag = cpu_set_flag,
        clear_flag = cpu_clear_flag,
        seg = seg,
        out_port = out_port,
        in_port = in_port,
        reset = reset,
        save = save,
        load = load
    }

    return self
end

return cpu