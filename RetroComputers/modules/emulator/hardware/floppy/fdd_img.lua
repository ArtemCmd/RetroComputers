local filesystem = require("retro_computers:emulator/filesystem")
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local fdd = {}

local floppy_chs = {
    [163840] = {40, 1, 8},
    [184320] = {40, 1, 9},
    [322560] = {70, 1, 9},
    [327680] = {40, 2, 8},
    [368640] = {40, 2, 9},
    [409600] = {80, 1, 10},
    [655360] = {80, 2, 8},
    [737280] = {80, 2, 9},
    [819200] = {80, 2, 10},
    [827392] = {80, 2, 11},
    [983040] = {80, 2, 12},
    [1064960] = {80, 2, 13},
    [1146880] = {80, 2, 14},
    [1228800] = {80, 2, 15},
    [1474560] = {80, 2, 18},
    [1556480] = {80, 2, 19},
    [1720320] = {80, 2, 21},
    [1741824] = {81, 2, 21},
    [1763328] = {82, 2, 21},
    [1884160] = {80, 2, 23},
    [2949120] = {80, 2, 36}
}

function fdd.load(path)
    local stream = filesystem.open(path, "r", false)

    if stream then
        local file_size = file.length(path)
        local chs = floppy_chs[file_size]

        if not chs then
            error(string.format("Unknown Floppy CHS: %d", file_size))
        end

        local drive = {
            cylinders = chs[1],
            heads = chs[2],
            sectors = chs[3],
            sector_size = 512,
            cylinder = 0,
            seek = function(self, cylinder)
                self.cylinder = cylinder
            end,
            read_sector = function(self, cylinder, head, sector, sector_size)
                stream:set_position(lshift((cylinder * self.heads + head) * self.sectors + (sector - 1), 9))
                return stream:read_bytes(sector_size)
            end,
            write_sector = function(self, cylinder, head, sector, data)
                stream:set_position(lshift((cylinder * self.heads + head) * self.sectors + (sector - 1), 9))
                stream:write_bytes(data)
            end,
            save = function(_)
                stream:flush()
            end
        }

        return drive
    else
        error("File not found: " .. path)
    end
end

return fdd
