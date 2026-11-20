-- Crank trace recorder: appends one JSON line per swing to traces.jsonl in
-- the game's Data folder (format in core/trace.lua). Off unless the "debug"
-- file is in the Data folder at launch (main.lua). logcap keeps the file to about 1 MB
-- (older lines in traces-1.jsonl). kubb-engine's tools/replay_traces.lua replays it.
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
	sign = nil,         -- swing.tune.forwardSign when the swing's first sample came in
	written = 0,
}

function recorder.clear()
	recorder.n = 0
end

function recorder.add(dt, delta)
	if recorder.n >= recorder.maxFrames then return end
	-- the crank's direction this swing is made with: the line is written when
	-- the throw lands, and the crank may have been flipped by then (device/crank)
	if recorder.n == 0 then recorder.sign = tw.swing.tune.forwardSign end
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
	local line = tw.trace.encode(recorder.samples, recorder.n, event, result, recorder.sign or tw.swing.tune.forwardSign, now())
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
