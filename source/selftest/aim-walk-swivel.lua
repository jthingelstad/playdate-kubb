-- Scenario "aim-walk-swivel": walk right about 1.5 m with the d-pad, then
-- hold left and turn the crank to swivel left. Frame 1 before, frame 2 after
-- the walk, frame 3 after the swivel.
import "selftest/_throw"

local sign = tw.swing.tune.forwardSign
local WALK = 63 -- frames at 50 fps and 1.2 m/s: about 1.5 m

tw.selftest.scenarios["aim-walk-swivel"] = tw.selftest.throwScenario {
	script = {
		{ n = 2 },
		{ n = WALK, hold = { "right" } },
		{ n = 2 },
		-- crank back (anti-clockwise) with left held: swivel left, no walking
		{ n = 30, hold = { "left" }, crank = -4 * sign },
		{ n = 5 },
	},
	shots = {
		function(s, f) return f == 2 end,
		function(s, f) return f == WALK + 3 end,
		function(s, f) return f == WALK + 36 end,
	},
	check = function(s)
		if math.abs(s.playerX - 1.5) > 0.1 then return string.format("walked to %.2f", s.playerX) end
		local deg = math.deg(s.swivel)
		if math.abs(deg + 30) > 0.5 then return string.format("swivel %.1f, want -30", deg) end
	end,
}
