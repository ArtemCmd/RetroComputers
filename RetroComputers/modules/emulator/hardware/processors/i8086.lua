-- TODO: Rewrite
-- AAAAAAAAAAAAAAAAAAAAAAAAAAAAAaa govnokod
local logger = require("retro_computers:logger")

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot
local io_ports = {}
local run_one = function (self, a, b) end

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
    return lshift(self.segments[s+1], 4) + v
end

local function segmd(self, s, v)
    return lshift(self.segments[(self.segment_mode or (s+1))], 4) + v
end

local function advance_ip(self)
    local ip = (lshift(self.segments[(self.seg_cs)+1], 4)+(self.ip))
    self.ip = band(self.ip + 1, 0xFFFF)
    return self.memory[ip]
end

local function advance_ip16(self)
    local ip = (lshift(self.segments[(self.seg_cs)+1], 4)+(self.ip))
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

local function cpu_flag(self, t)
    return band(self.flags, lshift(1, t)) ~= 0
end


local function cpu_clear_flag(self, t)
    self.flags = band(self.flags, bxor(self.flags, lshift(1, t)))
end


local function cpu_set_flag(self, t)
    self.flags = bor(self.flags, lshift(1, t))
end


local function cpu_write_flag(self, t, v)
    if v then
        self.flags = bor(self.flags, lshift(1, t))
    else
        self.flags = band(self.flags, bxor(self.flags, lshift(1, t)))
    end
end

local function cpu_complement_flag(self, t)
    self.flags = bxor(self.flags, lshift(1, t))
end

local function cpu_incdec_dir(self, t, amount)
    if (band(self.flags, lshift(1, (10))) ~= 0) then
        self.regs[t] = band(self.regs[t] - amount, 0xFFFF)
    else
        self.regs[t] = band(self.regs[t] + amount, 0xFFFF)
    end
end

local function cpu_set_ip(self, cs, ip)
    self.segments[2] = cs
    self.ip = ip
end

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

local function cpu_seg_rm(self, data, v)
    if v >= 8 and v < 16 then
        return self.rm_seg_t[(v - 7)]
    elseif v >= 32 and v < 40 then
        return self.rm_seg_t[(v - 31)]
    else
        return self.seg_ds
    end
end

local function cpu_addr_rm(self, data, v)
    if v >= 8 and v < 16 then
        return cpu_rm_addr[(v - 7)](self, data)
    elseif v >= 24 and v <= 25 then
        return data.disp
    elseif v >= 32 and v < 40 then
        return cpu_rm_addr[(v - 31)](self, data)
    else
        return 0xFF
    end
end

local readrm_table = {}
readrm_table[0] = function(self, data, v) return self.regs[1] end
readrm_table[1] = function(self, data, v) return self.regs[2] end
readrm_table[2] = function(self, data, v) return self.regs[3] end
readrm_table[3] = function(self, data, v) return self.regs[4] end
readrm_table[4] = function(self, data, v) return self.regs[5] end
readrm_table[5] = function(self, data, v) return self.regs[6] end
readrm_table[6] = function(self, data, v) return self.regs[7] end
readrm_table[7] = function(self, data, v) return self.regs[8] end
for i=8,15 do readrm_table[i] = function(self, data, v)
    return self.memory:r16((lshift(self.segments[(self.segment_mode or (self.rm_seg_t[(v - 7)]+1))], 4) + (cpu_rm_addr[(v - 7)](self, (data)))))
end end
readrm_table[16] = function(self, data, v) return band(self.regs[1], 0xFF) end
readrm_table[17] = function(self, data, v) return band(self.regs[2], 0xFF) end
readrm_table[18] = function(self, data, v) return band(self.regs[3], 0xFF) end
readrm_table[19] = function(self, data, v) return band(self.regs[4], 0xFF) end
readrm_table[20] = function(self, data, v) return rshift(self.regs[1], 8) end
readrm_table[21] = function(self, data, v) return rshift(self.regs[2], 8) end
readrm_table[22] = function(self, data, v) return rshift(self.regs[3], 8) end
readrm_table[23] = function(self, data, v) return rshift(self.regs[4], 8) end
readrm_table[24] = function(self, data, v) return self.memory[(lshift(self.segments[(self.segment_mode or (4))], 4) + (data.disp))] end
readrm_table[25] = function(self, data, v) return self.memory:r16((lshift(self.segments[(self.segment_mode or (4))], 4) + (data.disp))) end
for i=26,31 do readrm_table[i] = function(self, data, v)
    return self.segments[v - 25]
end end
for i=32,39 do readrm_table[i] = function(self, data, v)
    return self.memory[(lshift(self.segments[(self.segment_mode or (self.rm_seg_t[(v - 31)]+1))], 4) + (cpu_rm_addr[(v - 31)](self, (data))))]
end end
readrm_table[40] = function(self, data, v) return band(data.imm, 0xFF) end
readrm_table[41] = function(self, data, v) return data.imm end

local function cpu_read_rm(self, data, v)
    return readrm_table[v](self, data, v)
end

local writerm_table = {}
writerm_table[0] = function(self, data, v, val) self.regs[1] = val end
writerm_table[1] = function(self, data, v, val) self.regs[2] = val end
writerm_table[2] = function(self, data, v, val) self.regs[3] = val end
writerm_table[3] = function(self, data, v, val) self.regs[4] = val end
writerm_table[4] = function(self, data, v, val) self.regs[5] = val end
writerm_table[5] = function(self, data, v, val) self.regs[6] = val end
writerm_table[6] = function(self, data, v, val) self.regs[7] = val end
writerm_table[7] = function(self, data, v, val) self.regs[8] = val end
for i=8,15 do writerm_table[i] = function(self, data, v, val)
 self.memory:w16((lshift(self.segments[(self.segment_mode or (self.rm_seg_t[(v - 7)]+1))], 4) + (cpu_rm_addr[(v - 7)](self, (data)))), val)
end end
writerm_table[16] = function(self, data, v, val) self.regs[1] = bor(band(self.regs[1], 0xFF00), band(val, 0xFF)) end
writerm_table[17] = function(self, data, v, val) self.regs[2] = bor(band(self.regs[2], 0xFF00), band(val, 0xFF)) end
writerm_table[18] = function(self, data, v, val) self.regs[3] = bor(band(self.regs[3], 0xFF00), band(val, 0xFF)) end
writerm_table[19] = function(self, data, v, val) self.regs[4] = bor(band(self.regs[4], 0xFF00), band(val, 0xFF)) end
writerm_table[20] = function(self, data, v, val) self.regs[1] = bor(band(self.regs[1], 0xFF), lshift(band(val, 0xFF), 8)) end
writerm_table[21] = function(self, data, v, val) self.regs[2] = bor(band(self.regs[2], 0xFF), lshift(band(val, 0xFF), 8)) end
writerm_table[22] = function(self, data, v, val) self.regs[3] = bor(band(self.regs[3], 0xFF), lshift(band(val, 0xFF), 8)) end
writerm_table[23] = function(self, data, v, val) self.regs[4] = bor(band(self.regs[4], 0xFF), lshift(band(val, 0xFF), 8)) end
writerm_table[24] = function(self, data, v, val)
 self.memory[(lshift(self.segments[(self.segment_mode or (4))], 4) + (data.disp))] = band(val, 0xFF)
end
writerm_table[25] = function(self, data, v, val)
    self.memory:w16((lshift(self.segments[(self.segment_mode or (4))], 4) + (data.disp)), val)
end
for i=26,31 do writerm_table[i] = function(self, data, v, val)
    self.segments[v - 25] = val
end end
for i=32,39 do writerm_table[i] = function(self, data, v, val)
    self.memory[(lshift(self.segments[(self.segment_mode or (self.rm_seg_t[(v - 31)]+1))], 4) + (cpu_rm_addr[(v - 31)](self, (data))))] = band(val, 0xFF)
end end
local function cpu_write_rm(self, data, v, val)
    writerm_table[v](self, data, v, val)
end

local mrm_table = {}
for i=0,2047 do
    local is_seg = band(i, 1024) ~= 0
    local mod = band(rshift(i, 6), 0x03)
    local reg = band(rshift(i, 3), 0x07)
    local rm = band(i, 0x07)
    local d = band(rshift(i, 9), 0x01)
    local w = band(rshift(i, 8), 0x01)
    if is_seg then w = 1 end

    local op1 = reg
    local op2 = rm

    if is_seg then
        op1 = (op1 % 6) + 26
    elseif w == 0 then
        op1 = op1 + 16
    end

    if mod == 0 and rm == 6 then
        op2 = 24 + w
    elseif mod ~= 3 then
        if w == 0 then
            op2 = op2 + 32
        else
            op2 = op2 + 8
        end
    else
        if w == 0 then
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
    mrm_table[i] = {src=src, dst=dst, cdisp=cdisp, disp=0}
end

local function cpu_mod_rm(self, opcode, is_seg)
    local modrm = bor(bor(advance_ip(self), lshift(band(opcode, 3), 8)), (is_seg or 0))
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
    return {src=data.src,dst=data.dst,disp=data.disp}
end

local mrm6_4 = {src=40,dst=16,imm=0}
local mrm6_5 = {src=41,dst=0,imm=0}

local mrm6_table = {
    [0]=cpu_mod_rm,
    [1]=cpu_mod_rm,
    [2]=cpu_mod_rm,
    [3]=cpu_mod_rm,
    [4]=function(self, v)
    mrm6_4.imm=advance_ip(self)
        return mrm6_4
    end,
    [5]=function(self, v)
    mrm6_5.imm=advance_ip16(self)
        return mrm6_5
    end,
    [6]=cpu_mod_rm,
    [7]=cpu_mod_rm
}

local function cpu_mod_rm6(opcode)
    local v = band(opcode, 0x07)
    return mrm6_table[v](v)
end

local parity_table = {}
for i = 0,255 do
    local p = 0
    local v = i
    while v ~= 0 do
        p = p + band(v, 1)
        v = rshift(v, 1)
    end
    if band(p, 1) == 0 then
        parity_table[i] = 4
    else
        parity_table[i] = 0
    end
end

local function cpu_write_parity(self, v)
    self.flags = band(self.flags, bor(0xFFFB, parity_table[band(v, 0xFF)]))
end

local function cpu_push16(self, value)
    self.regs[5] = band(self.regs[5] - 2, 0xFFFF)
    self.memory:w16((lshift(self.segments[(self.seg_ss)+1], 4)+(self.regs[5])), band(value, 0xFFFF))
end

local function cpu_pop16(self)
    local sp = self.regs[5]
    self.regs[5] = band(sp + 2, 0xFFFF)
    return self.memory:r16((lshift(self.segments[(self.seg_ss)+1], 4)+(sp)))
end

local function cpu_mov(self, mrm)
    local v1 = cpu_read_rm(self, mrm, mrm.src)
    cpu_write_rm(self, mrm, mrm.dst, v1)
end

local function cpu_zsp(self, vr, opc)
    if band(opc, 0x01) == 1 then
        cpu_write_flag(self, 6, band(vr, 0xFFFF) == 0)
        cpu_write_flag(self, 7, band(vr, 0x8000) ~= 0)
        self.flags = bor(band(self.flags, 0xFFFB), parity_table[band(vr, 0xFF)])
    else
        cpu_write_flag(self, 6, band(vr, 0xFF) == 0)
        cpu_write_flag(self, 7, band(vr, 0x80) ~= 0)
        self.flags = bor(band(self.flags, 0xFFFB), parity_table[band(vr, 0xFF)])
    end
end

local function cpu_inc(self, vr, opc)
    cpu_zsp(self, vr, opc)
    cpu_write_flag(self, 4, band(vr, 0xF) == 0x0)
    if band(opc, 0x01) == 1 then
        cpu_write_flag(self, 11, vr == 0x8000)
    else
        cpu_write_flag(self, 11, vr == 0x80)
    end
end

local function cpu_dec(self, vr, opc)
    cpu_zsp(self, vr, opc)
    cpu_write_flag(self, 4, band(vr, 0xF) == 0xF)
    if band(opc, 0x01) == 1 then
        cpu_write_flag(self, 11, vr == 0x7FFF)
    else
        cpu_write_flag(self, 11, vr == 0x7F)
    end
end

local function cpu_uf_add(self, v1, v2, vc, vr, opc)
    cpu_write_flag(self, 4, (band(v1, 0xF) + band(v2, 0xF) + vc) >= 0x10)
    if band(opc, 0x01) == 1 then
        cpu_write_flag(self, 0, band(vr, 0xFFFF) ~= vr)
        cpu_write_flag(self, 11, (band(v1, 0x8000) == band(v2, 0x8000)) and (band(vr, 0x8000) ~= band(v1, 0x8000)))
    else
        cpu_write_flag(self, 0, band(vr, 0xFF) ~= vr)
        cpu_write_flag(self, 11, (band(v1, 0x80) == band(v2, 0x80)) and (band(vr, 0x80) ~= band(v1, 0x80)))
    end
end

local function cpu_uf_sub(self, v1, v2, vb, vr, opc)
    cpu_write_flag(self, 4, (band(v2, 0xF) - band(v1, 0xF) - vb) < 0)
    if band(opc, 0x01) == 1 then
        cpu_write_flag(self, 0, band(vr, 0xFFFF) ~= vr)
        cpu_write_flag(self, 11, (band(v1, 0x8000) ~= band(v2, 0x8000)) and (band(vr, 0x8000) == band(v1, 0x8000)))
    else
        cpu_write_flag(self, 0, band(vr, 0xFF) ~= vr)
        cpu_write_flag(self, 11, (band(v1, 0x80) ~= band(v2, 0x80)) and (band(vr, 0x80) == band(v1, 0x80)))
    end
end

local function cpu_uf_bit(self, vr, opc)
    self.flags = band(self.flags, bnot(0x0801))
    cpu_zsp(self, vr, opc)
end

local cpu_shift_mask = 0xFF

local function cpu_shl(self, mrm, opcode)
    local v1 = band(cpu_read_rm(self, mrm, mrm.src), cpu_shift_mask)
    if v1 >= 1 then
        local v2 = cpu_read_rm(self, mrm, mrm.dst)
        local w = band(opcode, 0x01)
        local mask = 0xFFFF
        if w == 0 then mask = 0xFF end
        local msb = (rshift(mask, 1) + 1)

        local vr = lshift(v2, v1)
        cpu_write_flag(self, 0, band(vr, (mask + 1)) ~= 0)
        cpu_write_rm(self, mrm, mrm.dst, band(vr, mask))
        cpu_zsp(self, band(vr, mask), opcode)
        if v1 == 1 then
            local msb_result = band(vr, msb) ~= 0
            cpu_write_flag(self, 11, (band(self.flags, lshift(1, (0))) ~= 0) ~= msb_result)
        end
    end
end

local function cpu_shr(self, mrm, opcode, arith)
    local w = band(opcode, 0x01)
    local mask = 0x8000
    if w == 0 then mask = 0x80 end

    local v1 = band(cpu_read_rm(self, mrm, mrm.src), cpu_shift_mask)
    local v2 = cpu_read_rm(self, mrm, mrm.dst)
    local vr
    if (arith) then
        vr = v2
        local shift1 = v1
        while shift1 > 0 do
            vr = bor(band(vr, mask), band(rshift(vr, 1), (mask - 1)))
            shift1 = shift1 - 1
        end
    else
        vr = rshift(v2, v1)
    end
    cpu_write_rm(self, mrm, mrm.dst, vr)
    cpu_zsp(self, vr, opcode)

    if lshift(1, (band(v1, 0x1F) - 1)) > mask then
        cpu_write_flag(self, 0, arith and (band(v2, mask) ~= 0))
    else
        cpu_write_flag(self, 0, band(v2, lshift(1, (v1 - 1))) ~= 0)
    end
    if v1 == 1 then
        cpu_write_flag(self, 11, (not arith) and (band(v2, mask) ~= 0))
    end
end

-- Modes: 
-- 0 - ROR
-- 1 - ROL
-- 2 - RCR
-- 3 - RCL
local function cpu_rotate(self, mrm, opcode, mode)
    local w = band(opcode, 0x01)
    local shift = 15
    if w == 0 then shift = 7 end

    local v1 = band(cpu_read_rm(self, mrm, mrm.src), cpu_shift_mask)
    local v2 = cpu_read_rm(self, mrm, mrm.dst)
    local vr = v2
    local cf = 0
    local of = 0
    if (band(self.flags, lshift(1, (0))) ~= 0) then cf = 1 end

    local shifts = v1
    if shifts > 0 then
        if mode == 0 then
            shifts = band(shifts, shift)
            local shiftmask = lshift(1, shifts) - 1
            cf = band(rshift(vr, band((shifts - 1), shift)), 0x01)
            vr = bor(rshift(vr, shifts), lshift(band(vr, shiftmask), band((shift - shifts + 1), shift)))
            of = band(bxor(rshift(vr, shift), rshift(vr, (shift - 1))), 0x01)
        elseif mode == 1 then
            shifts = band(shifts, shift)
            cf = band(rshift(vr, band((shift - shifts + 1), shift)), 0x01)
            vr = bor(band(lshift(vr, shifts), (lshift(1, (shift + 1)) - 1)), rshift(vr, band((shift - shifts + 1), shift)))
            of = band(bxor(rshift(vr, shift), cf), 0x01)
        elseif mode == 2 then
            shifts = shifts % (shift + 2)
            while shifts > 0 do
                local newcf = band(vr, 0x01)
                vr = bor(rshift(vr, 1), lshift(cf, shift))
                shifts = shifts - 1
                cf = newcf
            end
            of = band(bxor(rshift(vr, shift), rshift(vr, (shift - 1))), 0x01)
        elseif mode == 3 then
            shifts = shifts % (shift + 2)
            while shifts > 0 do
                local newcf = band(rshift(vr, shift), 0x01)
                vr = bor(band(lshift(vr, 1), (lshift(1, (shift + 1)) - 1)), cf)
                shifts = shifts - 1
                cf = newcf
            end
            of = band(bxor(rshift(vr, shift), cf), 0x01)
        end

        cpu_write_rm(self, mrm, mrm.dst, band(vr, 0xFFFF))
        cpu_write_flag(self, 0, cf == 1)
        if v1 == 1 then
            cpu_write_flag(self, 11, of == 1)
        end
    end
end

local function cpu_mul(self, mrm, opcode)
    local w = band(opcode, 0x01)
    local v1 = cpu_read_rm(self, mrm, mrm.src)
    local v2 = cpu_read_rm(self, mrm, mrm.dst)
    local vr = v1 * v2
    local vrf
    if w == 1 then
        vr = band(vr, 0xFFFFFFFF)
        self.regs[3] = rshift(vr, 16)
        self.regs[1] = band(vr, 0xFFFF)
        vrf = rshift(vr, 16)
    else
        vr = band(vr, 0xFFFF)
        self.regs[1] = vr
        vrf = rshift(vr, 8)
    end

    cpu_write_flag(self, 0, vrf ~= 0)
    cpu_write_flag(self, 11, vrf ~= 0)
end

local function cpu_imul(self, mrm, opcode)
    local w = band(opcode, 0x01)
    local v1 = cpu_read_rm(self, mrm, mrm.src)
    local v2 = cpu_read_rm(self, mrm, mrm.dst)
    local vr = 0
    if w == 1 then
        vr = (to_16(v1) * to_16(v2))
        self.regs[3] = band(rshift(vr, 16), 0xFFFF)
        self.regs[1] = band(vr, 0xFFFF)

        cpu_write_flag(self, 0, (vr < -0x8000) or (vr >= 0x8000))
        cpu_write_flag(self, 11, (vr < -0x8000) or (vr >= 0x8000))
    else
        vr = (to_8(v1) * to_8(v2))
        self.regs[1] = band(vr, 0xFFFF)

        cpu_write_flag(self, 0, (vr < -0x80) or (vr >= 0x80))
        cpu_write_flag(self, 11, (vr < -0x80) or (vr >= 0x80))
    end
end

local function cpu_div(self, mrm, opcode)
    local w = band(opcode, 0x01)
    local v2 = cpu_read_rm(self, mrm, mrm.dst)
    if w == 1 then
        local v = bor(lshift(self.regs[3], 16), (self.regs[1]))
        if v2 == 0 then
            logger:error("i8086: Divide %d by zero", v2)
            emit_interrupt(self, 0, false)
            return
        end
        local vd = math.floor(v / v2)
        local vr = v % v2
        if vd > 0xFFFF then
            logger:error("i8086: Overflow: %d / %d = %d", v, v2, vd)
            emit_interrupt(self, 0, false)
            return
        end

        self.regs[3] = band(vr, 0xFFFF)
        self.regs[1] = band(vd, 0xFFFF)
    else
        local v = (self.regs[1])
        if v2 == 0 then
            logger:error("i8086: Divide %d by zero", v2)
            emit_interrupt(self, 0, false)
            return
        end
        local vd = math.floor(v / v2)
        local vr = v % v2
        if vd > 0xFF then
            logger:error("i8086: Overflow: %d / %d = %d", v, v2, vd)
            emit_interrupt(self, 0, false)
            return
        end

        self.regs[1] = bor(lshift(band(vr, 0xFF), 8), band(vd, 0xFF))
    end
end

local function cpu_idiv(self, mrm, opcode)
    local w = band(opcode, 0x01)
    local v2 = cpu_read_rm(self, mrm, mrm.dst)
    if w == 1 then
        local v = bor(lshift(self.regs[3], 16), (self.regs[1]))
        v = to_32(v)
        v2 = to_16(v2)
        if v2 == 0 then
            logger:error("i8086: Divide %d by zero", v2)
            emit_interrupt(self, 0, false)
            return
        end
        local vd = v / v2
        if vd >= 0 then vd = math.floor(vd) else vd = math.ceil(vd) end
            local vr = math.fmod(v, v2)
        if (vd >= 0x8000) or (vd < -0x8000) then
            logger:error("i8086: Overflow: %d / %d = %d", v, v2, vd)
            emit_interrupt(self, 0, false)
            return
        end

        self.regs[3] = band(vr, 0xFFFF)
        self.regs[1] = band(vd, 0xFFFF)
    else
        local v = (self.regs[1])
        v = to_16(v)
        v2 = to_8(v2)
        if v2 == 0 then
            logger:error("i8086: Divide %d by zero", v2)
            emit_interrupt(self, 0, false)
            return
        end
        local vd = math.floor(v / v2)
        if vd >= 0 then vd = math.floor(vd) else vd = math.ceil(vd) end
        local vr = math.fmod(v, v2)
        if (vd >= 0x80) or (vd < -0x80) then
            logger:error("i8086: Overflow: %d / %d = %d", v, v2, vd)
            emit_interrupt(self, 0, false)
            return
        end

        self.regs[1] = bor(lshift(band(vr, 0xFF), 8), band(vd, 0xFF))
    end
end

local function cpu_add(self, mrm, opcode, carry)
    local w = band(opcode, 0x01)
    local v1 = cpu_read_rm(self, mrm, mrm.src)
    local v2 = cpu_read_rm(self, mrm, mrm.dst)
    local vc = 0
    if carry and (band(self.flags, lshift(1, (0))) ~= 0) then
        vc = 1
    end
    local vr = v1 + v2 + vc
    if w == 1 then
        cpu_write_rm(self, mrm, mrm.dst, band(vr, 0xFFFF))
    else
        cpu_write_rm(self, mrm, mrm.dst, band(vr, 0xFF))
    end
    cpu_zsp(self, vr, opcode)
    cpu_uf_add(self, v1, v2, vc, vr, opcode)
end

local function cpu_cmp(self, v2, v1, opcode)
    local vr = v2 - v1
    cpu_uf_sub(self, v1, v2, 0, vr, opcode)
    cpu_zsp(self, vr, opcode)
end

local function cpu_cmp_mrm(self, mrm, opcode)
    cpu_cmp(self, cpu_read_rm(self, mrm, mrm.dst), cpu_read_rm(self, mrm, mrm.src), opcode)
end

local function cpu_sub(self, mrm, opcode, borrow)
    local w = band(opcode, 0x01)
    local v1 = cpu_read_rm(self, mrm, mrm.src)
    local v2 = cpu_read_rm(self, mrm, mrm.dst)
    local vb = 0
    if borrow and (band(self.flags, lshift(1, (0))) ~= 0) then
        vb = 1
    end
    local vr = v2 - v1 - vb
    cpu_uf_sub(self, v1, v2, vb, vr, opcode)
    if w == 1 then
        vr = band(vr, 0xFFFF)
    else
        vr = band(vr, 0xFF)
    end
    cpu_write_rm(self, mrm, mrm.dst, vr)
    cpu_zsp(self, vr, opcode)
end

local function cpu_xor(self, mrm, opc)
    local v1 = cpu_read_rm(self, mrm, mrm.src)
    local v2 = cpu_read_rm(self, mrm, mrm.dst)
    local vr = bxor(v1, v2)
    cpu_write_rm(self, mrm, mrm.dst, vr)
    cpu_uf_bit(self, vr, opc)
end

local function cpu_and(self, mrm, opc)
    local v1 = cpu_read_rm(self, mrm, mrm.src)
    local v2 = cpu_read_rm(self, mrm, mrm.dst)
    local vr = band(v1, v2)
    cpu_write_rm(self, mrm, mrm.dst, vr)
    cpu_uf_bit(self, vr, opc)
end

local function cpu_test(self, mrm, opc)
    local v1 = cpu_read_rm(self, mrm, mrm.src)
    local v2 = cpu_read_rm(self, mrm, mrm.dst)
    local vr = band(v1, v2)
    cpu_uf_bit(self, vr, opc)
end

local function cpu_or(self, mrm, opc)
    local v1 = cpu_read_rm(self, mrm, mrm.src)
    local v2 = cpu_read_rm(self, mrm, mrm.dst)
    local vr = bor(v1, v2)
    cpu_write_rm(self, mrm, mrm.dst, vr)
    cpu_uf_bit(self, vr, opc)
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
        if self.regs[2] == 0 then break end

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

local function cpu_in(port)
    local p = io_ports[port]
    -- logger:debug("i8086: Cpu in: port:%02X", port)
    if p == nil then
        logger:warning("i8086: Cpu in: port:%02X not found", port)
        return 0xFF
    elseif type(p) == "function" then
        return p(port)
    else
        return p
    end
end

local function cpu_out(self, port, val)
    local p = io_ports[port]
    -- logger:warning("i8086: Cpu out: port:%02X", port)
    if type(p) == "function" then
        p(self, port, val)
    elseif p ~= nil then
        io_ports[port+1] = val
    else
       logger:warning("i8086: Cpu out: port:%02X not found", port)
    end
end

local function port_get(self, port)
    return io_ports[port]
end

local function port_set(self, port, value, value2)
    if type(value) == "function" and type(value2) == "function" then
        io_ports[port+1] = function(cpu, port, v)
            if v then
                value(cpu, port,v)
            else
                value2(cpu, port)
            end
        end
    else
        io_ports[port] = value
    end
end

local interrupt_handlers = {}

local function register_interrupt_handler(self, id, handler)
    interrupt_handlers[id + 1] = handler
end

local function cpu_int_fake(self, id)
    local ax = self.regs[1]
    local ah = rshift(ax, 8)
    local al = band(ax, 0xFF)

    local h = interrupt_handlers[id + 1]
    -- logger:warning("i8086: Interrupt: %02X, AH = %02X", id, ah)
    if h then
        local r = h(self, ax,ah,al)
        if r then
            return r
        end
    end

    logger:warning("i8086: Unknown interrupt: %02X, AH = %02X", id, ah)
end

local function cpu_int(self, id)
    -- logger:debug("i8086: INT %02X", id)
    local addr = self.memory:r16(id * 4)
    local seg = self.memory:r16(id * 4 + 2)

    cpu_push16(self, self.flags)
    cpu_push16(self, self.segments[2])
    cpu_push16(self, self.ip)

    self.segments[2] = seg
    self.ip = addr
    self.halted = false

    self.flags = band(self.flags, bnot(lshift(1, 9)))
end

local rel_jmp_conds = {
    function(self) return (band(self.flags, lshift(1, (11))) ~= 0) end,
    function(self) return not (band(self.flags, lshift(1, (11))) ~= 0) end,
    function(self) return (band(self.flags, lshift(1, (0))) ~= 0) end,
    function(self) return not (band(self.flags, lshift(1, (0))) ~= 0) end,
    function(self) return (band(self.flags, lshift(1, (6))) ~= 0) end,
    function(self) return not (band(self.flags, lshift(1, (6))) ~= 0) end,
    function(self) return (band(self.flags, lshift(1, (0))) ~= 0) or (band(self.flags, lshift(1, (6))) ~= 0) end,
    function(self) return not ((band(self.flags, lshift(1, (0))) ~= 0) or (band(self.flags, lshift(1, (6))) ~= 0)) end,
    function(self) return (band(self.flags, lshift(1, (7))) ~= 0) end,
    function(self) return not (band(self.flags, lshift(1, (7))) ~= 0) end,
    function(self) return (band(self.flags, lshift(1, (2))) ~= 0) end,
    function(self) return not (band(self.flags, lshift(1, (2))) ~= 0) end,
    function(self) return (band(self.flags, lshift(1, (11))) ~= 0) ~= (band(self.flags, lshift(1, (7))) ~= 0) end,
    function(self) return (band(self.flags, lshift(1, (11))) ~= 0) == (band(self.flags, lshift(1, (7))) ~= 0) end,
    function(self) return ((band(self.flags, lshift(1, (11))) ~= 0) ~= (band(self.flags, lshift(1, (7))) ~= 0)) or (band(self.flags, lshift(1, (6))) ~= 0) end,
    function(self) return not (((band(self.flags, lshift(1, (11))) ~= 0) ~= (band(self.flags, lshift(1, (7))) ~= 0)) or (band(self.flags, lshift(1, (6))) ~= 0)) end
}

local opcode_map = {}

-- NOP
opcode_map[0x90] = function(self, opcode) end

-- ADD
opcode_map[0x00] = function(self, opcode)
    cpu_add(self, mrm6_table[band((opcode), 0x7)](self, (opcode)), opcode)
end
for i=0x01,0x05 do
    opcode_map[i] = opcode_map[0x00]
end

-- PUSH/POP ES
opcode_map[0x06] = function(self, opcode) cpu_push16(self, self.segments[1]) end
opcode_map[0x07] = function(self, opcode) self.segments[1] = cpu_pop16(self) end

-- OR
opcode_map[0x08] = function(self, opcode) cpu_or(self, mrm6_table[band((opcode), 0x7)](self, (opcode)), opcode) end
for i=0x09,0x0D do opcode_map[i] = opcode_map[0x08] end

-- PUSH CS
opcode_map[0x0E] = function(self, opcode) cpu_push16(self, self.segments[2]) end

-- POP CS (8086)
opcode_map[0x0F] = function(self, opcode) self.segments[2] = cpu_pop16(self) end

-- ADC
opcode_map[0x10] = function(self, opcode) cpu_add(self, mrm6_table[band((opcode), 0x7)](self, (opcode)), opcode, true) end
for i=0x11,0x15 do opcode_map[i] = opcode_map[0x10] end

-- PUSH/POP SS
opcode_map[0x16] = function(self, opcode) cpu_push16(self, self.segments[3]) end
opcode_map[0x17] = function(self, opcode) self.segments[3] = cpu_pop16(self) end

-- SBB
opcode_map[0x18] = function(self, opcode) cpu_sub(self, mrm6_table[band((opcode), 0x7)](self, (opcode)), opcode, true) end
for i=0x19,0x1D do opcode_map[i] = opcode_map[0x18] end

-- PUSH/POP DS
opcode_map[0x1E] = function(self, opcode) cpu_push16(self, self.segments[4]) end
opcode_map[0x1F] = function(self, opcode) self.segments[4] = cpu_pop16(self) end

-- AND
opcode_map[0x20] = function(self, opcode) cpu_and(self, mrm6_table[band((opcode), 0x7)](self, (opcode)), opcode) end
for i=0x21,0x25 do opcode_map[i] = opcode_map[0x20] end

-- ES:
opcode_map[0x26] = function(self, opcode)
    self.segment_mode = 1
    local r = run_one(self, true, true)
    self.segment_mode = nil
    return r
end

-- DAA
opcode_map[0x27] = function(self, opcode)
    local al = band(self.regs[1], 0xFF)
    local old_al = al
    local old_cf = (band(self.flags, lshift(1, (0))) ~= 0)
    if (band(old_al, 0x0F) > 0x9) or (band(self.flags, lshift(1, (4))) ~= 0) then
        al = al + 0x6
        cpu_write_flag(self, 0, old_cf or (al > 0xFF))
        self.flags = bor(self.flags, lshift(1, (4)))
    else
        self.flags = band(self.flags, bxor(self.flags, lshift(1, (4))))
    end
    if (old_al > 0x99) or old_cf then
        al = al + 0x60
        self.flags = bor(self.flags, lshift(1, (0)))
    end
    self.regs[1] = bor(band(self.regs[1], 0xFF00), band(al, 0xFF))
    cpu_zsp(self, al, 0)
end

-- SUB
opcode_map[0x28] = function(self, opcode) cpu_sub(self, mrm6_table[band((opcode), 0x7)](self, (opcode)), opcode) end
for i=0x29,0x2D do opcode_map[i] = opcode_map[0x28] end

-- CS:
opcode_map[0x2E] = function(self, opcode)
    self.segment_mode = 2
    local r = run_one(self, true, true)
    self.segment_mode = nil
    return r
end

-- DAS
opcode_map[0x2F] = function(self, opcode)
    local al = band(self.regs[1], 0xFF)
    local old_al = al
    local old_cf = (band(self.flags, lshift(1, (0))) ~= 0)
    if (band(al, 0x0F) > 0x9) or (band(self.flags, lshift(1, (4))) ~= 0) then
        al = al - 0x6
        cpu_write_flag(self, 0, old_cf or (al < 0))
        self.flags = bor(self.flags, lshift(1, (4)))
    else
        self.flags = band(self.flags, bxor(self.flags, lshift(1, (4))))
    end
    if ((al) > 0x99) or old_cf then
        al = al - 0x60
        self.flags = bor(self.flags, lshift(1, (0)))
    else
        self.flags = band(self.flags, bxor(self.flags, lshift(1, (0))))
    end
    self.regs[1] = bor(band(self.regs[1], 0xFF00), band(al, 0xFF))
    cpu_zsp(self, al, 0)
end

-- XOR
opcode_map[0x30] = function(self, opcode) cpu_xor(self, mrm6_table[band((opcode), 0x7)](self, (opcode)), opcode) end
for i=0x31,0x35 do opcode_map[i] = opcode_map[0x30] end

-- SS:
opcode_map[0x36] = function(self, opcode)
    self.segment_mode = 3
    local r = run_one(self, true, true)
    self.segment_mode = nil
    return r
end

-- AAA
opcode_map[0x37] = function(self, opcode)
    local al = band(self.regs[1], 0xFF)
    if (band(al, 0x0F) >= 0x9) or (band(self.flags, lshift(1, (4))) ~= 0) then
        self.regs[1] = band((self.regs[1] + 0x106), 0xFFFF)
        self.flags = bor(self.flags, lshift(1, (0)))
        self.flags = bor(self.flags, lshift(1, (4)))
    else
        self.flags = band(self.flags, bxor(self.flags, lshift(1, (0))))
        self.flags = band(self.flags, bxor(self.flags, lshift(1, (4))))
    end
    self.regs[1] = band(self.regs[1], 0xFF0F)
end

-- CMP
opcode_map[0x38] = function(self, opcode) cpu_cmp_mrm(self, mrm6_table[band((opcode), 0x7)](self, (opcode)), opcode) end
for i=0x39,0x3D do opcode_map[i] = opcode_map[0x38] end

-- DS:
opcode_map[0x3E] = function(self, opcode)
    self.segment_mode = 4
    local r = run_one(self, true, true)
    self.segment_mode = nil
    return r
end

-- AAS
opcode_map[0x3F] = function(self, opcode)
    local al = band(self.regs[1], 0xFF)
    if (band(al, 0x0F) >= 0x9) or (band(self.flags, lshift(1, (4))) ~= 0) then
        self.regs[1] = band((self.regs[1] - 0x006), 0xFFFF)
        local ah = rshift(band(self.regs[1], 0xFF00), 8)
        ah = band((ah - 1), 0xFF)
        self.regs[1] = bor(band(self.regs[1], 0xFF), lshift(ah, 8))
        self.flags = bor(self.flags, lshift(1, (0)))
        self.flags = bor(self.flags, lshift(1, (4)))
    else
        self.flags = band(self.flags, bxor(self.flags, lshift(1, (0))))
        self.flags = band(self.flags, bxor(self.flags, lshift(1, (4))))
    end
    self.regs[1] = band(self.regs[1], 0xFF0F)
end

-- INC
opcode_map[(0x40)] = function(self, opcode) local v = self.regs[(1)]; v = band((v + 1), 0xFFFF); self.regs[(1)] = v; cpu_inc(self, v, 1) end
opcode_map[(0x41)] = function(self, opcode) local v = self.regs[(2)]; v = band((v + 1), 0xFFFF); self.regs[(2)] = v; cpu_inc(self, v, 1) end
opcode_map[(0x42)] = function(self, opcode) local v = self.regs[(3)]; v = band((v + 1), 0xFFFF); self.regs[(3)] = v; cpu_inc(self, v, 1) end
opcode_map[(0x43)] = function(self, opcode) local v = self.regs[(4)]; v = band((v + 1), 0xFFFF); self.regs[(4)] = v; cpu_inc(self, v, 1) end
opcode_map[(0x44)] = function(self, opcode) local v = self.regs[(5)]; v = band((v + 1), 0xFFFF); self.regs[(5)] = v; cpu_inc(self, v, 1) end
opcode_map[(0x45)] = function(self, opcode) local v = self.regs[(6)]; v = band((v + 1), 0xFFFF); self.regs[(6)] = v; cpu_inc(self, v, 1) end
opcode_map[(0x46)] = function(self, opcode) local v = self.regs[(7)]; v = band((v + 1), 0xFFFF); self.regs[(7)] = v; cpu_inc(self, v, 1) end
opcode_map[(0x47)] = function(self, opcode) local v = self.regs[(8)]; v = band((v + 1), 0xFFFF); self.regs[(8)] = v; cpu_inc(self, v, 1) end

-- DEC
opcode_map[(0x48)] = function(self, opcode) local v = self.regs[(1)]; v = band((v - 1), 0xFFFF); self.regs[(1)] = v; cpu_dec(self, v, 1) end
opcode_map[(0x49)] = function(self, opcode) local v = self.regs[(2)]; v = band((v - 1), 0xFFFF); self.regs[(2)] = v; cpu_dec(self, v, 1) end
opcode_map[(0x4A)] = function(self, opcode) local v = self.regs[(3)]; v = band((v - 1), 0xFFFF); self.regs[(3)] = v; cpu_dec(self, v, 1) end
opcode_map[(0x4B)] = function(self, opcode) local v = self.regs[(4)]; v = band((v - 1), 0xFFFF); self.regs[(4)] = v; cpu_dec(self, v, 1) end
opcode_map[(0x4C)] = function(self, opcode) local v = self.regs[(5)]; v = band((v - 1), 0xFFFF); self.regs[(5)] = v; cpu_dec(self, v, 1) end
opcode_map[(0x4D)] = function(self, opcode) local v = self.regs[(6)]; v = band((v - 1), 0xFFFF); self.regs[(6)] = v; cpu_dec(self, v, 1) end
opcode_map[(0x4E)] = function(self, opcode) local v = self.regs[(7)]; v = band((v - 1), 0xFFFF); self.regs[(7)] = v; cpu_dec(self, v, 1) end
opcode_map[(0x4F)] = function(self, opcode) local v = self.regs[(8)]; v = band((v - 1), 0xFFFF); self.regs[(8)] = v; cpu_dec(self, v, 1) end

-- PUSH/POP
opcode_map[0x50] = function(self, opcode) cpu_push16(self, self.regs[1]) end
opcode_map[0x51] = function(self, opcode) cpu_push16(self, self.regs[2]) end
opcode_map[0x52] = function(self, opcode) cpu_push16(self, self.regs[3]) end
opcode_map[0x53] = function(self, opcode) cpu_push16(self, self.regs[4]) end
opcode_map[0x54] = function(self, opcode) cpu_push16(self, self.regs[5]) end
opcode_map[0x55] = function(self, opcode) cpu_push16(self, self.regs[6]) end
opcode_map[0x56] = function(self, opcode) cpu_push16(self, self.regs[7]) end
opcode_map[0x57] = function(self, opcode) cpu_push16(self, self.regs[8]) end
opcode_map[0x58] = function(self, opcode) self.regs[1] = cpu_pop16(self) end
opcode_map[0x59] = function(self, opcode) self.regs[2] = cpu_pop16(self) end
opcode_map[0x5A] = function(self, opcode) self.regs[3] = cpu_pop16(self) end
opcode_map[0x5B] = function(self, opcode) self.regs[4] = cpu_pop16(self) end
opcode_map[0x5C] = function(self, opcode) self.regs[5] = cpu_pop16(self) end
opcode_map[0x5D] = function(self, opcode) self.regs[6] = cpu_pop16(self) end
opcode_map[0x5E] = function(self, opcode) self.regs[7] = cpu_pop16(self) end
opcode_map[0x5F] = function(self, opcode) self.regs[8] = cpu_pop16(self) end

-- PUSH SP (8086 bug reproduction)
opcode_map[0x54] = function(self, opcode)
    cpu_push16(self, self.regs[5] - 2)
end

-- JMP
for i=0x70,0x7F do
    local cond = rel_jmp_conds[i - 0x6F]
    opcode_map[i] = function(self, opcode)
        local offset = advance_ip(self)
        if cond(self) then
            self.ip = band((self.ip + to_8(offset)), 0xFFFF)
        end
    end
end

for i=0,15 do
    opcode_map[0x60 + i] = opcode_map[0x70 + i]
end

local grp1_table = {
    [0]=cpu_add,
    [1]=cpu_or,
    [2]=function(self, a,b) cpu_add(self, a,b,true) end,
    [3]=function(self, a,b) cpu_sub(self, a,b,true) end,
    [4]=cpu_and,
    [5]=function(self, a,b) cpu_sub(self, a,b,false) end,
    [6]=cpu_xor,
    [7]=function(self, a,b) cpu_cmp_mrm(self, a,b) end
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

-- MOV segment
opcode_map[0x8C] = function(self, opcode)
    local mrm = cpu_mod_rm(self, opcode, 1024)
    if mrm.dst == 26 + self.seg_cs then
        logger:warning("i8086: Tried writing to CS segment!")
    end
    cpu_mov(self, mrm)
    if mrm.dst == 26+self.seg_ss then
        return run_one(self, true, true)
    end
end
opcode_map[0x8E] = opcode_map[0x8C]

-- LEA
opcode_map[0x8D] = function(self, opcode)
    local mrm = cpu_mod_rm(self, 3)
    cpu_write_rm(self, mrm, mrm.dst, cpu_addr_rm(self, mrm, mrm.src))
end

-- POP m16
opcode_map[0x8F] = function(self, opcode)
    local mrm = cpu_mod_rm(self, 1)
    cpu_write_rm(self, mrm, mrm.dst, cpu_pop16(self))
end

-- XCHG (XCHG AX, AX == NOP)
opcode_map[(0x91)] = function(self, opcode) local v = self.regs[(2)]; self.regs[(2)] = self.regs[1]; self.regs[1] = v; end
opcode_map[(0x92)] = function(self, opcode) local v = self.regs[(3)]; self.regs[(3)] = self.regs[1]; self.regs[1] = v; end
opcode_map[(0x93)] = function(self, opcode) local v = self.regs[(4)]; self.regs[(4)] = self.regs[1]; self.regs[1] = v; end
opcode_map[(0x94)] = function(self, opcode) local v = self.regs[(5)]; self.regs[(5)] = self.regs[1]; self.regs[1] = v; end
opcode_map[(0x95)] = function(self, opcode) local v = self.regs[(6)]; self.regs[(6)] = self.regs[1]; self.regs[1] = v; end
opcode_map[(0x96)] = function(self, opcode) local v = self.regs[(7)]; self.regs[(7)] = self.regs[1]; self.regs[1] = v; end
opcode_map[(0x97)] = function(self, opcode) local v = self.regs[(8)]; self.regs[(8)] = self.regs[1]; self.regs[1] = v; end

-- CBW
opcode_map[0x98] = function(self, opcode)
    local v = band(self.regs[1], 0xFF)
    if v >= 0x80 then v = bor(v, 0xFF00) end
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
    local newIp = advance_ip16(self)
    local newCs = advance_ip16(self)
    cpu_push16(self, self.segments[2])
    cpu_push16(self, self.ip)
    self.ip = newIp
    self.segments[2] = newCs
end

-- PUSHF/POPF
opcode_map[0x9C] = function(self, opcode) cpu_push16(self, self.flags) end

opcode_map[0x9D] = function(self, opcode) self.flags = bor(cpu_pop16(self), 0xF002) end

-- SAHF/LAHF
opcode_map[0x9E] = function(self, opcode)
    self.flags = bor(band(self.flags, 0xFF00), rshift(band(self.regs[1], 0xFF00), 8))
end
opcode_map[0x9F] = function(self, opcode)
    self.regs[1] = bor(band(self.regs[1], 0xFF), lshift(band(self.flags, 0xFF), 8))
end

-- MOV offs->AL
opcode_map[0xA0] = function(self, opcode)
    local addr = advance_ip16(self)
    self.regs[1] = bor(band(self.regs[1], 0xFF00), self.memory[(lshift(self.segments[(self.segment_mode or (4))], 4) + (addr))])
end

-- MOV offs->AX
opcode_map[0xA1] = function(self, opcode)
    local addr = advance_ip16(self)
    self.regs[1] = self.memory:r16((lshift(self.segments[(self.segment_mode or (4))], 4) + (addr)))
end

-- MOV AL->offs
opcode_map[0xA2] = function(self, opcode)
    local addr = advance_ip16(self)
    self.memory[(lshift(self.segments[(self.segment_mode or (4))], 4) + (addr))] = band(self.regs[1], 0xFF)
end

-- MOV AX->offs
opcode_map[0xA3] = function(self, opcode)
    local addr = advance_ip16(self)
    self.memory:w16((lshift(self.segments[(self.segment_mode or (4))], 4) + (addr)), self.regs[1])
end

-- MOVSB/MOVSW
opcode_map[0xA4] = function(self, opcode)
    local addrSrc = (lshift(self.segments[(self.segment_mode or (4))], 4) + (self.regs[7]))
    local addrDst = (lshift(self.segments[(self.seg_es)+1], 4)+(self.regs[8]))
    self.memory[addrDst] = self.memory[addrSrc]
    cpu_incdec_dir(self, 7, 1)
    cpu_incdec_dir(self, 8, 1)
end

opcode_map[0xA5] = function(self, opcode)
    local addrSrc = (lshift(self.segments[(self.segment_mode or (4))], 4) + (self.regs[7]))
    local addrDst = (lshift(self.segments[(self.seg_es)+1],4)+(self.regs[8]))
    self.memory:w16(addrDst, self.memory:r16(addrSrc))
    cpu_incdec_dir(self, 7, 2)
    cpu_incdec_dir(self, 8, 2)
end

-- CMPSB/CMPSW
opcode_map[0xA6] = function(self, opcode)
    local addrSrc = (lshift(self.segments[(self.segment_mode or (4))], 4) + (self.regs[7]))
    local addrDst = (lshift(self.segments[(self.seg_es)+1],4)+(self.regs[8]))
    cpu_cmp(self, self.memory[addrSrc], self.memory[addrDst], opcode)
    cpu_incdec_dir(self, 7, 1)
    cpu_incdec_dir(self, 8, 1)
end
opcode_map[0xA7] = function(self, opcode)
    local addrSrc = (lshift(self.segments[(self.segment_mode or (4))], 4) + (self.regs[7]))
    local addrDst = (lshift(self.segments[(self.seg_es)+1], 4)+(self.regs[8]))
    cpu_cmp(self, self.memory:r16(addrSrc), self.memory:r16(addrDst), opcode)
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
    local addrDst = (lshift(self.segments[(self.seg_es)+1],4)+(self.regs[8]))
    self.memory[addrDst] = band(self.regs[1], 0xFF)
    cpu_incdec_dir(self, 8, 1)
end
opcode_map[0xAB] = function(self, opcode)
    local addrDst = (lshift(self.segments[(self.seg_es)+1], 4)+(self.regs[8]))
    self.memory:w16(addrDst, self.regs[1])
    cpu_incdec_dir(self, 8, 2)
end

-- LODSB/LODSW
opcode_map[0xAC] = function(self, opcode)
    local addrSrc = (lshift(self.segments[(self.segment_mode or (4))], 4) + (self.regs[7]))
    self.regs[1] = bor(band(self.regs[1], 0xFF00), self.memory[addrSrc])
    cpu_incdec_dir(self, 7, 1)
end
opcode_map[0xAD] = function(self, opcode)
    local addrSrc = (lshift(self.segments[(self.segment_mode or (4))], 4) + (self.regs[7]))
    self.regs[1] = self.memory:r16(addrSrc)
    cpu_incdec_dir(self, 7, 2)
end

-- SCASB/SCASW
opcode_map[0xAE] = function(self, opcode)
    local addrDst = (lshift(self.segments[(self.seg_es)+1], 4)+(self.regs[8]))
    cpu_cmp(self, band(self.regs[1], 0xFF), self.memory[addrDst], opcode)
    cpu_incdec_dir(self, 8, 1)
end
opcode_map[0xAF] = function(self, opcode)
    local addrDst = (lshift(self.segments[(self.seg_es)+1], 4)+(self.regs[8]))
    cpu_cmp(self, self.regs[1], self.memory:r16(addrDst), opcode)
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
    cpu_write_rm(self, mrm, mrm.dst, self.memory:r16((lshift(self.segments[(self.segment_mode or (defseg+1))], 4) + (addr))))
    if opcode == 0xC5 then
        self.segments[4] = self.memory:r16((lshift(self.segments[(self.segment_mode or (defseg+1))], 4) + (addr + 2)))
    else
        self.segments[1] = self.memory:r16((lshift(self.segments[(self.segment_mode or (defseg+1))], 4) + (addr + 2)))
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
end

-- INT imm
opcode_map[0xCD] = function(self, opcode) cpu_int(self, advance_ip(self)) end

-- INTO
opcode_map[0xCE] = function(self, opcode)
    if (band(self.flags, lshift(1, (11))) ~= 0) then
        cpu_int(self, 4)
    end
end

-- IRET far
opcode_map[0xCF] = function(self, opcode)
    self.ip = cpu_pop16(self)
    self.segments[2] = cpu_pop16(self)
    self.flags = cpu_pop16(self)
end

local grp2_table = {
    function(self, a,b) cpu_rotate(self, a,b,1) end,
    function(self, a,b) cpu_rotate(self, a,b,0) end,
    function(self, a,b) cpu_rotate(self, a,b,3) end,
    function(self, a,b) cpu_rotate(self, a,b,2) end,
    cpu_shl,
    cpu_shr,
    cpu_shl, -- SAL
    function(self, a,b) cpu_shr(self, a,b,true) end
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
    self.regs[1] = band((old_al + (old_ah * base)), 0xFF)
    cpu_zsp(self, self.regs[1], 0)
end

-- SALC (undocumented)
opcode_map[0xD6] = function(self, opcode)
    if (band(self.flags, lshift(1, (0))) ~= 0) then
        self.regs[1] = bor(self.regs[1], 0xFF)
    else
        self.regs[1] = band(self.regs[1], 0xFF00)
    end
end

-- XLAT
opcode_map[0xD7] = function(self, opcode)
    local addr = band((self.regs[4] + band(self.regs[1], 0xFF)), 0xFFFF)
    self.regs[1] = bor(band(self.regs[1], 0xFF00), self.memory[(lshift(self.segments[(self.segment_mode or (4))], 4) + (addr))])
end

-- LOOPNZ r8
opcode_map[0xE0] = function(self, opcode)
    local offset = to_8(advance_ip(self))
    self.regs[2] = self.regs[2] - 1
    if self.regs[2] ~= 0 and not (band(self.flags, lshift(1, (6))) ~= 0) then
        self.ip = band((self.ip + offset), 0xFFFF)
    end
end
-- LOOPZ r8
opcode_map[0xE1] = function(self, opcode)
    local offset = to_8(advance_ip(self))
    self.regs[2] = self.regs[2] - 1
    if self.regs[2] ~= 0 and (band(self.flags, lshift(1, (6))) ~= 0) then
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
    self.regs[1] = bor(band(self.regs[1], 0xFF00), band(cpu_in(advance_ip(self)), 0xFF))
end

-- IN AX, Ib
opcode_map[0xE5] = function(self, opcode)
    self.regs[1] = band(cpu_in(advance_ip(self)), 0xFFFF)
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
    local newIp = advance_ip16(self)
    local newCs = advance_ip16(self)
    self.ip = newIp
    self.segments[2] = newCs
end

-- JMP r8
opcode_map[0xEB] = function(self, opcode)
    local offset = to_8(advance_ip(self))
    self.ip = band(self.ip + offset, 0xFFFF)
end

-- IN AL, DX
opcode_map[0xEC] = function(self, opcode)
    self.regs[1] = bor(band(self.regs[1], 0xFF00), band(cpu_in(self.regs[3]), 0xFF))
end

-- IN AX, DX
opcode_map[0xED] = function(self, opcode)
    self.regs[1] = band(cpu_in(self.regs[3]), 0xFFFF)
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

opcode_map[0xF1] = function(self, opcode)

end

-- REPNZ
opcode_map[0xF2] = function(self, opcode)
    if not cpu_rep(self, function() return not (band(self.flags, lshift(1, (6))) ~= 0) end) then return false end
end

-- REPZ
opcode_map[0xF3] = function(self, opcode)
    if not cpu_rep(self, function() return (band(self.flags, lshift(1, (6))) ~= 0) end) then return false end
end

-- HLT
opcode_map[0xF4] = function(self, opcode)
    self.halted = true
    return true
end

-- CMC
opcode_map[0xF5] = function(self, opcode) self.flags = bxor(self.flags, lshift(1, (0))) end

-- GRP3
local grp3_table = {}
grp3_table[0] = function(self, mrm, opcode)
    mrm = cpu_mrm_copy(mrm)
    if opcode == 0xF7 then
        mrm.src = 41
        mrm.imm = advance_ip16(self)
    else
        mrm.src = 40
        mrm.imm = advance_ip(self)
        end
        cpu_test(self, mrm, opcode)
    end
    grp3_table[1] = function()
    logger:error("i8086: Invalid opcode: GRP3/1")
end

-- GRP3/NOT
grp3_table[2] = function(self, mrm, opcode)
    if opcode == 0xF7 then
        cpu_write_rm(self, mrm, mrm.dst, bxor(cpu_read_rm(self, mrm, mrm.dst), 0xFFFF))
    else
        cpu_write_rm(self, mrm, mrm.dst, bxor(cpu_read_rm(self, mrm, mrm.dst), 0xFF))
    end
end

-- GRP3/NEG
grp3_table[3] = function(self, mrm, opcode)
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
end

grp3_table[4] = cpu_mul
grp3_table[5] = cpu_imul
grp3_table[6] = cpu_div
grp3_table[7] = cpu_idiv

opcode_map[0xF6] = function(self, opcode)
    local mrm = cpu_mod_rm(self, band(opcode, 0x01))
    local v = band(mrm.src, 0x07)
    if v >= 4 then
        mrm = cpu_mrm_copy(mrm)
    if opcode == 0xF7 then mrm.src = 0 else mrm.src = 16 end
    end
    grp3_table[v](self, mrm, opcode)
end
opcode_map[0xF7] = opcode_map[0xF6]

-- flag setters
opcode_map[0xF8] = function(self, opcode) self.flags = band(self.flags, bxor(self.flags, lshift(1, (0)))) end
opcode_map[0xF9] = function(self, opcode) self.flags = bor(self.flags, lshift(1, (0))) end
opcode_map[0xFA] = function(self, opcode) self.flags = band(self.flags, bxor(self.flags, lshift(1, (9)))) end
opcode_map[0xFB] = function(self, opcode) self.flags = bor(self.flags, lshift(1, (9))) end
opcode_map[0xFC] = function(self, opcode) self.flags = band(self.flags, bxor(self.flags, lshift(1, (10)))) end
opcode_map[0xFD] = function(self, opcode) self.flags = bor(self.flags, lshift(1, (10))) end

-- GRP4
opcode_map[0xFE] = function(self, opcode)
    local mrm = cpu_mod_rm(self, 0)
    local v = band(mrm.src, 0x07)

    if v == 0 then -- INC
        local v = band((cpu_read_rm(self, mrm,mrm.dst) + 1), 0xFF)
        cpu_write_rm(self, mrm,mrm.dst,v)
        cpu_inc(self, v, 0)
    elseif v == 1 then -- DEC
        local v = band((cpu_read_rm(self, mrm,mrm.dst) - 1), 0xFF)
        cpu_write_rm(self, mrm,mrm.dst,v)
        cpu_dec(self, v, 0)
    else

    end
end

-- GRP5
opcode_map[0xFF] = function(self, opcode)
    local mrm = cpu_mod_rm(self, 1)
    local v = band(mrm.src, 0x07)
    if v == 0 then -- INC
        local v = band((cpu_read_rm(self, mrm,mrm.dst) + 1), 0xFFFF)
        cpu_write_rm(self, mrm,mrm.dst,v)
        cpu_inc(self, v, 1)
    elseif v == 1 then -- DEC
        local v = band((cpu_read_rm(self, mrm,mrm.dst) - 1), 0xFFFF)
        cpu_write_rm(self, mrm,mrm.dst,v)
        cpu_dec(self, v, 1)
    elseif v == 2 then -- CALL near abs
        local newIp = cpu_read_rm(self, mrm,mrm.dst)
        cpu_push16(self, self.ip)
        self.ip = newIp
    elseif v == 3 then -- CALL far abs
        local addr = (lshift(self.segments[(self.segment_mode or (cpu_seg_rm(self, mrm,mrm.dst)+1))], 4) + (cpu_addr_rm(self, mrm,mrm.dst)))
        local newIp = self.memory:r16(addr)
        local newCs = self.memory:r16(addr+2)
        cpu_push16(self, self.segments[2])
        cpu_push16(self, self.ip)
        self.ip = newIp
        self.segments[2] = newCs
    elseif v == 4 then -- JMP near abs
        self.ip = cpu_read_rm(self, mrm,mrm.dst)
    elseif v == 5 then -- JMP far
        local addr = (lshift(self.segments[(self.segment_mode or (cpu_seg_rm(self, mrm,mrm.dst)+1))], 4) + (cpu_addr_rm(self, mrm,mrm.dst)))
        local newIp = self.memory:r16(addr)
        local newCs = self.memory:r16(addr+2)
        self.ip = newIp
        self.segments[2] = newCs
    elseif v == 6 then
        cpu_push16(self, cpu_read_rm(self, mrm,mrm.dst))
    else
        --logger:error("i8086: Unknown GRP5 opcode: %02X", v)
    end
end

-- 8087 FPU stubs
opcode_map[0x9B] = function(self, opcode) end
for i=0xD8,0xDF do
    opcode_map[i] = function(self, opcode) cpu_mod_rm(self, 1) end
end

-- 8086 0xCX opcode aliases
opcode_map[0xC0] = opcode_map[0xC2]
opcode_map[0xC1] = opcode_map[0xC3]
opcode_map[0xC8] = opcode_map[0xCA]
opcode_map[0xC9] = opcode_map[0xCB]

run_one = function(self, no_interrupting, pr_state)
    if self.hasint and not no_interrupting then
        local intr = self.intqueue[1]
        if intr ~= nil then
            if intr >= 256 or (band(self.flags, lshift(1, (9))) ~= 0) then
                table.remove(self.intqueue, 1)
                cpu_int(self, band(intr, 0xFF))
                if #self.intqueue == 0 then self.hasint = false end
            end
        end
    end

    if (band(self.ip, 0xFF00) == 0x1100) and (self.segments[2] == 0xF000) then
        self.flags = bor(self.flags, lshift(1, (9)))
        local intr = cpu_int_fake(self, band(self.ip, 0xFF))
        if intr ~= -1 then
            self.ip = cpu_pop16(self)
            self.segments[2] = cpu_pop16(self)
            local old_flags = cpu_pop16(self)
            local old_flag_mask = 0x0200
            self.flags = bor(band(self.flags, bxor(self.flags, old_flag_mask)), band(old_flags, old_flag_mask))
            return true
        else
            return false
        end
    end

    local opcode = advance_ip(self)
    -- logger:error("i8086: Opcode: %02X", opcode)
    local om = opcode_map[opcode]
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

local function emit_interrupt(self, v, nmi)
    nmi = (v == 2)
    if nmi then
        table.insert(self.intqueue, v + 256)
    else
        table.insert(self.intqueue, v)
    end
    self.hasint = true
end

local cpu = {}

local function reset(self)
    for i = 1, 8, 1 do
        self.regs[i] = 0
    end
    for i = 1, 6, 1 do
        self.segments[i] = 0
    end
    self.seg_es = 0
    self.seg_ss = 2
    self.seg_cs = 1
    self.seg_ds = 3
    self.ip = 0
    self.intqueue = {}

    for i=0, 255 do
        self.memory:w16(i*4, 0x1100 + i)
        self.memory:w16(i*4 + 2, 0xF000)
    end
end

function cpu.new(memory)
    local instance = {
        regs = {0, 0, 0, 0, 0, 0, 0, 0},
        segments = {0, 0, 0, 0, 0, 0},
        seg_es = 0,
        seg_cs = 1,
        seg_ss = 2,
        seg_ds = 3,

        flags = 0,
        ip = 0,
        hasint = false,
        segment_mode = nil,
        halted = false,
        memory = memory,
        intqueue = {},
        reset = reset,

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
    }

    instance.rm_seg_t = {
        instance.seg_ds, instance.seg_ds,
        instance.seg_ss, instance.seg_ss,
        instance.seg_ds, instance.seg_ds,
        instance.seg_ss, instance.seg_ds
    }

    for i=0,255 do
        if interrupt_handlers[i+1] then
            memory[0xF1100+i] = 0x90
        else
            memory[0xF1100+i] = 0xCF
        end
    end

    for i=0, 255 do
        memory:w16(i*4, 0x1100 + i)
        memory:w16(i*4 + 2, 0xF000)
    end
    return instance
end

return cpu