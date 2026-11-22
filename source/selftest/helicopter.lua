-- Scenario "helicopter": a stuttered flick (fast and slow frames
-- alternating) on the plan's release, wound 40 degrees past the power target's
-- centre (overpowered: every 30 degrees past the target multiplies the shake's
-- cost): the shake tilts the baton past the helicopter limit. Until engine 0.13
-- it was thrown at the Pro level (the shake's full cost) on the targets; on the
-- person's meter (shakeGain 0.75, the level no longer counts) the same flick
-- tilts it 19 degrees, legal, so it is overpowered as well. Frames: mid-flight with the baton spinning flat, then at rest
-- with the readout saying HELICOPTER.
import "selftest/_throw"

local st = tw.selftest
local landedAt = nil

st.scenarios.helicopter = st.throwScenario {
	script = function(s) return st.planned(s, 40, 0, 200, { shaky = true }) end,
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
		if s.vSteady then return "a stuttered flick read STEADY" end
	end,
}
