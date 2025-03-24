local logger = require("retro_computers:logger")

local function update(self)
    if self.handler then
        if self.enabled then
            local freq = 1193182 / self.pit.channels[2].reload
            self.handler(freq)
        end
    end
end

local function get_handler(self)
    return self.handler
end

local function set_handler(self, handler)
    self.handler = handler
end

local function reset(self)
    self.enabled = false
    self.ppi_enabled = false
end

local speaker = {}

function speaker.new(pit)
    local self = {
        pit = pit,
        enabled = false,
        ppi_enabled = false,
        get_handler = get_handler,
        set_handler = set_handler,
        update = update,
        reset = reset
    }

    pit:set_channel_handler(2, function(channel, set, old_set)
        update(self)
        self.ppi_enabled = set
    end)

    return self
end

return speaker