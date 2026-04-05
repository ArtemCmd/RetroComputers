local logger = require("dave_logger:logger")("RetroComputers")
local config = require("retro_computers:config")
local input_manager = require("retro_computers:input_manager")
local vmmanager = require("retro_computers:vmmanager")

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot

-- Screen
local screen_width = 0
local screen_height = 0
local canvas_width = 0
local canvas_height = 0
local screen_scale_x = 0
local screen_scale_y = 0
local start_animation = false
local alpha_animation = 255
local initialized = false

-- Debug
local last_time = 0
local fps = 0

-- Machine
local mx, my, mz
local machine = nil
local events_ids = {}
local key_matrix = {}
local key_time = 0
local device_keyboard
local device_mouse

-- Keyboard
local left_shift = false
local shift_chars = {
    ['Q'] = 'key:q',
    ['W'] = 'key:w',
    ['E'] = 'key:e',
    ['R'] = 'key:r',
    ['T'] = 'key:t',
    ['Y'] = 'key:y',
    ['U'] = 'key:u',
    ['I'] = 'key:i',
    ['O'] = 'key:o',
    ['P'] = 'key:p',
    ['A'] = 'key:a',
    ['S'] = 'key:s',
    ['D'] = 'key:d',
    ['F'] = 'key:f',
    ['G'] = 'key:g',
    ['H'] = 'key:h',
    ['J'] = 'key:j',
    ['K'] = 'key:k',
    ['L'] = 'key:l',
    ['Z'] = 'key:z',
    ['X'] = 'key:x',
    ['C'] = 'key:c',
    ['V'] = 'key:v',
    ['B'] = 'key:b',
    ['N'] = 'key:n',
    ['M'] = 'key:m',
    ['<'] = 'key:comma',
    ['>'] = 'key:period',
    ['?'] = 'key:slash',
    ['"'] = 'key:apostrophe',
    [':'] = 'key:semicolon',
    ['{'] = 'key:left-bracket',
    ['}'] = 'key:right-bracket',
    ['|'] = 'key:backslash',
    ['!'] = 'key:1',
    ['@'] = 'key:2',
    ['#'] = 'key:3',
    ['$'] = 'key:4',
    ['%'] = 'key:5',
    ['^'] = 'key:6',
    ['&'] = 'key:7',
    ['*'] = 'key:8',
    ['('] = 'key:9',
    [')'] = 'key:0',
    ['_'] = 'key:minus',
    ["+"] = "key:equal"
}
local char2key = {
    ["\n"] = "key:enter",
    [" "] = "key:space",
    ["\\"] = "key:backslash",
    ["'"] = "key:apostrophe",
    ["["] = "key:left-bracket",
    ["]"] = "key:right-bracket",
    ["`"] = "key:grave-accent",
    ["*"] = "key:kp-multiply",
    ["/"] = "key:slash",
    ["."] = "key:period",
    [","] = "key:comma",
    [";"] = "key:semicolon",
    ["-"] = "key:minus",
    ["="] = "key:equal"
}

local canvas = Canvas({640, 200})

local function update()
    if start_animation then
        local animation = document.screen_animation

        animation.color = {0, 0, 0, alpha_animation}
        alpha_animation = alpha_animation - (60 * time.delta())

        if alpha_animation < 0 then
            start_animation = false
            alpha_animation = 255
        end
    else
        document.screen_animation:setInterval(1000000, function()end)
        document.screen_animation.visible = false
    end
end

local function refresh(screen)
    canvas:set_data(screen.buffer)
    canvas:update()
end

local function refresh_debug(screen)
    if (os.clock() - last_time) >= 1.0 then
        document.fps_counter.text = string.format("FPS: %d", fps)
        fps = 0
        last_time = os.clock()
    end

    canvas:set_data(screen.buffer)
    canvas:update()

    fps = fps + 1
end

local function set_canvas_resolution(width, height)
    if (canvas_width ~= width) or (canvas_height ~= height) then
        canvas_width = width
        canvas_height = height
        canvas = Canvas({width, height})
        canvas:create_texture("gui/screen")
    end
end

local function set_resolution(width, height, scale_x, scale_y)
    if (screen_width == width) and (screen_height == height) and (screen_scale_x == scale_x) and (screen_scale_y == scale_y) then
        return
    end

    logger:debug("Screen: Set resolution to %dx%d", width, height)

    local viewport = gui.get_viewport()
    local panel = document.control_panel
    local screen_animation = document.screen_animation
    local screen_graphics = document.screen_graphics
    local screen = document.screen
    local root = document.root

    screen.size = {width * scale_x, height * scale_y}
    screen_graphics.size = screen.size
    screen_animation.size = screen.size
    root.size = {math.max(screen.size[1], panel.size[1]), screen.size[2] + panel.size[2]}
    root.pos = {viewport[1] / 2 - root.size[1] / 2, viewport[2] / 2 - root.size[2] / 2}
    panel.pos = {(root.size[1] / 2 - panel.size[1] / 2), screen.size[2]}
    screen.pos = {root.size[1] / 2 - screen.size[1] / 2, screen.pos[2]}

    screen_width = width
    screen_height = height
    screen_scale_x = scale_x
    screen_scale_y = scale_y
end

local function send_key(key)
    local scancode = input_manager.get_scancode(key) or 0x00
---@diagnostic disable-next-line: need-check-nil, undefined-field
    local keyboard = machine:get_device("keyboard")

    if not keyboard.push_key then
        return
    end

    if left_shift then
        keyboard:push_key(0x2A)
        keyboard:push_key(scancode)
        keyboard:push_key(bor(0x80, scancode))
        keyboard:push_key(0xAA)
    else
        keyboard:push_key(scancode)
        keyboard:push_key(bor(0x80, scancode))
    end

    if scancode == 0x2A then
        left_shift = not left_shift
    end
end

function start_vm()
    if machine then
        if machine:is_running() then
            machine:stop()

            alpha_animation = 255
            start_animation = false

            set_resolution(640, 200, 1.0, 1.0)
        else
            local screen = machine:get_device("screen")

            machine:start()
            start_animation = true
            document.screen_animation:setInterval(100, update)

            set_canvas_resolution(screen.width, screen.height)
            set_resolution(screen.width, screen.height, screen.scale_x, screen.scale_y)
        end

        refresh(machine:get_device("screen"))
    end
end

function show_keyboard()
    input_manager.set_enabled(false)
    hud.open_permanent("dave_keyboard:keyboard")
end

function send_ctrl_alt_del()
    if machine then
        local keyboard = machine:get_device("keyboard")

        if keyboard and keyboard.push_key then
            keyboard:push_key(0x1D)
            keyboard:push_key(0x38)
            keyboard:push_key(0x53)
            keyboard:push_key(0x9D)
            keyboard:push_key(0xB8)
            keyboard:push_key(0xD3)
        end
    end
end

function open_inventory()
    hud.open_block(mx, my, mz)
end

function on_open(_, x, y, z)
    if not initialized then
        initialized = true

        if config.debug.show_fps then
            document.fps_counter.visible = true
            refresh = refresh_debug
        else
            document.fps_counter.visible = false
        end

        events.on("dave_keyboard:keyboard.close", function()
            input_manager.set_enabled(true)
        end)

        events.on("dave_keyboard:keyboard.key_pressed", function(key)
            if machine then
                send_key(key)
            end
        end)

        events.on("dave_keyboard:keyboard.send_text", function(text)
            if machine then
                if #text > 0 then
                    for i = 1, #text, 1 do
                        local char = text:sub(i, i)

                        if char2key[char] then
                            send_key(char2key[char])
                        elseif shift_chars[char] then
                            send_key("key:left-shift")
                            send_key(shift_chars[char])
                            send_key("key:left-shift")
                        else
                            send_key("key:" .. char)
                        end
                    end
                end
            end
        end)

        events.on("retro_computers:input_manager.key_down",  function(key, code)
            if (not device_keyboard) or config.input.ignore_keys[key] then
                return
            end

            if key_matrix[code] then
                if time.uptime() > key_time then
                    device_keyboard:send(code)
                end
            else
                device_keyboard:send(code)

                key_matrix[code] = true
                key_time = time.uptime() + 0.5
            end
        end)

        events.on("retro_computers:input_manager.key_up", function(key, code)
            if (not device_keyboard) or config.input.ignore_keys[key] then
                return
            end

            audio.play_sound_2d("computer/keyboard", 1.0, 1.0)
            device_keyboard:send(bor(code, 0x80))

            key_matrix[code] = false
        end)

        events.on("retro_computers:input_manager.mouse_state_changed", function(delta_x, delta_y, left_pressed, middle_pressed, right_pressed)
            if device_mouse then
                device_mouse:update_mouse_state(delta_x, delta_y, left_pressed, middle_pressed, right_pressed)
            end
        end)
    end

    local machine_id = block.get_field(x, y, z, "vm_id")

    if machine_id then
        machine = vmmanager.get_machine_by_id(machine_id)

        if machine then
            local screen = machine:get_device("screen")

            if screen then
                screen.update = refresh

                table.insert(events_ids, 1, screen.events:add_handler(1, function(event_type, width, height)
                    set_canvas_resolution(width, height)
                    set_resolution(width, height, screen.scale_x, screen.scale_y)
                end))

                table.insert(events_ids, 1, screen.events:add_handler(2, function(event_type, scale_x, scale_y)
                    set_resolution(screen.width, screen.height, scale_x, scale_y)
                end))

                set_canvas_resolution(screen.width, screen.height)
                set_resolution(screen.width, screen.height, screen.scale_x, screen.scale_y)
            end

            input_manager.set_enabled(true)
            mx, my, mz = x, y, z

            device_keyboard = machine:get_device("keyboard")
            device_mouse = machine:get_device("mouse")

            refresh(machine:get_device("screen"))
        else
            logger:error("Screen: Machine not found!")
        end
    end
end

function on_close()
    hud.close("dave_keyboard:keyboard")

    if machine then
        local screen = machine:get_device("screen")
        alpha_animation = 0

        if screen then
            screen.update = function() end
            screen.events:remove_handler(1, table.remove(events_ids))
            screen.events:remove_handler(2, table.remove(events_ids))
        end

        device_keyboard = nil
        device_mouse = nil

        machine = nil
    end

    input_manager.set_enabled(false)
end
