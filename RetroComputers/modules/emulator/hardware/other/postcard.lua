local logger = require("retro_computers:logger")
local config = require("retro_computers:config")

local bios_code = {
    ["bios_xt"] = {
        [0x00] = "Boot the OS",
        [0x01] = "Start of BIOS POST, CPU test",
        [0x02] = "Initial chipset configuration",
        [0x03] = "Initialize DMAC initialized",
        [0x04] = "Test low 32 KiB of RAM",
        [0x05] = "Initialize interrupt table",
        [0x06] = "Initialize PIT (timer)",
        [0x07] = "Initialize PIC",
        [0x08] = "Initialize KBC and keyboard",
        [0x09] = "Enable interrupts",
        [0x10] = "Locate video BIOS",
        [0x11] = "Initialize video BIOS",
        [0x12] = "No video BIOS, using MDA/CGA",
        [0x20] = "Initialize RTC",
        [0x21] = "Detect CPU type",
        [0x22] = "Detect FPU",
        [0x24] = "Detect serial ports",
        [0x25] = "Detect parallel ports",
        [0x30] = "Start RAM test",
        [0x31] = "RAM test completed",
        [0x32] = "RAM test canceled",
        [0x40] = "Start BIOS extension ROM scan",
        [0x41] = "BIOS extension ROM found, initizalize",
        [0x42] = "BIOS extension ROM initialized",
        [0x43] = "BIOS extension scan complete",
        [0x52] = "CPU test failed",
        [0x54] = "Low 32 KiB RAM test failed",
        [0x55] = "RAM test failed",
        [0x60] = "Unable to flush KBC output buffer",
        [0x61] = "Unable to send command to KBC",
        [0x62] = "Keyboard controller self test failed",
        [0x63] = "Keyboard interface test failed",
        [0x70] = "Keyboard BAT test failed",
        [0x71] = "Keyboard disable command failed",
        [0x72] = "Keyboard enable command failed",
    }
}

local postcard = {}

function postcard.new(cpu, used_bios)
    cpu:port_set(0x80, function (_, _, val)
        if val then
            if config.enable_post_card then
                local codes = bios_code[used_bios]

                if codes then
                    if codes[val] then
                        logger:debug("POST Card: %s", bios_code[used_bios][val])
                    end
                else
                    logger:debug("POST Card: %d", val)
                end
            end
        else
            return 0
        end
    end)
end

return postcard