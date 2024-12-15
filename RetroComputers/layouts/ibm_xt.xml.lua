---@diagnostic disable: lowercase-global
local logger = require("retro_computers:logger")
local vmmanager = require("retro_computers:emulator/vmmanager")
local blocks = require("retro_computers:blocks")
local config = require("retro_computers:config")
local libpng = nil

local is_initilized = false
-- Screen
local screen_width = 0
local screen_height = 0
local screen = document.screen
local cursor = document.cursor

local screen_graphics = {}
local clock = os.clock()
-- Machine
local mx, my, mz
local machine = nil
-- Font
local glyph_width, glyph_height = 0, 0

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
        local height = machine.components.display.height
        local width = machine.components.display.width

        if machine.components.videocard.textmode then
            local cursor_x = screen.pos[1] + (machine.components.display.cursor_x * glyph_width)
            local cursor_y = screen.pos[2] + (machine.components.display.cursor_y * glyph_height + (glyph_height - cursor.size[2]))

            for y = 0, height - 1, 1 do
                for x = 0, width - 1, 1 do
                    local cell = machine.components.display.buffer[y * width + x] or {0, 0, 15}
                    local index = y * width + x
                    -- local bg_index = width * height + index
                    document[index + 1].src =  machine.components.videocard.font[cell[1]]
                    document[index + 1].color = machine.components.videocard.color_palette[cell[3]]
                    -- document[bg_index + 1].color = machine.components.videocard.color_palette[cell[2] + 1]
                end
            end
            cursor.pos = {cursor_x, cursor_y}
            cursor.visible = not cursor.visible
        else
            if libpng then
                if os.clock() - clock >= 0.1  then
                    for y = 0, height - 1, 1 do
                        for x = 0, width - 1, 1 do
                            local pixel = machine.components.videocard.color_palette[machine.components.display.buffer[y * width + x]]
                            screen_graphics:set(x, y, pixel[1], pixel[2], pixel[3], pixel[4])
                        end
                    end

                    screen_graphics:load("gui/screen")
                    clock = os.clock()
                    -- logger:debug("Screen: Render graphics mode")
                end
            else
                local str = {}
                for y = 0, height - 1, 1 do
                    for x = 0, width - 1, 1 do
                        local pixel = palette[machine.components.display.buffer[y * width + x]]
                        str[y * width + x] = pixel
                    end
                    str[y * width + width - 1] = '\n'
                end
                print(table.concat(str))
            end
        end
    end
end

local function set_resolution(width, height, graphics_mode)
    if (screen_width == width) and (screen_height == height) then
        return
    end
    logger:debug("Screen: Set resolution to Width = %d Height = %d, Graphics Mode = %s", width, height, graphics_mode)
    screen_width = width
    screen_height = height

    if graphics_mode then
        local viewport = gui.get_viewport()
        document.root.size = viewport
        screen:clear()
        screen.size = {width, height}
        screen.pos = {viewport[1] / 2 - screen.size[1] / 2, viewport[2] / 2 - screen.size[2] / 2}
        screen.visible = false

        document.screen_graphics.size = {screen.size[1], screen.size[2]}
        document.screen_graphics.pos = {screen.pos[1], screen.pos[2]}
        document.screen_graphics.visible = true

        cursor.visible = false
    else
        local viewport = gui.get_viewport()
        document.root.size = viewport

        -- -- Screen
        document.screen_graphics.visible = false
        screen.visible = true
        screen:clear()
        screen.size = {width * glyph_width, height * glyph_height + 4}
        screen.pos = {viewport[1] / 2 - screen.size[1] / 2, viewport[2] / 2 - screen.size[2] / 2}

        -- local pixels = x * y
        for i = 0, height - 1, 1 do
            for j = 0, width - 1, 1 do
                local index = i * width + j
                -- local bg_index = pixels + index
                -- screen:add(string.format("<image id='%s' size='%d, %d' pos='%d, %d' src='fonts/ibm_pc_8_8/glyphs/0'/>", bg_index + 1, glyph_width, glyph_height, glyph_width * j, glyph_height * i))
                screen:add(string.format("<image id='%s' size='%d, %d' pos='%d, %d' src='fonts/ibm_pc_8_8/glyphs/0'/>", index + 1, glyph_width, glyph_height, glyph_width * j, glyph_height * i))
            end
        end
        cursor.size = {glyph_width, 2 * config.font_scale}
    end
    -- Control panel
    local panel = document.control_panel
    panel.pos = {screen.pos[1] + (screen.size[1] / 2 - panel.size[1] / 2), screen.pos[2] + screen.size[2]}
end

function on_open()
    if not is_initilized then
        is_initilized = true
        if pack.is_installed("libpng") then
            libpng = require("libpng:image")
            screen_graphics = libpng:new(640, 200)
        end
    end
    machine = vmmanager.get_current_machine()
    if machine then
        machine.components.display.update = refresh
        machine.components.display.set_resolution = set_resolution
        machine.is_focused = true
        local block = blocks.get_current_block()
        if block then
            mx = block.pos[1]
            my = block.pos[2]
            mz = block.pos[3]
        end
        glyph_width = machine.components.videocard.glyph_width * config.font_scale
        glyph_height = machine.components.videocard.glyph_height * config.font_scale
        cursor.color = machine.components.videocard.cursor_color
        set_resolution(machine.components.display.width, machine.components.display.height, not machine.components.videocard.textmode)
    else
        logger:error("Screen: Machine not found!")
    end
end

function on_close()
    hud.close("retro_computers:keyboard")
    if machine then
        machine.components.display.update = function() end
        machine.components.display.set_resolution = function() end
        machine.is_focused = false
        machine = nil
        glyph_height = 0
        glyph_width = 0
    end
end