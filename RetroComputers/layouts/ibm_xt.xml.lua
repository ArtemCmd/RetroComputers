---@diagnostic disable: lowercase-global
local logger = require("retro_computers:logger")
local vmmanager = require("retro_computers:emulator/vmmanager")
local blocks = require("retro_computers:blocks")
local cp437 = require("retro_computers:emulator/cp437")
local config = require("retro_computers:config")

-- Screen
local width, height, last_width, last_height
local screen = document.screen
local cursor = document.cursor
-- Machine
local mx, my, mz
local machine = nil
-- Font
local glyph_width, glyph_height = 8, 8
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
    {255, 255, 255, 255} -- white
}
setmetatable(cga_palette, {
    __index = function (t, k)
        if rawget(t, k) then
            return rawget(t, k)
        end
        return {0, 255, 255, 255}
    end
})

function start_vm()
    if machine then
        if machine.enebled then
            machine:shutdown()
            cursor.visible = false
        else
            machine:start()
        end
    end
end

function show_keyboard()
    hud.open_permanent("retro_computers:keyboard")
end

function send_ctrl_alt_del()
    if machine then
        machine.components.keyboard:send_key("left-ctrl")
        machine.components.keyboard:send_key("alt")
        machine.components.keyboard:send_key("delete")
    end
end

function open_inventory()
    hud.open_block(mx, my, mz)
end

local function refresh()
    if machine then
        local height = machine.display.height
        local width = machine.display.width
        if machine.components.videocard:get_mode() < 4 then
            local cursor_x = screen.pos[1] + (machine.display.cursor_x * glyph_width)
            local cursor_y = screen.pos[2] + (machine.display.cursor_y * glyph_height + (glyph_height - cursor.size[2]))

            for y = 0, height - 1, 1 do
                for x = 0, width - 1, 1 do
                    local cell = machine.display.buffer[y * width + x] or {0, 0, 15}
                    local index = y * width + x
                    -- local bg_index = width * height + index
                    if cell then
                        document[index + 1].src = cache[cell[1]]
                        document[index + 1].color = cga_palette[cell[3] + 1]
                        -- document[bg_index + 1].color = cga_palette[cell[2] + 1]
                    else
                        document[index + 1].color = {0, 0, 0, 255}
                    end
                end
            end
            cursor.pos = {cursor_x, cursor_y}
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

    -- Apply scale
    glyph_width = glyph_width * config.font_scale
    glyph_height = glyph_height * config.font_scale


    local viewport = gui.get_viewport()
    document.root.size = viewport

    -- Screen
    screen:clear()
    screen.size = {x * glyph_width, y * glyph_height + 4}
    screen.wpos = {viewport[1] / 2 - screen.size[1] / 2, viewport[2] / 2 - screen.size[2] / 2}
    -- local pixels = x * y
    for i = 0, y - 1, 1 do
        for j = 0, x - 1, 1 do
            local index = i * x + j
            -- local bg_index = pixels + index
            -- screen:add(string.format("<image id='%s' size='%d, %d' pos='%d, %d' src='fonts/ibm_pc_8_8/glyphs/0'/>", bg_index + 1, glyph_width, glyph_height, glyph_width * j, glyph_height * i))
            screen:add(string.format("<image id='%s' size='%d, %d' pos='%d, %d' src='fonts/ibm_pc_8_8/glyphs/0'/>", index + 1, glyph_width, glyph_height, glyph_width * j, glyph_height * i))
        end
    end
    cursor.size = {glyph_width, 2 * config.font_scale}

    -- Control panel
    local panel = document.control_panel
    panel.pos = {screen.pos[1] + (screen.size[1] / 2 - panel.size[1] / 2), screen.pos[2] + screen.size[2]}
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
            setmetatable(cache, {
                __index = function (t, k)
                    if rawget(t, k) then
                        return rawget(t, k)
                    else
                        return "fonts/ibm_pc_8_8/glyphs/0"
                    end
                end
            })
            is_cached = true
        end
        set_resolution(machine.display.width, machine.display.height)
    else
        logger:error("Machine not found!")
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