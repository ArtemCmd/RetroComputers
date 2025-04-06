---@diagnostic disable: lowercase-global, undefined-field
local logger = require("retro_computers:logger")
local blocks = require("retro_computers:blocks")
local vmmanager = require("retro_computers:emulator/vmmanager")

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

-- Screen
local screen_graphics = document.screen_graphics
local screen_width = 0
local screen_height = 0
local start_animation = false
local timer_animation = 255

-- Machine
local mx, my, mz
local machine = nil
local event_id = 0

local function refresh()
---@diagnostic disable-next-line: need-check-nil
    local screen = machine:get_component("screen")
    local canvas = screen_graphics.data

    if start_animation then
        local animation = document.screen_animation

        animation.color = {0, 0, 0, timer_animation}
        timer_animation = timer_animation - (20 * time.delta())

        if timer_animation < 0 then
            start_animation = false
            timer_animation = 255
        end
    end

    canvas:set_data(screen.buffer)
    canvas:update()
end

local function set_resolution(width, height)
    if (screen_width == width) and (screen_height == height) then
        return
    end

    logger.debug("Screen: Set resolution to %dx%d", width, height)

    local viewport = gui.get_viewport()
    local panel = document.control_panel
    local screen_animation = document.screen_animation
    local screen = document.screen
    local canvas = screen_graphics.data
    local root = document.root

    screen.size = {width, height}
    screen_graphics.size = screen.size
    canvas.width = width
    canvas.height = height

    panel.pos = {(screen.size[1] / 2 - panel.size[1] / 2), screen.size[2]}
    screen_animation.size = screen.size

    root.size = {screen.size[1], screen.size[2] + panel.size[2]}
    root.pos = {viewport[1] / 2 - root.size[1] / 2, viewport[2] / 2 - root.size[2] / 2}

    screen_width = width
    screen_height = height
end

function start_vm()
    if machine then
        if machine.enabled then
            machine:shutdown()

            timer_animation = 255
            start_animation = false

            set_resolution(640, 200)
        else
            machine:start()
            start_animation = true
        end

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
        local screen = machine:get_component("screen")
        local block = blocks.get_current_block()

        if screen then
            screen.update = refresh

            event_id = screen.events:add_handler(function(event_type, width, height)
                if event_type == 0 then
                    set_resolution(width, height)
                end
            end)

            set_resolution(screen.width, screen.height)
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
        local screen = machine:get_component("screen")

        machine.is_focused = false
        timer_animation = 0

        if screen then
            screen.update = function() end
            screen.events:remove_handler(event_id)
        end

        machine = nil
    end
end