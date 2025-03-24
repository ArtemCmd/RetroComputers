---@diagnostic disable: lowercase-global
local logger = require("retro_computers:logger")
local config = require("retro_computers:config")
local blocks = require("retro_computers:blocks")
local vmmanager = require("retro_computers:emulator/vmmanager")

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

-- Screen
local screen_width = 0
local screen_height = 0
local cols = 0
local rows = 0
local screen = document.screen
local screen_text = document.screen_text
local screen_graphics = document.screen_graphics
local cursor = document.cursor
local clock = os.clock()
local glyph_width, glyph_height = 8, 8
local start_animation = false
local timer_animation = 255
local cursor_offset_y = 0

-- Machine
local mx, my, mz
local machine = nil
local event_id = 0

local function unpack_color(color)
    local r = band(rshift(color, 16), 0xFF)
    local g = band(rshift(color,  8), 0xFF)
    local b = band(color, 0xFF)

    return {r, g, b, 255}
end

local function refresh()
    if machine then
        local display = machine:get_component("display")
        local videocard = machine:get_component("videocard")
        local height = display.height
        local width = display.width

        if start_animation then
            local animation = document.screen_animation

            animation.color = {0, 0, 0, timer_animation}
            timer_animation = timer_animation - (20 * time.delta())

            if timer_animation < 0 then
                start_animation = false
                timer_animation = 255
            end
        end

        if display.text_mode then
            local cursor_x = display.cursor_x * glyph_width
            local cursor_y = display.cursor_y * glyph_height + cursor_offset_y
            local pixels = width * height

            for i = 1, height * cols, 1 do
                local cell = display.char_buffer[i - 1]
                local screen_cell = document[tostring(i)]

                screen_cell.src = videocard.font[cell[1]]
                screen_cell.color = unpack_color(cell[3])

                if config.screen.draw_text_background then
                    document[tostring(pixels + i)].color = unpack_color(cell[2])
                end
            end

            cursor.pos = {cursor_x, cursor_y}
            cursor.visible = display.cursor_visible
        else
            if (os.clock() - clock) >= config.screen.renderer_delay then
                local canvas = screen_graphics.data

                for y = 0, height - 1, 1 do
                    for x = 0, width - 1, 1 do
                        local pixel = unpack_color(display.buffer[y * width + x])
                        canvas:set(x, height - y, pixel[1], pixel[2], pixel[3], 255)
                    end
                end

                canvas:update()
                clock = os.clock()
            end
        end
    end
end

local function update_cursor(self)
    if machine then
        local videocard = machine:get_component("videocard")
        local old_size = cursor.size

        document.cursor.size = {old_size[1], videocard.cursor_height * config.screen.scale}
        cursor_offset_y = videocard.cursor_offset_y * config.screen.scale
    end
end

local function set_resolution(width, height, graphics_mode)
    if (screen_width == width) and (screen_height == height) then
        return
    end

    logger.debug("Screen: Set resolution to %dx%d, Graphics Mode = %s", width, height, graphics_mode)

    screen_width = width
    screen_height = height

    local viewport = gui.get_viewport()
    document.root.size = viewport

    if graphics_mode then
        screen.size = {width, height}
        screen_text.visible = false
        screen_graphics.visible = true
        cursor.visible = false
    else
        screen.size = {width * glyph_width, height * glyph_height}
        screen_graphics.visible = false

        screen_text.visible = true
        screen_text.size = {width * glyph_width, height * glyph_height}

        if (cols < width) or (rows < height) then
            cols = width
            rows = height
            screen_text:clear()

            local pixels = width * height

            if config.screen.draw_text_background then
                for y = 0, height - 1, 1 do
                    for x = 0, width - 1, 1 do
                        local bg_index = pixels + y * width + x
                        local glyph_x = x * glyph_width
                        local glyph_y = y * glyph_height

                        screen_text:add(string.format("<container id='%d' size='%d, %d' pos='%d, %d'/>", bg_index + 1, glyph_width, glyph_height, glyph_x, glyph_y))
                    end
                end
            end

            for y = 0, height - 1, 1 do
                for x = 0, width - 1, 1 do
                    local index = y * width + x
                    local glyph_x = x * glyph_width
                    local glyph_y = y * glyph_height

                    screen_text:add(string.format("<image id='%d' size='%d, %d' pos='%d, %d' src='fonts/cga_8_8/glyphs/0'/>", index + 1, glyph_width, glyph_height, glyph_x, glyph_y))
                end
            end
        end
    end

    screen.pos = {viewport[1] / 2 - screen.size[1] / 2, viewport[2] / 2 - screen.size[2] / 2}

    -- Control panel
    local panel = document.control_panel
    panel.pos = {screen.wpos[1] + (screen.size[1] / 2 - panel.size[1] / 2), screen.wpos[2] + screen.size[2]}

    -- Power on animation
    local screen_animation = document.screen_animation
    screen_animation.size = screen.size
end

function start_vm()
    if machine then
        if machine.enabled then
            machine:shutdown()
            timer_animation = 255
            start_animation = false
        else
            machine:start()
            start_animation = true
        end

        cursor.visible = false
        refresh()
    else
        logger.error("Screen: Machine not found!")
    end
end

function show_keyboard()
    hud.open_permanent("retro_computers:keyboard")
end

function send_ctrl_alt_del()
    if machine then
        local keyboard = machine:get_component("keyboard")

        if keyboard then
            keyboard:send_key(0x1D)
            keyboard:send_key(0x38)
            keyboard:send_key(0x53)
            keyboard:send_key(0x9D)
            keyboard:send_key(0xB8)
            keyboard:send_key(0xD3)
        end
    end
end

function open_inventory()
    hud.open_block(mx, my, mz)
end

function on_open()
    machine = vmmanager.get_current_machine()

    if machine then
        local videocard = machine:get_component("videocard")
        local display = machine:get_component("display")
        local block = blocks.get_current_block()

        if videocard then
            glyph_width = videocard.glyph_width * config.screen.scale + 1
            glyph_height = videocard.glyph_height * config.screen.scale + 1
            cursor.color = videocard.cursor_color
        end

        if display then
            old_set_resolution_func = display.set_resolution
            display.update = refresh
            display.update_cursor = update_cursor

            event_id = display.events:add_handler(function(event_type, width, height, graphics_mode)
                if event_type == 0 then
                    set_resolution(width, height, graphics_mode)
                end
            end)

            set_resolution(display.width, display.height, not display.text_mode)
        end

        if block then
            mx = block.pos[1]
            my = block.pos[2]
            mz = block.pos[3]
        end

        machine.is_focused = true
    else
        logger.error("Screen: Machine not found!")
    end

    refresh()
end

function on_close()
    hud.close("retro_computers:keyboard")

    if machine then
        local display = machine:get_component("display")

        glyph_height = 0
        glyph_width = 0
        machine.is_focused = false
        cursor.visible = false
        timer_animation = 0

        if display then
            display.update = function() end
            display.update_cursor = function() end

            display.events:remove_handler(event_id)
        end

        machine = nil
    end
end