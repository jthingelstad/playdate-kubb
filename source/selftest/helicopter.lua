-- Scenario "helicopter": a scripted jerky flick (fast and slow frames
-- alternating). Frames: mid-flight with the baton spinning flat, then at rest
-- with the readout saying HELICOPTER.
import "selftest/_throw"

local st = tw.selftest
local landedAt = nil

st.scenarios.helicopter = st.throwScenario {
	script = {
		{ n = 2 },
		st.windup(120, 30),
		{ n = 5 },
		st.flick { 30, 10, 30, 10, 30, 10 },
		{ n = 200 },
	},
	shots = {
		function(s) return s.mode == "flight" and tw.flight.progress(s.flight) >= 0.5 end,
		function(s, f)
			if s.mode == "rest" then landedAt = landedAt or f end
			return landedAt and f == landedAt + 30
		end,
	},
	maxFrames = 300,
	check = function(s)
		local l = s.last
		if not l then return "no throw" end
		if l.legal then return string.format("jerky throw was legal (tilt %.1f)", l.tilt) end
		if not s.readout or not s.readout:find("HELICOPTER") then return "readout: " .. tostring(s.readout) end
	end,
}
