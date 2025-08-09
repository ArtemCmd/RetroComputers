-- =====================================================================================================================================================================
-- PC Speaker emulation.
-- =====================================================================================================================================================================

local logger = require("dave_logger:logger")("RetroComputers")
local band, bor, lshift, rshift, bxor = bit.band, bit.bor, bit.lshift, bit.rshift, bit.bxor

local speaker = {}

local function update(self)
    if (self.chanel_mode ~= 0) and (self.chanel_mode ~= 1) and (self.chanel_mode ~= 5) and (self.chanel_mode ~= 4) then
        self.handler(self.channel_count, self.enabled and self.gated)
    end
end

local function get_handler(self)
    return self.handler
end

local function set_handler(self, handler)
    self.handler = handler
end

local function reset(self)
    self.channel_out = false
    self.channel_count = 0xFFFF
    self.channel_mode = 0
    self.enabled = false
    self.gated = false
    self.channel_out = false
    self.ppi_enabled = false
end

function speaker.new(pit)
    local self = {
        buffer = {},
        channel_mode = 0,
        channel_count = 0xFFFF,
        channel_out = false,
        enabled = false,
        ppi_enabled = false,
        gated = false,
        get_handler = get_handler,
        set_handler = set_handler,
        update = update,
        reset = reset
    }

    pit:set_channel_out_handler(2, function(out, old_out)
        update(self)

        local count = pit.channels[2].load

        if count == 0 then
            count = 0x10000
        end

        if count < 25 then
            self.channel_out = false
        else
            self.channel_out = out
        end

        self.ppi_enabled = out
    end)

    pit:set_channel_load_handler(2, function(mode, count)
        self.channel_count = count
        self.channel_mode = mode
    end)

    return self
end

return speaker
