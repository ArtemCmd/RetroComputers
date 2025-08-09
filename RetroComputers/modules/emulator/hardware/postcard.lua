-- =====================================================================================================================================================================
-- POST Diagnostic Card emulation.
-- =====================================================================================================================================================================

local logger = require("dave_logger:logger")("RetroComputers")

local postcard = {}

local function postcard_out(cpu, port, val)
    logger:debug("POST Card: 0x%02X", val)
end

function postcard.new(cpu, base_port)
    local cpu_io = cpu:get_io()

    cpu_io:set_port_out(base_port, postcard_out)
end

return postcard
