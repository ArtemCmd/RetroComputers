local event = {}

local function add_handler(self, event_id, handler)
    local evt = self.events[event_id]

    if not evt then
        evt = {
            next_id = 0,
            handlers = {}
        }

        self.events[event_id] = evt
    end

    local id = evt.next_id
    evt.next_id = evt.next_id + 1
    evt.handlers[id] = handler

    return id
end

local function remove_handler(self, event_id, id)
    local evt = self.events[event_id]

    if evt then
        evt.handlers[id] = nil
    end
end

local function emit(self, event_id, ...)
    local evt = self.events[event_id]

    if not self.emit_event then
        self.emit_event = true
        emit(self, 0, event_id)
    else
        self.emit_event = false
    end

    if evt then
        local handlers = evt.handlers

        for _, handler in pairs(handlers) do
            handler(event_id, ...)
        end
    end
end

function event.new()
    local self = {
        emit_event = false,
        events = {},
        add_handler = add_handler,
        remove_handler = remove_handler,
        emit = emit
    }

    return self
end

return event
