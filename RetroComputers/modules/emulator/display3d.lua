local display = {}
local SCALE = 0.00065

local rotation_to_position = {
    [0] = {0.49, 0.79, 0.652},
    [1] = {0.66, 0.79, 0.500},
    [2] = {0.498, 0.79, 0.34},
    [3] = {0.348, 0.79, 0.51},
}

local function update(self)
    if (os.clock() - self.clock) >= 0.05 then
        if type(self.display2d.buffer[1]) == "table" then
            local str = {}
            for y = 0, self.display2d.height - 1, 1 do
                for x = 0, self.display2d.width - 1, 1 do
                    local cell = self.display2d.buffer[y * self.display2d.width + x] or {0, 0, 0}
                    str[x + 1] = utf8.encode(cell[1])
                end
                if y == self.display2d.cursor_y then
                    if self.cursor_enebled then
                        str[self.display2d.cursor_x + 1] = '_'
                    else
                        str[self.display2d.cursor_x + 1] = ' '
                    end
                    self.cursor_enebled = not self.cursor_enebled
                end
                gfx.text3d.set_text(self.texboxes[y], table.concat(str))
            end
            self.clock = os.clock()
        end
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
            self.texboxes[i] = gfx.text3d.show({x + position[1], y + position[2] - (0.013 * i), z + position[3]}, "", {display = "static_billboard", scale = SCALE, color = {170 / 256, 170 / 256, 170 / 256, 1}})
            gfx.text3d.set_rotation(self.texboxes[i], mat4.rotate({0, 1, 0}, 90 * rotation))
        end
    end
end

function display.new(x, y, z, rotation, display2d)
    local self = {
        display2d = display2d,
        update = update,
        texboxes = {},
        cursor_enebled = false,
        clock = os.clock(),
        delete = delete,
        reset = reset,
        transform = {x, y, z, rotation}
    }
    for i = 0, 24, 1 do
        local position = rotation_to_position[rotation]
        self.texboxes[i] = gfx.text3d.show({x + position[1], y + position[2] - (0.013 * i), z + position[3]}, "", {display = "static_billboard", scale = SCALE, color = {170 / 256, 170 / 256, 170 / 256, 1}})
        gfx.text3d.set_rotation(self.texboxes[i], mat4.rotate({0, 1, 0}, 90 * rotation))
    end
    return self
end

return display