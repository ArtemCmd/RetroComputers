---@diagnostic disable: lowercase-global

local config = require("retro_computers:config")
local vmmanager = require("retro_computers:emulator/vmmanager")

local pos = {}
local pressed = false
local initilized = false
local is_pressed = input.is_pressed
local machine = nil

local function update_virtual_keyboard()
    local mouse_pos = input.get_mouse_pos()
    local keyboard = document.sc_keyboard

    if mouse_pos[1] >= keyboard.pos[1] and mouse_pos[1] <= keyboard.pos[1] + keyboard.size[1] and mouse_pos[2] >= keyboard.pos[2] and mouse_pos[2] <= keyboard.pos[2] + keyboard.size[2] then
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

function button_key(key)
    if machine then
        machine.keyboard:send_key(key)
    end
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
                if char == "\n" then
                    machine.keyboard:send_key("enter")
                else
                    machine.keyboard:send_key(char)
                end
            end
        end
        document.clipboard.text = ""
    end
end

function on_open()
    local keyboard = document.sc_keyboard
    if not initilized then
        keyboard:setInterval(config.screen_keyboard_delay, update_virtual_keyboard)
        initilized = true
    end
    local viewport = gui.get_viewport()
    keyboard.pos = {viewport[1] / 2 - keyboard.size[1] / 2, viewport[2] / 2 - keyboard.size[2] / 2}
    machine = vmmanager.get_machine(1)
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