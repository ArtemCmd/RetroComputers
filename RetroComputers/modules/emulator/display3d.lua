local display = {}

local rotation_to_position = {
    [0] = {0.49, 0.79, 0.652},
    [1] = {0.66, 0.79, 0.500},
    [2] = {0.498, 0.79, 0.34},
    [3] = {0.348, 0.79, 0.51},
}

local palette = {
    [0] = ' ', -- black
    [170] = '(', -- blue
    [43520] = ')', -- green
    [43690] = '*', -- cyan
    [11141120] = '&', -- red
    [11141290] = '%', -- magenta
    [85] = '?', -- brown
    [11184810] = '.', -- light gray
    [5592405] = ',', -- dark gray
    [5592575] = '^', -- light blue
    [5635925] = '$', -- light green
    [5636095] = '#', -- light cyan
    [16733525] = '@', -- light red
    [16733695] = '!', -- light magenta
    [16777045] = 'D', -- yellow
    [16777215] = '#' -- white
}

local function update_resolution(self)
    if (not self.display2d.textmode) and ((not self.graphics_mode) or (self.display2d.width ~= self.last_width)) then
        self.graphics_mode = true
        self.text_mode = false

        self:delete()

        if self.display2d.width <= 320 then
            for i = 0, self.display2d.height - 1, 1 do
                if not self.texboxes[i] then
                    local position = rotation_to_position[self.transform[4]]
                    self.texboxes[i] = gfx.text3d.show({self.transform[1] + position[1], self.transform[2] + (position[2] - 0.02) - (0.0015 * i), self.transform[3] + position[3]}, "", {display = "static_billboard", scale = 0.00015, color = {170 / 256, 170 / 256, 170 / 256, 1}})
                    gfx.text3d.set_rotation(self.texboxes[i], mat4.rotate({0, 1, 0}, 90 * self.transform[4]))
                end
            end
        else
            for i = 0, self.display2d.height - 1, 1 do
                if not self.texboxes[i] then
                    local position = rotation_to_position[self.transform[4]]
                    self.texboxes[i] = gfx.text3d.show({self.transform[1] + position[1], self.transform[2] + (position[2] - 0.02) - (0.0015 * i), self.transform[3] + position[3]}, "", {display = "static_billboard", scale = 0.00008, color = {170 / 256, 170 / 256, 170 / 256, 1}})
                    gfx.text3d.set_rotation(self.texboxes[i], mat4.rotate({0, 1, 0}, 90 * self.transform[4]))
                end
            end
        end

        self.last_width = self.display2d.width
    elseif self.display2d.textmode and (not self.text_mode) then
        self.text_mode = true
        self.graphics_mode = false
        self:delete()
        self:reset(self.transform[1], self.transform[2], self.transform[3], self.transform[4])
    end
end

local function update(self)
    if (os.clock() - self.clock) >= 0.05 then
        update_resolution(self)

        local str = {}

        if self.display2d.textmode then
            for y = 0, self.display2d.height - 1, 1 do
                for x = 0, self.display2d.width - 1, 1 do
                    local cell = self.display2d.char_buffer[y * self.display2d.width + x] or {0, 0, 0}
                    str[x + 1] = utf8.encode(cell[1])
                end

                if y == self.display2d.cursor_y then
                    if self.display2d.cursor_visible then
                        str[self.display2d.cursor_x + 1] = '_'
                    else
                        str[self.display2d.cursor_x + 1] = ' '
                    end
                end

                gfx.text3d.set_text(self.texboxes[y], table.concat(str))
            end
        else
            for y = 0, self.display2d.height - 1, 1 do
                for x = 0, self.display2d.width - 1, 1 do
                    local cell = self.display2d.buffer[y * self.display2d.width + x] or 11141290

                    str[x + 1] = palette[cell]
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

local function reset(self, x, y, z, rotation)
    for i = 0, 24, 1 do
        if not self.texboxes[i] then
            local position = rotation_to_position[rotation]
            self.texboxes[i] = gfx.text3d.show({x + position[1], y + position[2] - (0.013 * i), z + position[3]}, "", {display = "static_billboard", scale = 0.00065, color = {170 / 256, 170 / 256, 170 / 256, 1}})
            gfx.text3d.set_rotation(self.texboxes[i], mat4.rotate({0, 1, 0}, 90 * rotation))
        else
            local position = rotation_to_position[rotation]
            gfx.text3d.set_pos(self.texboxes[i], {x + position[1], y + position[2] - (0.013 * i), z + position[3]})
        end
    end
end

function display.new(x, y, z, rotation, display2d)
    local self = {
        transform = {x, y, z, rotation},
        display2d = display2d,
        texboxes = {},
        clock = os.clock(),
        last_width = 0,
        graphics_mode = false,
        text_mode = true,
        delete = delete,
        reset = reset,
        update = update
    }

    for i = 0, 24, 1 do
        local position = rotation_to_position[rotation]
        self.texboxes[i] = gfx.text3d.show({x + position[1], y + position[2] - (0.013 * i), z + position[3]}, "DaveBIOS is best BIOS", {display = "static_billboard", scale = 0.00065, color = {170 / 256, 170 / 256, 170 / 256, 1}})
        gfx.text3d.set_rotation(self.texboxes[i], mat4.rotate({0, 1, 0}, 90 * rotation))
    end

    return self
end

return display