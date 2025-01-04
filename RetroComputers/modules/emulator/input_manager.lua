local is_pressed = input.is_pressed

-- Key name, scancode
local scancodes = {
    ["space"] = 0x39,
    ["backspace"] = 0x0E,
    ["tab"] = 0x0F,
    ["enter"] = 0x1C,
    ["esc"] = 0x01,
    ["caps-lock"] = 0x3A,
    ["q"] = 0x10,
    ["w"] = 0x11,
    ["e"] = 0x12,
    ["r"] = 0x13,
    ["t"] = 0x14,
    ["y"] = 0x15,
    ["u"] = 0x16,
    ["i"] = 0x17,
    ["o"] = 0x18,
    ["p"] = 0x19,
    ["a"] = 0x1E,
    ["s"] = 0x1F,
    ["d"] = 0x20,
    ["f"] = 0x21,
    ["g"] = 0x22,
    ["h"] = 0x23,
    ["j"] = 0x24,
    ["k"] = 0x25,
    ["l"] = 0x26,
    [";"] = 0x27,
    ["back-slash"] = 0x2B,
    ["z"] = 0x2C,
    ["x"] = 0x2D,
    ["c"] = 0x2E,
    ["v"] = 0x2F,
    ["b"] = 0x30,
    ["n"] = 0x31,
    ["m"] = 0x32,
    [","] = 0x33,
    ["."] = 0x34,
    ["/"] = 0x35,
    ["1"] = 0x02,
    ["2"] = 0x03,
    ["3"] = 0x04,
    ["4"] = 0x05,
    ["5"] = 0x06,
    ["6"] = 0x07,
    ["7"] = 0x08,
    ["8"] = 0x09,
    ["9"] = 0x0A,
    ["0"] = 0x0B,
    ["-"] = 0x0C,
    ["left-shift"] = 0x2A,
    ["left"] = 0x4B,
    ["right"] = 0x4D,
    ["up"] = 0x48,
    ["down"] = 0x50,
    ["["] = 0x1A,
    ["]"] = 0x1B,
    ["*"] = 0x37,
    ["left-ctrl"] = 0x1D,
    ["left-alt"] = 0x38,
    ["delete"] = 0x53,
    ["kovichki"] = 0x28,
    ["="] = 0x0D,
    ["f1"] = 0x3B,
    ["f2"] = 0x3C,
    ["f3"] = 0x3D,
    ["f4"] = 0x3E,
    ["f5"] = 0x3F,
    ["f6"] = 0x40,
    ["f7"] = 0x41,
    ["f8"] = 0x42,
    ["f9"] = 0x43,
    ["f10"] = 0x44,
    ["page-up"] = 0x49,
    ["page-down"] = 0x51,
    ["insert"] = 0x52
}
local key_matrix = {}

local manager = {}

function manager.update()
    for keyname, scancode in pairs(scancodes) do
        if is_pressed("key:" .. keyname) then
            events.emit("retro_computers:input_manager.key_down", keyname, scancode)
            key_matrix[scancode] = true
        else
            if key_matrix[scancode] then
                events.emit("retro_computers:input_manager.key_up", keyname, scancode)
                key_matrix[scancode] = false
            end
        end
    end
end

function manager.is_pressed(scancode)
    return key_matrix[scancode]
end

function manager.get_scancode(keyname)
    return scancodes[keyname]
end

return manager