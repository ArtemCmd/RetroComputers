---@diagnostic disable: lowercase-global
local config = require("retro_computers:config")
local vmmanager = require("retro_computers:emulator/vmmanager")
local input_manager = require("retro_computers:emulator/input_manager")

local band, bor, rshift, lshift, bxor, bnot = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor, bit.bnot
local pos = {}
local pressed = false
local initilized = false
local is_pressed = input.is_pressed
local machine = nil
local left_shift = false

-- Char, Key name
local shift_chars = {
    ['Q'] = 'q',
    ['W'] = 'w',
    ['E'] = 'e',
    ['R'] = 'r',
    ['T'] = 't',
    ['Y'] = 'y',
    ['U'] = 'u',
    ['I'] = 'i',
    ['O'] = 'o',
    ['P'] = 'p',
    ['A'] = 'a',
    ['S'] = 's',
    ['D'] = 'd',
    ['F'] = 'f',
    ['G'] = 'g',
    ['H'] = 'h',
    ['J'] = 'j',
    ['K'] = 'k',
    ['L'] = 'l',
    ['Z'] = 'z',
    ['X'] = 'x',
    ['C'] = 'c',
    ['V'] = 'v',
    ['B'] = 'b',
    ['N'] = 'n',
    ['M'] = 'm',
    ['<'] = ',',
    ['>'] = '.',
    ['?'] = '/',
    ['"'] = 'kovichki',
    [':'] = ';',
    ['{'] = '[',
    ['}'] = ']',
    ['|'] = '\\',
    ['!'] = '1',
    ['@'] = '2',
    ['#'] = '3',
    ['$'] = '4',
    ['%'] = '5',
    ['^'] = '6',
    ['&'] = '7',
    ['*'] = '8',
    ['('] = '9',
    [')'] = '0',
    ['_'] = '-'
}

local char_to_keyname = {
    ["\n"] = "enter",
    [" "] = "space",
    ["\\"] = "back-slash",
}

local function update_keyboard()
    local mouse_pos = input.get_mouse_pos()
    local keyboard = document.root

    if (mouse_pos[1] >= keyboard.pos[1]) and (mouse_pos[1] <= keyboard.pos[1] + keyboard.size[1]) and (mouse_pos[2] >= keyboard.pos[2]) and (mouse_pos[2] <= keyboard.pos[2] + keyboard.size[2]) then
        if is_pressed("mouse:left") then
            if not pressed then
                pos = {mouse_pos[1] - keyboard.pos[1], mouse_pos[2] - keyboard.pos[2]}
                pressed = true
            end
        else
            pressed = false
        end

        if pressed then
            keyboard.pos = {mouse_pos[1] - pos[1], mouse_pos[2] - pos[2]}
        end
    end
end

local function send_key(key)
    if machine then
        local scancode = input_manager.get_scancode(key) or 0

        if scancode == 0x2A then
            left_shift = not left_shift
        end

        if left_shift then
            machine.components.keyboard:send_key(0x2A)
            machine.components.keyboard:send_key(scancode)
            machine.components.keyboard:send_key(0xAA)
        else
            machine.components.keyboard:send_key(scancode)
            machine.components.keyboard:send_key(bor(0x80, scancode))
        end
    end
end

function button_key(key)
    audio.play_sound_2d("computer/keyboard", 1.0, 1.0)
    send_key(key)
end

function switch_key(key, button_id)
    local button = document[button_id]
    local old_color = button.color

    button.color = button.hoverColor
    button.hoverColor = old_color

    button_key(key)
end

function button_close()
    hud.close("retro_computers:keyboard")
end

function send_text()
    if machine then
        local clipboard = document.clipboard

        if #clipboard.text > 0 then
            for i = 1, #clipboard.text, 1 do
                local char = clipboard.text:sub(i, i)

                if char_to_keyname[char] then
                    send_key(char_to_keyname[char])
                elseif shift_chars[char] then
                    send_key("left-shift")
                    send_key(shift_chars[char])
                    send_key("left-shift")
                else
                    send_key(char)
                end
            end
        end

        document.clipboard.text = ""
    end
end

function on_open()
    local keyboard = document.root
    local viewport = gui.get_viewport()

    machine = vmmanager.get_current_machine()

    if not initilized then
        initilized = true
        keyboard:setInterval(config.screen_keyboard_delay, update_keyboard)
    end

    keyboard.pos = {viewport[1] / 2 - keyboard.size[1] / 2, viewport[2] / 2 - keyboard.size[2] / 2}

    if machine then
        machine.is_focused = false
    end
end

function on_close()
    document.clipboard.text = ""

    if machine then
        machine.is_focused = true
        machine = nil
    end
end