-- Scenario "flight": a scripted clean, strong throw at mid loft. Frames:
-- 1 just after release, as the baton rises into the aim view; 2 mid-flight
-- (tumbling); 3 the impact camera just before landing; 4 at rest with the
-- debug readout. The trace recorder is on, writing to
-- Data/<bundle>/selftest/flight-traces.jsonl; the check reads the line back
-- and replays it through core/swing. The frame-time log is on too, writing
-- to Data/<bundle>/selftest/flight-frames.jsonl; the check reads its one
-- line (scripted frames: 20 ms each).
import "selftest/_throw"

local st = tw.selftest
local landedAt = nil
local TRACES = "selftest/flight-traces.jsonl"
local FRAMES = "selftest/flight-frames.jsonl"

st.scenarios.flight = st.throwScenario {
	script = {
		{ n = 2 },
		st.windup(120, 30),
		{ n = 5 },
		st.flick { 6, 12, 18, 22, 24, 24, 24 },
		{ n = 200 },
	},
	shots = {
		function(s, f)
			if f == 1 then
				playdate.file.mkdir("selftest")
				playdate.file.delete(TRACES)
				tw.recorder.path, tw.recorder.on = TRACES, true
				playdate.file.delete(FRAMES)
				tw.framelog.path, tw.framelog.on = FRAMES, true
			end
			return s.mode == "flight" and st.batonOnScreen(s, 200)
		end,
		function(s) return s.mode == "flight" and tw.flight.progress(s.flight) >= 0.45 end,
		function(s) return s.mode == "flight" and tw.flight.progress(s.flight) >= 0.92 end,
		function(s, f)
			if s.mode == "rest" then landedAt = landedAt or f end
			return landedAt and f == landedAt + 30
		end,
	},
	maxFrames = 300,
	check = function(s)
		local l = s.last
		if not l then return "no throw" end
		if not l.legal then return "clean throw was not legal" end
		if l.power < 0.9 then return "power " .. l.power end
		if l.distance < 7.5 or l.distance > 9.5 then return "distance " .. l.distance end
		local f = playdate.file.open(TRACES, playdate.file.kFileRead)
		if not f then return "no trace file" end
		local line = f:readline()
		f:close()
		local t = tw.trace.decode(line)
		local ev, r = tw.trace.replay(t)
		if t.event ~= "release" or ev ~= "release" then return "trace event " .. tostring(t.event) .. "/" .. tostring(ev) end
		if math.abs(r.power - l.power) > 0.01 or r.legal ~= l.legal then return "trace replays differently" end
		if not t.result.distance or math.abs(t.result.distance - l.distance) > 0.01 then return "trace distance" end
		f = playdate.file.open(FRAMES, playdate.file.kFileRead)
		if not f then return "no frame-time log" end
		line = f:readline()
		local extra = f:readline()
		f:close()
		if extra then return "more than one frame-time line" end
		if #line >= 300 then return "frame-time line is " .. #line .. " bytes" end
		local o = tw.trace.decode(line)
		if o.scene ~= "practice" or o.proj ~= "baton" then return "frame-time scene/proj" end
		local n = o.pre[1] + o.slow[1] + o.post[1]
		if n < 50 then return "frame-time frames " .. line end
		if math.abs(o.pre[4] - 20) > 0.1 then return "scripted frames are not 20 ms: " .. line end
		if o.bodies ~= 18 then return "bodies " .. tostring(o.bodies) end
	end,
}
