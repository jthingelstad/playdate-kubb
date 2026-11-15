-- Scenario "gauge-ghost": the crank starts away from the bottom of the turn.
-- Frames: the crank ahead of the bottom (ghost dot and the arrow back), then
-- parked on the wind-up side (no throw starts; "bring the crank to the
-- bottom"), then a throw after coming down through the bottom and back.
import "selftest/_throw"

local st = tw.selftest
local f = tw.swing.tune.forwardSign

st.scenarios["gauge-ghost"] = st.throwScenario {
	startPos = 180 + 70 * f,                 -- 70 degrees ahead of the bottom
	script = {
		{ n = 3 },
		{ crank = -f * 10, n = 16 },         -- back through the bottom to 90 behind: winds up
		{ crank = f * 2, n = 50 },           -- slowly forward again: a let-down, ends 10 ahead
		{ crank = f * 100, n = 1 }, { crank = f * 100, n = 1 }, { crank = f * 50, n = 1 }, -- over the top to 100 behind
		{ n = 5 },
		{ crank = -f * 5, n = 10 },          -- further back while parked behind: nothing happens
		{ n = 5 },
	},
	shots = {
		function(s, fr) return fr == 2 end,
		function(s, fr) return fr == 85 end,
	},
	check = function(s)
		if s.promptText ~= "CRANK DOWN" then return "parked behind the prompt was " .. tostring(s.promptText) end
		if s.swing.phase ~= "idle" then return "a throw started behind the bottom: " .. s.swing.phase end
		if s.throws ~= 0 then return "throws " .. s.throws end
	end,
}
