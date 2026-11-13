-- Scenario "rearm": after a throw the crank is parked behind the bottom
-- during the flight. Back in aim mode nothing may start until the crank
-- crosses the bottom again.
import "selftest/_throw"

local st = tw.selftest
local f = tw.swing.tune.forwardSign
local aimAgain = nil

st.scenarios.rearm = st.throwScenario {
	script = { { n = 3 }, st.windup(130, 20), { n = 4 },
		st.flick { 6, 12, 18, 22, 24, 24, 24, 12 },
		{ n = 5 }, { crank = -f * 8, n = 5 },   -- during the flight: park 28 degrees behind
		{ n = 400 } },
	shots = {
		function(s, fr)
			if s.throws == 1 and s.mode == "aim" then aimAgain = aimAgain or fr end
			return aimAgain and fr == aimAgain + 10
		end,
	},
	maxFrames = 500,
	check = function(s)
		if s.swing.phase ~= "idle" then return "a wind-up started without crossing the bottom: " .. s.swing.phase end
		if s.armed then return "armed without a fresh crossing" end
	end,
}
