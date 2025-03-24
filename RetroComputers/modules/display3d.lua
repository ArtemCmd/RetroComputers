local display = {}

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
        local display2d = self.display2d

        if self.graphics_mode then
            for y = 0, display2d.height - 1, 1 do
                for x = 0, display2d.width - 1, 1 do
                    local cell = display2d.buffer[y * display2d.width + x] or 0x00

                    str[x + 1] = palette[cell]
                end

                gfx.text3d.set_text(self.texboxes[y], table.concat(str))
            end
        else
            for y = 0, display2d.height - 1, 1 do
                for x = 0, display2d.width - 1, 1 do
                    local cell = display2d.char_buffer[y * display2d.width + x]
                    str[x + 1] = utf8.encode(cell[1])
                end

                if y == display2d.cursor_y then
                    if display2d.cursor_visible then
                        str[display2d.cursor_x + 1] = '_'
                    end
                end

                gfx.text3d.set_text(self.texboxes[y], table.concat(str))
            end
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
    for i = 0, self.display2d.height - 1, 1 do
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

    self.graphics_mode = false

    update(self)
end

function display.new(x, y, z, rotation, scale, offsets, color, display2d)
    local self = {
        transform = {x, y, z, rotation},
        texboxes = {},
        offsets = offsets,
        scale = scale,
        display2d = display2d,
        color = color,
        clock = 0,
        graphics_mode = false,
        delete = delete,
        reset = reset,
        update = update
    }

    reset(self)

    display2d.events:add_handler(function(event_type, width, height, graphics_mode)
        if event_type == 0 then
            if graphics_mode then
                local offset = self.offsets[self.transform[4]]
                local scale = 0.00013
                self:delete()

                for i = 0, self.display2d.height - 1, 1 do
                    local position = {self.transform[1] + offset[1], self.transform[2] + (offset[2] - 0.02) - (0.0015 * i), self.transform[3] + offset[3]}

                    if self.display2d.width <= 320 then
                        scale = 0.00015
                    end

                    self.texboxes[i] = gfx.text3d.show(position, "", {display = "static_billboard", scale = scale, color = {self.color[1] / 256, self.color[2] / 256, self.color[3] / 256, 1}})
                    gfx.text3d.set_rotation(self.texboxes[i], mat4.rotate({0, 1, 0}, 90 * self.transform[4]))
                end

                self.graphics_mode = true
            else
                self:reset()
                self.graphics_mode = false
            end
        end
    end)

    return self
end

return display