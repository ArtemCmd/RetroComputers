local display = {}

function display.new()
    local self = {
        buffer = {},
        cursor_visibly = false,
        cursor_x = 0,
        cursor_y = 0,
        width = 80,
        height = 25,
        update = function() end,
        set_resolution = function (width, height, graphics) end
    }
    return self
end

return display