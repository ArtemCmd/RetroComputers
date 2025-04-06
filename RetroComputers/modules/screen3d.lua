local screen3d = {}
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local palette = {
    [0x000000] = ' ', -- black
    [0x0000AA] = '(', -- blue
    [0x00AA00] = ')', -- green
    [0x00AAAA] = '*', -- cyan
    [0xAA0000] = '&', -- red
    [0xAA00AA] = '%', -- magenta
    [0x000055] = '?', -- brown
    [0xAAAAAA] = '.', -- light gray
    [0x555555] = ',', -- dark gray
    [0x5555FF] = '^', -- light blue
    [0x55FF55] = '$', -- light green
    [0x55FFFF] = '#', -- light cyan
    [0xFF5555] = '@', -- light red
    [0xFF55FF] = '!', -- light magenta
    [0xFFFF55] = 'D', -- yellow
    [0xFFFFFF] = '#' -- white
}

local function update(self)
    if (os.clock() - self.clock) >= 0.05 then
        local str = {}

        for y = 0, 199, 1 do
            for x = 0, self.screen.width - 1, 1 do
                local pixel = self.screen:get_pixel(y * self.screen.width + x) or {0, 0, 0, 0}

                str[x + 1] = palette[bor(bor(lshift(pixel[1], 16), lshift(pixel[2], 8)), pixel[3])] or ' '
            end

            gfx.text3d.set_text(self.texboxes[y], table.concat(str))
        end

        self.clock = os.clock()
    end
end

local function delete(self)
    for i = 0, #self.texboxes, 1 do
        gfx.text3d.hide(self.texboxes[i])
        self.texboxes[i] = nil
    end
end

local function reset(self)
    for i = 0, self.screen.height - 1, 1 do
        local offset = self.offsets[self.transform[4]]
        local position = {self.transform[1] + offset[1], self.transform[2] + offset[2] - (1 * self.scale * 24 * i), self.transform[3] + offset[3]} -- 0.013 
        local textbox = self.texboxes[i]
        local preset = {display = "static_billboard", scale = self.scale, color = {self.color[1] / 256, self.color[2] / 256, self.color[3] / 256, 1.0}}

        if not textbox then
            self.texboxes[i] = gfx.text3d.show(position, "", preset)
        else
            gfx.text3d.set_pos(textbox, position)
            gfx.text3d.update_settings(textbox, preset)
        end

        gfx.text3d.set_rotation(self.texboxes[i], mat4.rotate({0, 1, 0}, 90 * self.transform[4]))
        gfx.text3d.set_text(self.texboxes[i], "")
    end

    update(self)
end

function screen3d.new(x, y, z, rotation, scale, offsets, color, screen)
    local self = {
        transform = {x, y, z, rotation},
        texboxes = {},
        offsets = offsets,
        scale = scale,
        screen = screen,
        color = color,
        clock = 0,
        delete = delete,
        reset = reset,
        update = update
    }

    reset(self)

    return self
end

return screen3d