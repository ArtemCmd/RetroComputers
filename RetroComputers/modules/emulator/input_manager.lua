local manager = {}

local scancodes = {
    ["key:space"] = 0x39,
    ["key:backspace"] = 0x0E,
    ["key:tab"] = 0x0F,
    ["key:enter"] = 0x1C,
    ["key:escape"] = 0x01,
    ["key:caps-lock"] = 0x3A,
    ["key:q"] = 0x10,
    ["key:w"] = 0x11,
    ["key:e"] = 0x12,
    ["key:r"] = 0x13,
    ["key:t"] = 0x14,
    ["key:y"] = 0x15,
    ["key:u"] = 0x16,
    ["key:i"] = 0x17,
    ["key:o"] = 0x18,
    ["key:p"] = 0x19,
    ["key:a"] = 0x1E,
    ["key:s"] = 0x1F,
    ["key:d"] = 0x20,
    ["key:f"] = 0x21,
    ["key:g"] = 0x22,
    ["key:h"] = 0x23,
    ["key:j"] = 0x24,
    ["key:k"] = 0x25,
    ["key:l"] = 0x26,
    ["key:semicolon"] = 0x27,
    ["key:backslash"] = 0x2B,
    ["key:z"] = 0x2C,
    ["key:x"] = 0x2D,
    ["key:c"] = 0x2E,
    ["key:v"] = 0x2F,
    ["key:b"] = 0x30,
    ["key:n"] = 0x31,
    ["key:m"] = 0x32,
    ["key:comma"] = 0x33,
    ["key:period"] = 0x34,
    ["key:slash"] = 0x35,
    ["key:1"] = 0x02,
    ["key:2"] = 0x03,
    ["key:3"] = 0x04,
    ["key:4"] = 0x05,
    ["key:5"] = 0x06,
    ["key:6"] = 0x07,
    ["key:7"] = 0x08,
    ["key:8"] = 0x09,
    ["key:9"] = 0x0A,
    ["key:0"] = 0x0B,
    ["key:minus"] = 0x0C,
    ["key:left-shift"] = 0x2A,
    ["key:right-shift"] = 0x36,
    ["key:left"] = 0x4B,
    ["key:right"] = 0x4D,
    ["key:up"] = 0x48,
    ["key:down"] = 0x50,
    ["key:left-bracket"] = 0x1A,
    ["key:right-bracket"] = 0x1B,
    ["key:kp-multiply"] = 0x37,
    ["key:left-ctrl"] = 0x1D,
    ["key:right-ctrl"] = 0x1D,
    ["key:left-alt"] = 0x38,
    ["key:right-alt"] = 0x38,
    ["key:delete"] = 0x53,
    ["key:apostrophe"] = 0x28,
    ["key:equal"] = 0x0D,
    ["key:f1"] = 0x3B,
    ["key:f2"] = 0x3C,
    ["key:f3"] = 0x3D,
    ["key:f4"] = 0x3E,
    ["key:f5"] = 0x3F,
    ["key:f6"] = 0x40,
    ["key:f7"] = 0x41,
    ["key:f8"] = 0x42,
    ["key:f9"] = 0x43,
    ["key:f10"] = 0x44,
    ["key:f11"] = 0x85,
    ["key:f12"] = 0x86,
    ["key:page-up"] = 0x49,
    ["key:page-down"] = 0x51,
    ["key:insert"] = 0x52,
    ["key:grave-accent"] = 0x29,
    ["key:kp-add"] = 0x4E,
    ["key:kp-minus"] = 0x4A,
    ["key:kp-divide"] = 0x35,
    ["key:kp-enter"] = 0x1C,
    ["key:kp-0"] = 0x52,
    ["key:kp-1"] = 0x4F,
    ["key:kp-2"] = 0x50,
    ["key:kp-3"] = 0x51,
    ["key:kp-4"] = 0x4B,
    ["key:kp-5"] = 0x4C,
    ["key:kp-6"] = 0x4D,
    ["key:kp-7"] = 0x47,
    ["key:kp-8"] = 0x48,
    ["key:kp-9"] = 0x49,
    ["key:menu"] = 0x5D,
    ["key:left-win"] = 0x5B,
    ["key:right-win"] = 0x5C,
    ["key:print-screen"] = 0x37,
    ["key:home"] = 0x47,
    ["key:end"] = 0x4F,
    ["key:numlock"] = 0x45,
    ["key:scroll-lock"] = 0x46
}
local key_matrix = {}
local enabled = false
local mouse_left = false
local mouse_middle = false
local mouse_right = false
local any_key_pressed = false
local current_key = 0x00
local last_mouse_pos = {0, 0}

function manager.update()
    if enabled then
        any_key_pressed = false
        current_key = 0x00

        for key, scancode in pairs(scancodes) do
            if input.is_pressed(key) then
                events.emit("retro_computers:input_manager.key_down", key, scancode)
                current_key = scancode
                any_key_pressed = true
                key_matrix[key] = true
            else
                if key_matrix[key] then
                    events.emit("retro_computers:input_manager.key_up", key, scancode)
                    key_matrix[key] = false
                end
            end
        end

        local mouse_pos = input.get_mouse_pos()
        local left_pressed = input.is_pressed("mouse:left")
        local middle_pressed = input.is_pressed("mouse:middle")
        local right_pressed = input.is_pressed("mouse:right")

        if (mouse_pos[1] ~= last_mouse_pos[1]) or (mouse_pos[2] ~= last_mouse_pos[2]) or (left_pressed ~= mouse_left) or (middle_pressed ~= mouse_middle) or (right_pressed ~= mouse_right) then
            events.emit("retro_computers:input_manager.mouse_state_changed", mouse_pos[1] - last_mouse_pos[1], mouse_pos[2] - last_mouse_pos[2], mouse_left, mouse_middle, mouse_right)

            last_mouse_pos[1] = mouse_pos[1]
            last_mouse_pos[2] = mouse_pos[2]
            mouse_left = left_pressed
            mouse_middle = middle_pressed
            mouse_right = right_pressed
        end
    end
end

function manager.is_pressed(key)
    return key_matrix[key]
end

function manager.get_current_key()
    return current_key
end

function manager.is_any_key_pressed()
    return any_key_pressed
end

function manager.get_scancode(key)
    return scancodes[key]
end

function manager.set_enabled(val)
    enabled = val
    any_key_pressed = false
    current_key = 0x00
end

return manager
