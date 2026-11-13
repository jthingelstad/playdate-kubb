-- Scenario "loft": hold B and crank back to the lowest loft (frame 1), then
-- forward to the highest (frame 2). The HUD dial and the minimap aim line
-- change, and no throw starts.
import "selftest/_throw"

local sign = tw.swing.tune.forwardSign
local lft = tw.flight.tune

tw.selftest.scenarios.loft = tw.selftest.throwScenario {
	script = {
		{ n = 2 },
		{ n = 40, hold = { "b" }, crank = -6 * sign },
		{ n = 3 },
		{ n = 60, hold = { "b" }, crank = 6 * sign },
		{ n = 3 },
	},
	shots = {
		function(s, f) return f == 44 end,
		function(s, f) return f == 107 end,
	},
	check = function(s)
		if s.loftDeg ~= lft.loftMaxDeg then return "loft " .. s.loftDeg end
		if s.throws ~= 0 or s.swing.phase ~= "idle" then return "the crank threw while B was held" end
	end,
}
