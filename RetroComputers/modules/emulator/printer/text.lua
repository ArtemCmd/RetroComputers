local logger = require("retro_computers:logger")
local config = require("retro_computers:config")
local printer = {}

local glyphs = {
    ["0"] = {
        { 1, 1, 1 },
        { 1, 0, 1 },
        { 1, 0, 1 },
        { 1, 0, 1 },
        { 1, 1, 1 },
    },
    ["1"] = {
        { 0, 1, 0 },
        { 1, 1, 0 },
        { 0, 1, 0 },
        { 0, 1, 0 },
        { 1, 1, 1 },
    },
    ["2"] = {
        { 1, 1, 1 },
        { 0, 0, 1 },
        { 1, 1, 1 },
        { 1, 0, 0 },
        { 1, 1, 1 },
    },
    ["3"] = {
        { 1, 1, 1 },
        { 0, 0, 1 },
        { 1, 1, 1 },
        { 0, 0, 1 },
        { 1, 1, 1 },
    },
    ["4"] = {
        { 1, 0, 1 },
        { 1, 0, 1 },
        { 1, 1, 1 },
        { 0, 0, 1 },
        { 0, 0, 1 },
    },
    ["5"] = {
        { 1, 1, 1 },
        { 1, 0, 0 },
        { 1, 1, 1 },
        { 0, 0, 1 },
        { 1, 1, 1 },
    },
    ["6"] = {
        { 1, 1, 1 },
        { 1, 0, 0 },
        { 1, 1, 1 },
        { 1, 0, 1 },
        { 1, 1, 1 },
    },
    ["7"] = {
        { 1, 1, 1 },
        { 0, 0, 1 },
        { 0, 0, 1 },
        { 0, 0, 1 },
        { 0, 0, 1 },
    },
    ["8"] = {
        { 1, 1, 1 },
        { 1, 0, 1 },
        { 1, 1, 1 },
        { 1, 0, 1 },
        { 1, 1, 1 },
    },
    ["9"] = {
        { 1, 1, 1 },
        { 1, 0, 1 },
        { 1, 1, 1 },
        { 0, 0, 1 },
        { 1, 1, 1 },
    },




    ["a"] = {
        { 0, 1, 1, 0 },
        { 1, 0, 0, 1 },
        { 1, 1, 1, 1 },
        { 1, 0, 0, 1 },
        { 1, 0, 0, 1 },
    },
    ["b"] = {
        { 1, 1, 1, 0},
        { 1, 0, 0, 1},
        { 1, 1, 1, 0},
        { 1, 0, 0, 1},
        { 1, 1, 1, 1},
    },
    ["c"] = {
        { 0, 1, 1, 1 },
        { 1, 0, 0, 0 },
        { 1, 0, 0, 0 },
        { 1, 0, 0, 0 },
        { 0, 1, 1, 1 },
    },
    ["d"] = {
        { 1, 1, 1, 1, 0 },
        { 0, 1, 0, 0, 1 },
        { 0, 1, 0, 0, 1 },
        { 0, 1, 0, 0, 1 },
        { 1, 1, 1, 1, 0 },
    },
    ["e"] = {
        { 1, 1, 1, 1 },
        { 1, 0, 0, 0 },
        { 1, 1, 1, 0 },
        { 1, 0, 0, 0 },
        { 1, 1, 1, 1 },
    },
    ["f"] = {
        { 1, 1, 1, 1 },
        { 1, 0, 0, 0 },
        { 1, 1, 1, 0 },
        { 1, 0, 0, 0 },
        { 1, 0, 0, 0 },
    },
    ["g"] = {
        { 0, 1, 1, 1},
        { 1, 0, 0, 0},
        { 1, 0, 1, 1},
        { 1, 0, 0, 1},
        { 0, 1, 1, 1},
    },
    ["h"] = {
        { 1, 0, 0, 1},
        { 1, 0, 0, 1},
        { 1, 1, 1, 1},
        { 1, 0, 0, 1},
        { 1, 0, 0, 1},
    },
    ["i"] = {
        { 1, 1, 1},
        { 0, 1, 0},
        { 0, 1, 0},
        { 0, 1, 0},
        { 1, 1, 1},
    },
    ["j"] = {
        { 0, 0, 1},
        { 0, 0, 1},
        { 0, 0, 1},
        { 1, 0, 1},
        { 0, 1, 0},
    },
    ["k"] = {
        { 1, 0, 0, 1},
        { 1, 0, 1, 0},
        { 1, 1, 0, 0},
        { 1, 0, 1, 0},
        { 1, 0, 0, 1},
    },
    ["l"] = {
        { 1, 0, 0},
        { 1, 0, 0},
        { 1, 0, 0},
        { 1, 0, 0},
        { 1, 1, 1},
    },
    ["m"] = {
        { 1, 0, 0, 0, 1 },
        { 1, 1, 0, 1, 1 },
        { 1, 0, 1, 0, 1 },
        { 1, 0, 0, 0, 1 },
        { 1, 0, 0, 0, 1 },
    },
    ["n"] = {
        { 1, 0, 0, 0, 1 },
        { 1, 1, 0, 0, 1 },
        { 1, 0, 1, 0, 1 },
        { 1, 0, 0, 1, 1 },
        { 1, 0, 0, 0, 1 },
    },
    ["o"] = {
        { 0, 1, 1, 0},
        { 1, 0, 0, 1},
        { 1, 0, 0, 1},
        { 1, 0, 0, 1},
        { 0, 1, 1, 0},
    },
    ["p"] = {
        { 1, 1, 1, 0 },
        { 1, 0, 0, 1 },
        { 1, 1, 1, 0 },
        { 1, 0, 0, 0 },
        { 1, 0, 0, 0 },
    },
    ["q"] = {
        { 0, 1, 1, 0},
        { 1, 0, 0, 1},
        { 1, 0, 0, 1},
        { 1, 0, 1, 1},
        { 0, 1, 1, 0},
    },
    ["r"] = {
        { 1, 1, 1, 0},
        { 1, 0, 0, 1},
        { 1, 1, 1, 0},
        { 1, 0, 0, 1},
        { 1, 0, 0, 1},
    },
    ["s"] = {
        { 0, 1, 1, 1},
        { 1, 0, 0, 0},
        { 0, 1, 1, 0},
        { 0, 0, 0, 1},
        { 1, 1, 1, 0},
    },
    ["t"] = {
        { 1, 1, 1, 1, 1 },
        { 0, 0, 1, 0, 0 },
        { 0, 0, 1, 0, 0 },
        { 0, 0, 1, 0, 0 },
        { 0, 0, 1, 0, 0 },
    },
    ["u"] = {
        { 1, 0, 0, 1},
        { 1, 0, 0, 1},
        { 1, 0, 0, 1},
        { 1, 0, 0, 1},
        { 0, 1, 1, 0},
    },
    ["v"] = {
        { 1, 0, 0, 0, 1 },
        { 1, 0, 0, 0, 1 },
        { 1, 0, 0, 0, 1 },
        { 0, 1, 0, 1, 0 },
        { 0, 0, 1, 0, 0 },
    },
    ["w"] = {
        { 1, 0, 0, 0, 1 },
        { 1, 0, 0, 0, 1 },
        { 1, 0, 1, 0, 1 },
        { 1, 0, 1, 0, 1 },
        { 0, 1, 0, 1, 0 },
    },
    ["x"] = {
        { 1, 0, 0, 0, 1 },
        { 0, 1, 0, 1, 0 },
        { 0, 0, 1, 0, 0 },
        { 0, 1, 0, 1, 0 },
        { 1, 0, 0, 0, 1 },
    },
    ["y"] = {
        { 1, 0, 0, 1 },
        { 1, 0, 0, 1 },
        { 0, 1, 1, 1 },
        { 0, 0, 0, 1 },
        { 1, 1, 1, 0 },
    },
    ["z"] = {
        { 1, 1, 1, 1, 1 },
        { 0, 0, 0, 1, 0 },
        { 0, 0, 1, 0, 0 },
        { 0, 1, 0, 0, 0 },
        { 1, 1, 1, 1, 1 },
    },
    ["а"] = {
        { 0, 1, 1, 0 },
        { 1, 0, 0, 1 },
        { 1, 1, 1, 1 },
        { 1, 0, 0, 1 },
        { 1, 0, 0, 1 },
    },
    ["б"] = {
        { 1, 1, 1, 1 },
        { 1, 0, 0, 0 },
        { 1, 1, 1, 0 },
        { 1, 0, 0, 1 },
        { 1, 1, 1, 0 },
    },
    ["в"] = {
        { 1, 1, 1, 0 },
        { 1, 0, 0, 1 },
        { 1, 1, 1, 0 },
        { 1, 0, 0, 1 },
        { 1, 1, 1, 0 },
    },
    ["г"] = {
        { 1, 1, 1 },
        { 1, 0, 0 },
        { 1, 0, 0 },
        { 1, 0, 0 },
        { 1, 0, 0 },
    },
    ["д"] = {
        { 0, 0, 1, 1, 0 },
        { 0, 1, 0, 1, 0 },
        { 0, 1, 0, 1, 0 },
        { 0, 1, 0, 1, 0 },
        { 1, 1, 1, 1, 1 },
    },
    ["е"] = {
        { 1, 1, 1, 1 },
        { 1, 0, 0, 0 },
        { 1, 1, 1, 0 },
        { 1, 0, 0, 0 },
        { 1, 1, 1, 1 },
    },
    ["ё"] = {
        { 1, 0, 1, 0 },
        { 0, 0, 0, 0 },
        { 1, 1, 1, 1 },
        { 1, 0, 0, 0 },
        { 1, 1, 1, 0 },
        { 1, 0, 0, 0 },
        { 1, 1, 1, 1 },
    },
    ["ж"] = {
        { 1, 0, 1, 0, 1 },
        { 0, 1, 1, 1, 0 },
        { 0, 0, 1, 0, 0 },
        { 0, 1, 1, 1, 0 },
        { 1, 0, 1, 0, 1 },
    },
    ["з"] = {
        { 0, 1, 1, 1, 0 },
        { 0, 0, 0, 0, 1 },
        { 0, 0, 1, 1, 0 },
        { 0, 0, 0, 0, 1 },
        { 0, 1, 1, 1, 0 },
    },
    ["и"] = {
        { 1, 0, 0, 0, 1 },
        { 1, 0, 0, 1, 1 },
        { 1, 0, 1, 0, 1 },
        { 1, 1, 0, 0, 1 },
        { 1, 0, 0, 0, 1 },
    },
    ["й"] = {
        { 0, 1, 1, 1, 0 },
        { 0, 0, 0, 0, 0 },
        { 1, 0, 0, 0, 1 },
        { 1, 0, 0, 1, 1 },
        { 1, 0, 1, 0, 1 },
        { 1, 1, 0, 0, 1 },
        { 1, 0, 0, 0, 1 },
    },
    ["к"] = {
        { 1, 0, 0, 1, 0 },
        { 1, 0, 1, 0, 0 },
        { 1, 1, 0, 0, 0 },
        { 1, 0, 1, 0, 0 },
        { 1, 0, 0, 1, 0 },
    },
    ["л"] = {
        { 0, 0, 1, 1 },
        { 0, 1, 0, 1 },
        { 0, 1, 0, 1 },
        { 1, 0, 0, 1 },
        { 1, 0, 0, 1 },
    },
    ["м"] = {
        { 1, 0, 0, 0, 1 },
        { 1, 1, 0, 1, 1 },
        { 1, 0, 1, 0, 1 },
        { 1, 0, 0, 0, 1 },
        { 1, 0, 0, 0, 1 },
    },
    ["н"] = {
        { 1, 0, 0, 1 },
        { 1, 0, 0, 1 },
        { 1, 1, 1, 1 },
        { 1, 0, 0, 1 },
        { 1, 0, 0, 1 },
    },
    ["о"] = {
        { 0, 1, 1, 0 },
        { 1, 0, 0, 1 },
        { 1, 0, 0, 1 },
        { 1, 0, 0, 1 },
        { 0, 1, 1, 0 },
    },
    ["п"] = {
        { 1, 1, 1, 1 },
        { 1, 0, 0, 1 },
        { 1, 0, 0, 1 },
        { 1, 0, 0, 1 },
        { 1, 0, 0, 1 },
    },
    ["р"] = {
        { 1, 1, 1, 0},
        { 1, 0, 0, 1},
        { 1, 1, 1, 0},
        { 1, 0, 0, 0},
        { 1, 0, 0, 0},
    },
    ["с"] = {
        { 0, 1, 1, 1 },
        { 1, 0, 0, 0 },
        { 1, 0, 0, 0 },
        { 1, 0, 0, 0 },
        { 0, 1, 1, 1 },
    },
    ["т"] = {
        { 1, 1, 1, 1, 1 },
        { 0, 0, 1, 0, 0 },
        { 0, 0, 1, 0, 0 },
        { 0, 0, 1, 0, 0 },
        { 0, 0, 1, 0, 0 },
    },
    ["у"] = {
        { 1, 0, 0, 1 },
        { 1, 0, 0, 1 },
        { 0, 1, 1, 1 },
        { 0, 0, 0, 1 },
        { 1, 1, 1, 0 },
    },
    ["ф"] = {
        { 0, 1, 1, 1, 0 },
        { 1, 0, 1, 0, 1 },
        { 0, 1, 1, 1, 0 },
        { 0, 0, 1, 0, 0 },
        { 0, 0, 1, 0, 0 },
    },
    ["х"] = {
        { 1, 0, 0, 0, 1 },
        { 0, 1, 0, 1, 0 },
        { 0, 0, 1, 0, 0 },
        { 0, 1, 0, 1, 0 },
        { 1, 0, 0, 0, 1 },
    },
    ["ц"] = {
        { 1, 0, 0, 1, 0 },
        { 1, 0, 0, 1, 0 },
        { 1, 0, 0, 1, 0 },
        { 1, 0, 0, 1, 0 },
        { 0, 1, 1, 1, 1 },
    },
    ["ч"] = {
        { 1, 0, 0, 1 },
        { 1, 0, 0, 1 },
        { 0, 1, 1, 1 },
        { 0, 0, 0, 1 },
        { 0, 0, 0, 1 },
    },
    ["ш"] = {
        { 1, 0, 0, 0, 1 },
        { 1, 0, 0, 0, 1 },
        { 1, 0, 1, 0, 1 },
        { 1, 0, 1, 0, 1 },
        { 1, 1, 1, 1, 1 },
    },
    ["щ"] = {
        { 1, 0, 0, 0, 1, 0 },
        { 1, 0, 0, 0, 1, 0 },
        { 1, 0, 1, 0, 1, 0 },
        { 1, 0, 1, 0, 1, 0 },
        { 1, 1, 1, 1, 1, 1 },
    },
    ["ъ"] = {
        { 1, 1, 0, 0, 0 },
        { 0, 1, 0, 0, 0 },
        { 0, 1, 1, 1, 0 },
        { 0, 1, 0, 0, 1 },
        { 0, 1, 1, 1, 0 },
    },
    ["ы"] = {
        { 1, 0, 0, 0, 0, 1 },
        { 1, 0, 0, 0, 0, 1 },
        { 1, 1, 1, 0, 0, 1 },
        { 1, 0, 0, 1, 0, 1 },
        { 1, 1, 1, 0, 0, 1 },
    },
    ["ь"] = {
        { 1, 0, 0, 0 },
        { 1, 0, 0, 0 },
        { 1, 1, 1, 0 },
        { 1, 0, 0, 1 },
        { 1, 1, 1, 0 },
    },
    ["э"] = {
        { 1, 1, 1, 0 },
        { 0, 0, 0, 1 },
        { 0, 1, 1, 1 },
        { 0, 0, 0, 1 },
        { 1, 1, 1, 0 },
    },
    ["ю"] = {
        { 1, 0, 0, 1, 1, 0 },
        { 1, 0, 1, 0, 0, 1 },
        { 1, 1, 1, 0, 0, 1 },
        { 1, 0, 1, 0, 0, 1 },
        { 1, 0, 0, 1, 1, 0 },
    },
    ["я"] = {
        { 0, 1, 1, 1 },
        { 1, 0, 0, 1 },
        { 0, 1, 1, 1 },
        { 1, 0, 0, 1 },
        { 1, 0, 0, 1 },
    },


    ["-"] = {
        { 0, 0, 0 },
        { 0, 0, 0 },
        { 1, 1, 1 },
        { 0, 0, 0 },
        { 0, 0, 0 },
    },
    ["_"] = {
        { 0, 0, 0 },
        { 0, 0, 0 },
        { 0, 0, 0 },
        { 0, 0, 0 },
        { 1, 1, 1 },
    },
    ["+"] = {
        { 0, 0, 0 },
        { 0, 1, 0 },
        { 1, 1, 1 },
        { 0, 1, 0 },
        { 0, 0, 0 },
    },

    ["*"] = {
        { 0, 0, 0 },
        { 1, 0, 1 },
        { 0, 1, 0 },
        { 1, 0, 1 },
        { 0, 0, 0 },
    },
    ["°"] = {
        { 1 },
        { 0 },
        { 0 },
        { 0 },
        { 0 },
    },
    ["…"] = {
        { 0, 0, 0, 0, 0 },
        { 0, 0, 0, 0, 0 },
        { 0, 0, 0, 0, 0 },
        { 0, 0, 0, 0, 0 },
        { 1, 0, 1, 0, 1 },
    },
    [":"] = {
        {1,},
        { 1,},
        { 0,},
        { 1,},
        { 1},
    }
}

local glyphs_per_line = 3

local function new_page(self)
    logger:debug("Printer: Creating new page")

    if not file.exists("retro_computers:textures/printer") then
        file.mkdir("retro_computers:textures/printer")
    end

    local str = {}

    local curr_x = 1

    for y = 1, 5, 1 do
        for i = 1, #self.page, 1 do
            local char = self.page:sub(curr_x, curr_x)
            local glyph = glyphs[char]

            if glyph then
                for x = 1, 5, 1 do
                    local pixel = glyph[y][x]

                    if pixel then
                        if pixel > 0 then
                            print(curr_x, char)
                            str[#str+1] = '#'
                        else
                            str[#str+1] = ' '
                        end
                    else
                        str[#str+1] = ' '
                    end
                end

                str[#str+1] = ' '
            end

            if (i % glyphs_per_line) == 0 then
                str[#str+1] = '\n'
            end

            curr_x = curr_x + 1
        end

        str[#str+1] = '\n'

        curr_x = 1
    end

    console.log(table.concat(str))
    print(table.concat(str))
end

local function print_char(self, char)
    if char == 0x07 then -- BELL
    elseif char == 0x08 then -- BS
        if self.curr_x > 0 then
            self.curr_x = self.curr_x - 1
        end
    elseif char == 0x09 then -- HT
    elseif char == 0x0B then -- VT
        self.curr_x = 0
    elseif char == 0x0C then -- FF
        new_page(self)
    elseif char == 0x0D then -- CR
        self.curr_x = 0
    elseif char == 0x0A then -- LF
        self.curr_x = 0
        self.curr_y = self.curr_y + self.font.height
    elseif char == 0x0E then -- SO
    elseif char == 0x0F then -- SI
    elseif char == 0x11 then -- DC1
    elseif char == 0x12 then -- DC2
    elseif char == 0x13 then -- DC3
    elseif char == 0x14 then -- DC4
    elseif char == 0x18 then -- CAN
    elseif char == 0x1b then -- ESC
    else
        if self.curr_x >= 25 then
            self.curr_x = 0
            self.curr_y = self.curr_y + 5
            if self.curr_y > config.page_height then
                new_page(self)
            end
        end

        self.page = self.page .. utf8.encode(char)
        self.curr_x = self.curr_x + 5
    end
end

local function lpt_write(self)
    return function(_, val)
        print_char(self, val)
    end
end

function printer.new(lpt)
    local self = {
        page = "",
        curr_x = 0,
        curr_y = 0
    }

    local lpt_handler = {
        write = lpt_write(self)
    }
    lpt:set_port_handler(0x378, lpt_handler)

    return self
end

return printer