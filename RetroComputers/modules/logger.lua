local logger = {}
local logs = {}

local function log(level, msg, ...)
    local date = os.date("*t")
    local str = string.format("[%s] %04d/%02d/%02d %02d:%02d:%02d		 [      RetroComputers] %s", level, date.year, date.month, date.day, date.hour, date.min, date.sec, string.format(msg, ...))
    print(str)
    table.insert(logs, str .. '\n')
end

function logger.info(msg, ...)
	log('I', msg, ...)
end

function logger.debug(msg, ...)
	log('D', msg, ...)
end

function logger.warning(msg, ...)
	log('W', msg, ...)
end

function logger.error(msg, ...)
	log('E', msg, ...)
end

function logger.save()
    file.write(pack.data_file("retro_computers", "latest.log"), table.concat(logs))
end

return logger