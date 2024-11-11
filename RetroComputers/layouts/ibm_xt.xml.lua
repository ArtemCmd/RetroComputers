---@diagnostic disable: lowercase-global
local vmmanager = require("retro_computers:emulator/vmmanager")
local blocks = require("retro_computers:blocks")
local cp437 = require("retro_computers:emulator/cp437")

-- local band, rshift = bit.band, bit.rshift
-- Screen
local width, height, last_width, last_height
local screen = document.screen
local cursor = document.cursor
-- Machine
local mx, my, mz
local machine
-- Font
local glyph_width, glyph_height = 8, 8
local FONT_SCALE = 1
local cache = {}
local is_cached = false

local palette = {
    [0] = " ", -- black
    [1] = ".", -- blue
    [2] = ",", -- green
    [3] = "_", -- cyan
    [4] = "$", -- red
    [5] = "#", -- magenta
    [6] = "@", -- brown
    [7] = "!", -- light gray
    [8] = "S", -- dark gray
    [9] = "D", -- light blue
    [10] = "f", -- light green
    [11] = "8", -- light cyan
    [12] = "7", -- light red
    [13] = "6", -- light magenta
    [14] = "0", -- yellow
    [15] = "#" -- white
}

-- local cga_palette = {
-- 	0x000000,
--     0x0000AA,
--     0x00AA00,
--     0x00AAAA,
-- 	0xAA0000,
--     0xAA00AA,
--     0xAA5500,
--     0xAAAAAA,
-- 	0x555555,
--     0x5555FF,
--     0x55FF55,
--     0x55FFFF,
-- 	0xFF5555,
--     0xFF55FF,
--     0xFFFF55,
--     0xFFFFFF
-- }
local cga_palette = {
	{0, 0, 0, 255}, -- black
    {0, 0, 170, 255}, -- blue
    {0, 170, 0, 255}, -- green
    {0, 170, 170, 255}, -- cyan
	{170, 0, 0, 255}, -- red
    {170, 0, 170, 255}, -- magenta
    {170, 85, 0, 255}, -- brown
    {170, 170, 170, 255}, -- light gray
	{85, 85, 85, 255}, -- dark gray
    {85, 85, 255, 255}, -- light blue
    {85, 255, 85, 255}, -- light green
    {85, 255, 255, 255}, -- light cyan
	{255, 85, 85, 255}, -- light red
    {255, 85, 255, 255}, -- light magenta
    {255, 255, 85, 255}, -- yellow
    {255, 255, 255, 255}, -- white

    __index = function (t, k)
        if t[k] then
            return k
        else
            return {0, 0, 0, 255}
        end
    end
}

-- local function unpack_color(color)
--     local r = band(rshift(color, 16), 0xff);
--     local g = band(rshift(color,  8), 0xff);
--     local b = band((color), 0xff);
--     return {r, g, b, 255}
-- end

function start_vm()
    if machine.enebled then
        machine:shutdown()
        cursor.visible = false
    else
        machine:start()
    end
end

function show_keyboard()
    hud.open_permanent("retro_computers:keyboard")
end

function send_ctrl_alt_del()
    machine.keyboard:send_key("left-ctrl")
    machine.keyboard:send_key("alt")
    machine.keyboard:send_key("delete")
end

function open_inventory()
    hud.open_block(mx, my, mz)
end

local function refresh()
    if machine then
        local height = machine.display.height
        local width = machine.display.width
        if machine.videocard.get_mode() < 4 then
            local cursor_x = machine.display.cursor_x
            local cursor_y = machine.display.cursor_y

            for y = 0, height - 1, 1 do
                for x = 0, width - 1, 1 do
                    local cell = machine.display.buffer[y * width + x] or {0, 0, 15}
                    local index = y * 80 + x
                    -- local bg_index = width * height + index
                    if cell then
                        document[index + 1].src = cache[cell[1]]
                        document[index + 1].color = cga_palette[cell[3] + 1]
                        --document[bg_index + 1].color = cga_palette[char[2] + 1] -- Mnogo lagov
                    else
                        document[index + 1].color = {0, 0, 0, 255}
                    end
                end
            end
            cursor.pos = {cursor_x * 8, cursor_y * 8 + 6}
            cursor.visible = not cursor.visible
        else
            local str = {}
            for y = 0, 199 do
                for x = 0, 639 do
                    local pixel = palette[machine.display.buffer[y * 640 + x]]
                    str[y * 640 + x] = pixel or ' '
                end
                str[y * 640 + 639] = '\n'
            end
            print(table.concat(str))
        end
    end
end

local function set_resolution(x, y)
    last_width = width
    last_height = height
    if (last_width == x) and (last_height == y) then
        return
    end

    width = x
    height = y
    -- local pixels_count = width * height
    -- screen.size = {80 * 8, 25 * 16}
    screen:clear()
    for i = 0, y - 1, 1 do
        for j = 0, x - 1, 1 do
            local index = i * x + j
            -- local bg_index = pixels_count + index
            --screen:add(string.format("<image id='%s' size='%d, %d' pos='%d, %d' color='#000000FF'/>", bg_index + 1, 8 * FONT_SCALE, 8 * FONT_SCALE, 8 * j * FONT_SCALE, 8 * i * FONT_SCALE))
            screen:add(string.format("<image id='%s' size='%d, %d' pos='%d, %d' src='fonts/ibm_pc_8_8/glyphs/0'/>", index + 1, glyph_width * FONT_SCALE, glyph_height * FONT_SCALE, glyph_width * j * FONT_SCALE, glyph_height * i * FONT_SCALE))
        end
    end
end

function on_open(x, y, z)
    machine = vmmanager.get_current_machine()
    if machine then
        machine.display.update = refresh
        machine.is_focused = true
        local block = blocks.get_current_block()
        if block then
            mx = block.pos[1]
            my = block.pos[2]
            mz = block.pos[3]
        end
        if not is_cached then
            for _, v in pairs(cp437) do
                cache[v] = "fonts/ibm_pc_8_8/glyphs/" .. v
            end
            is_cached = true
        end
        set_resolution(machine.display.width, machine.display.height)
    end
end

function on_close()
    hud.close("retro_computers:keyboard")
    if machine then
        machine.display.update = function() end
        machine.is_focused = false
        machine = nil
    end
end