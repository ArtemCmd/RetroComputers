local event = {}

local function add_handler(self, handler)
    table.insert(self.handlers, handler)
    return #self.handlers
end

local function remove_handler(self, id)
    table.remove(self.handlers, id)
end

local function emit(self, ...)
    for i = 1, #self.handlers, 1 do
        self.handlers[i](...)
    end
end

function event.new()
    local self = {
        handlers = {},
        add_handler = add_handler,
        remove_handler = remove_handler,
        emit = emit
    }

    return self
end

return event