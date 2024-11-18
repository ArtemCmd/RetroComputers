local string_format = string.format

local logger = {}
local logs = {}

local function get_time()
	local date = os.date("*t")
	local time = string_format("%04d/%02d/%02d %02d:%02d:%02d", date.year, date.month, date.day, date.hour, date.min, date.sec)
	return time
end

local function log(level, msg, ...)
    local str = string_format("[%s] %s		 [      RetroComputers] %s", level, get_time(), string_format(msg, ...))
	print(str)
    logs[#logs+1] = str .. '\n'
end

function logger:info(msg, ...)
	log('I', msg, ...)
end

function logger:debug(msg, ...)
	log('D', msg, ...)
end

function logger:warning(msg, ...)
	log('W', msg, ...)
end

function logger:error(msg, ...)
	log('E', msg, ...)
end

function logger:save()
    file.write(pack.data_file("retro_computers", "latest.log"), table.concat(logs))
end

return logger