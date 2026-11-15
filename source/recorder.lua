-- Crank trace recorder: appends one JSON line per swing to traces.jsonl in
-- the game's Data folder (format in core/trace.lua). On by default; the
-- System Menu's "Record" turns it off. logcap keeps the file to about 1 MB
-- (older lines in traces-1.jsonl). tools/replay_traces.lua replays the file.
import "core/tw"
import "logcap"
import "core/trace"
import "core/swing"

local recorder = {
	path = "traces.jsonl",
	on = false,
	maxFrames = 3000,   -- about a minute at 50 fps; a longer wind-up is cut short
	samples = {},       -- flat {dt, delta, ...} of the swing being recorded
	n = 0,
	written = 0,
}

function recorder.clear()
	recorder.n = 0
end

function recorder.add(dt, delta)
	if recorder.n >= recorder.maxFrames then return end
	local n = recorder.n + 1
	recorder.samples[2 * n - 1] = dt
	recorder.samples[2 * n] = delta
	recorder.n = n
end

local function now()
	local t = playdate.getTime()
	return string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year, t.month, t.day, t.hour, t.minute, t.second)
end

-- Write the current swing as one line. result may be nil (a let-down).
function recorder.write(event, result)
	if not recorder.on or recorder.n == 0 then return end
	local line = tw.trace.encode(recorder.samples, recorder.n, event, result, tw.swing.tune.forwardSign, now())
	tw.logcap.check(recorder.path)
	local f = playdate.file.open(recorder.path, playdate.file.kFileAppend)
	if f then
		f:write(line .. "\n")
		f:close()
		recorder.written = recorder.written + 1
	end
	recorder.n = 0
end

tw.recorder = recorder
