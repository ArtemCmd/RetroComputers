local display = {}

function display.new()
    local self = {
        buffer = {},
        cursor_x = 0,
        cursor_y = 0,
        width = 80,
        height = 25,
        update = function() end
    }
    return self
end

return display