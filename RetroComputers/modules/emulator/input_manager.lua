local manager = {}
local is_pressed = input.is_pressed

-- keyname, ascii code, scancode
local keycodes = {
    ["space"] = {32, 57},
    ["backspace"] = {8, 14},
    ["tab"] = {9, 15},
    ["enter"] = {13, 28},
    ["esc"] = {27, 1},
    ["caps-lock"] = {20, 0x3A},
    ["q"] = {113, 16},
    ["w"] = {119, 17},
    ["e"] = {101, 18},
    ["r"] = {114, 19},
    ["t"] = {116, 20},
    ["y"] = {121, 21},
    ["u"] = {117, 22},
    ["i"] = {105, 23},
    ["o"] = {111, 24},
    ["p"] = {112, 25},
    ["a"] = {97, 30},
    ["s"] = {115, 31},
    ["d"] = {100, 32},
    ["f"] = {102, 33},
    ["g"] = {103, 34},
    ["h"] = {104, 35},
    ["j"] = {106, 36},
    ["k"] = {107, 37},
    ["l"] = {108, 38},
    [";"] = {58, 0x27},
    ["back-slash"] = {92, 0x2B},
    ["z"] = {122, 44},
    ["x"] = {120, 45},
    ["c"] = {99, 46},
    ["v"] = {118, 47},
    ["b"] = {98, 48},
    ["n"] = {110, 49},
    ["m"] = {109, 50},
    [","] = {188, 51},
    ["."] = {46, 52},
    ["/"] = {47, 53},
    ["1"] = {49, 2},
    ["2"] = {50, 3},
    ["3"] = {51, 4},
    ["4"] = {52, 5},
    ["5"] = {53, 6},
    ["6"] = {54, 7},
    ["7"] = {55, 8},
    ["8"] = {56, 9},
    ["9"] = {57, 10},
    ["0"] = {48, 11},
    ["-"] = {45, 0x0C},
    ["left-shift"] = {42, 0x2A},
    ["left"] = {75, 0x4b},
    ["right"] = {77, 0x4d},
    ["up"] = {72, 0x48},
    ["down"] = {0x19, 0x50},
    ["["] = {0, 0x1A},
    ["]"] = {0, 0x1B},
    ["*"] = {42, 0x37},
    ["left-ctrl"] = {65, 0x1D},
    ["left-alt"] = {18, 0x38},
    ["delete"] = {0, 0x53},
    ["kovichki"] = {92, 0x28},
    ["="] = {61, 0x0D},
    ["f1"] = {0, 0x3B},
    ["f2"] = {0, 0x3C},
    ["f3"] = {0, 0x3D},
    ["f4"] = {0, 0x3E},
    ["f5"] = {0, 0x3F},
    ["f6"] = {0, 0x40},
    ["f7"] = {0, 0x41},
    ["f8"] = {0, 0x42},
    ["f9"] = {0, 0x43},
    ["f10"] = {0, 0x44},
    ["page-up"] = {0, 0x49},
    ["page-down"] = {0, 0x51},
    ["insert"] = {0, 0x52},
}

local key_matrix = {}

function manager.update()
    for key, code in pairs(keycodes) do
        if is_pressed("key:" .. key) then
            events.emit("retro_computers:input_manager.key_down", key, code[1], code[2])
            key_matrix[code[2]] = true
        else
            if key_matrix[code[2]] then
                events.emit("retro_computers:input_manager.key_up", key, code[1], code[2])
                key_matrix[code[2]] = false
            end
        end
    end
end

function manager.is_pressed(scancode)
    return key_matrix[scancode]
end

function manager.get_keycode(key)
    return keycodes[key]
end

return manager