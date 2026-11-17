-- Frame-time log: appends one JSON line per throw (practice and match) to
-- frames.jsonl in the game's Data folder, once the throw is at rest, never
-- during the flight. The line is device/frametel's (format there and in
-- docs/notes/performance.md "Frame-time log"). Separate from the crank recorder's
-- traces.jsonl. On by default outside self-tests; the device autobench
-- turns it off while it runs, as it does the recorder. logcap keeps the file
-- to about 1 MB (older lines in frames-1.jsonl).
import "core/tw"
import "logcap"
import "device/frametel"

local framelog = {
	path = "frames.jsonl",
	on = false,
	written = 0,
}

local function now()
	local t = playdate.getTime()
	return string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year, t.month, t.day, t.hour, t.minute, t.second)
end

-- t: the throw's frametel table; info as frametel.encode (time is filled in).
function framelog.write(t, info)
	if not framelog.on then return end
	info.time = now()
	tw.logcap.check(framelog.path)
	local f = playdate.file.open(framelog.path, playdate.file.kFileAppend)
	if f then
		f:write(tw.frametel.encode(t, info) .. "\n")
		f:close()
		framelog.written = framelog.written + 1
	end
end

tw.framelog = framelog
