local config = require("retro_computers:config")

local util = {}

function util.load_roms(machine_name, memory)
    local roms = config.machine[machine_name].rom

    for i = 1, #roms, 1 do
        local rom = roms[i]
        local path

        if string.find(rom.filename, ":") then
            path = rom.filename
        else
            path = string.format("retro_computers:roms/%s/%s", machine_name, rom.filename)
        end

        memory:load_rom(rom.addr, path)
    end
end

return util
