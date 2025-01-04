---@diagnostic disable: lowercase-global
local logger = require("retro_computers:logger")
local vmmanager = require("retro_computers:emulator/vmmanager")
local blocks = require("retro_computers:blocks")
local config = require("retro_computers:config")
local libpng = nil

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot
local is_initilized = false
-- Screen
local screen_width = 0
local screen_height = 0
local cols = 0
local rows = 0
local screen = document.screen
local screen_text = document.screen_text
local screen_graphics = document.screen_graphics
local cursor = document.cursor
local framebuffer = {}
local clock = os.clock()
local is_screen_initilized = false
-- Machine
local mx, my, mz
local machine = nil
local old_set_resolution_func = function(width, height, graphics_mode) end
-- Font
local glyph_width, glyph_height = 8, 8

local function unpack_color(color)
    local r = band(rshift(color, 16), 0xFF)
    local g = band(rshift(color,  8), 0xFF)
    local b = band(color, 0xFF)
    return {r, g, b, 255}
end

function start_vm()
    if machine then
        if machine.enabled then
            machine:shutdown()
            cursor.visible = false
        else
            machine:start()
        end
    else
        logger:error("Screen: Machine not found!")
    end
end

function show_keyboard()
    hud.open_permanent("retro_computers:keyboard")
end

function send_ctrl_alt_del()
    if machine then
        machine.components.keyboard:send_key(0x1D)
        machine.components.keyboard:send_key(0x38)
        machine.components.keyboard:send_key(0x53)
        machine.components.keyboard:send_key(0x9D)
        machine.components.keyboard:send_key(0xB8)
        machine.components.keyboard:send_key(0xD3)
    end
end

function open_inventory()
    hud.open_block(mx, my, mz)
end

local function refresh()
    if machine then
        local height = machine.components.display.height
        local width = machine.components.display.width
        local display =  machine.components.display

        if display.textmode then
            local cursor_x = display.cursor_x * glyph_width
            local cursor_y = display.cursor_y * glyph_height + (glyph_height - cursor.size[2])

            local pixels = width * height
            for i = 1, height * cols, 1 do
                local cell = display.char_buffer[i - 1] or {0, 0, 0}
                document[i].src =  machine.components.videocard.font[cell[1]]
                document[i].color = unpack_color(cell[3])

                if config.draw_text_background then
                    document[pixels + i].color = unpack_color(cell[2])
                end
            end

            cursor.pos = {cursor_x, cursor_y}
            cursor.visible = display.cursor_visible
        else
            if libpng then
                if os.clock() - clock >= config.graphics_screen_renderer_delay then
                    for y = 0, height - 1, 1 do
                        for x = 0, width - 1, 1 do
                            local pixel = unpack_color(display.buffer[y * width + x])
                            framebuffer:set(x, y, pixel[1], pixel[2], pixel[3], 255)
                        end
                    end

                    framebuffer:load("gui/screen")
                    clock = os.clock()
                end
            end
        end
    end
end

local function set_resolution(width, height, graphics_mode)
    old_set_resolution_func(width, height, graphics_mode)

    if (screen_width == width) and (screen_height == height) then
        return
    end

    logger:debug("Screen: Set resolution to Width = %d Height = %d, Graphics Mode = %s", width, height, graphics_mode)

    screen_width = width
    screen_height = height

    local viewport = gui.get_viewport()
    document.root.size = viewport

    if graphics_mode then
        screen.size = {width, height}
        screen.pos = {viewport[1] / 2 - screen.size[1] / 2, viewport[2] / 2 - screen.size[2] / 2}
        screen_text.visible = false
        screen_graphics.visible = true
        cursor.visible = false
    else
        screen.size = {width * glyph_width, height * glyph_height}
        screen.pos = {viewport[1] / 2 - screen.size[1] / 2, viewport[2] / 2 - screen.size[2] / 2}
        screen_graphics.visible = false
        screen_text.visible = true
        screen_text.size = {width * glyph_width, height * glyph_height}

        if (cols < width) or (rows < height) then
            cols = width
            rows = height
            screen_text:clear()

            if config.draw_text_background then
                local pixels = width * height

                for y = 0, height - 1, 1 do
                    for x = 0, width - 1, 1 do
                        local bg_index = pixels + y * width + x
                        screen_text:add(string.format("<container id='%d' size='%d, %d' pos='%d, %d' src='fonts/ibm_pc_8_8/glyphs/0'/>", bg_index + 1, glyph_width, glyph_height, glyph_width * x, glyph_height * y))
                    end
                end
            end

            for y = 0, height - 1, 1 do
                for x = 0, width - 1, 1 do
                    local index = y * width + x

                    screen_text:add(string.format("<image id='%d' size='%d, %d' pos='%d, %d' src='fonts/ibm_pc_8_8/glyphs/0'/>", index + 1, glyph_width, glyph_height, glyph_width * x, glyph_height * y))
                end
            end
        end

        cursor.size = {glyph_width, 2 * config.font_scale}

        if not is_screen_initilized then
            is_screen_initilized = true
        end
    end

    -- Control panel
    local panel = document.control_panel
    panel.pos = {screen.wpos[1] + (screen.size[1] / 2 - panel.size[1] / 2), screen.wpos[2] + screen.size[2]}
end

function on_open()
    if not is_initilized then
        is_initilized = true
        if pack.is_installed("libpng") then
            libpng = require("libpng:image")
            framebuffer = libpng:new(640, 200)
        end
    end

    machine = vmmanager.get_current_machine()

    if machine then
        if machine.components.display then
            old_set_resolution_func = machine.components.display.set_resolution
            machine.components.display.update = refresh
            machine.components.display.set_resolution = set_resolution
            machine.is_focused = true
            local block = blocks.get_current_block()

            if block then
                mx = block.pos[1]
                my = block.pos[2]
                mz = block.pos[3]
            end

            glyph_width = machine.components.videocard.glyph_width * config.font_scale + 1
            glyph_height = machine.components.videocard.glyph_height * config.font_scale + 1
            cursor.color = machine.components.videocard.cursor_color

            set_resolution(machine.components.display.width, machine.components.display.height, not machine.components.display.textmode)
        end
    else
        logger:error("Screen: Machine not found!")
    end
end

function on_close()
    hud.close("retro_computers:keyboard")

    if machine then
        if machine.components.display then
            machine.components.display.update = function() end
            machine.components.display.set_resolution = old_set_resolution_func
            machine.is_focused = false
            machine = nil
            glyph_height = 0
            glyph_width = 0

            if is_screen_initilized then
                local pixels = screen_width * screen_height
                for i = 1, pixels - 1, 1 do
                    document[i].src = "fonts/ibm_pc_8_8/glyphs/0"
                    document[i].color = {0, 0, 0, 255}

                    if config.draw_text_background then
                        document[pixels + i - 1].src = "fonts/ibm_pc_8_8/glyphs/0"
                        document[pixels + i - 1].color = {0, 0, 0, 255}
                    end
                end
            end

            cursor.visible = false
        end
    end
end