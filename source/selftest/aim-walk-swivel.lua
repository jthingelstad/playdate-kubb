-- Scenario "aim-walk-swivel": walk right about 1.5 m and back about 1 m with
-- the d-pad, then hold A and turn the crank to swivel left. Frame 1 before,
-- frame 2 after the walk, frame 3 after the swivel. Then a double tap of A
-- faces straight again and a double tap of B resets the loft.
import "selftest/_throw"

local sign = tw.swing.tune.forwardSign
local WALK = 63 -- frames at 50 fps and 1.2 m/s: about 1.5 m
local BACK = 42 -- about 1 m

tw.selftest.scenarios["aim-walk-swivel"] = tw.selftest.throwScenario {
	script = {
		{ n = 2 },
		{ n = WALK, hold = { "right" } },
		{ n = BACK, hold = { "down" } },
		{ n = 2 },
		-- crank back with A held: swivel left, no walking and no wind-up
		{ n = 30, hold = { "a" }, crank = -4 * sign },
		{ n = 5 },
		{ n = 20, hold = { "b" }, crank = 6 * sign },
		{ n = 30 },
		{ press = { "a" } }, { n = 4 }, { press = { "a" } }, { n = 30 },
		{ press = { "b" } }, { n = 4 }, { press = { "b" } }, { n = 4 },
	},
	shots = {
		function(s, f) return f == 2 end,
		function(s, f) return f == WALK + BACK + 3 end,
		function(s, f)
			if f ~= WALK + BACK + 36 then return false end
			local deg = math.deg(s.swivel)
			if math.abs(deg + 30) > 0.5 then error(string.format("swivel %.1f, want -30", deg)) end
			return true
		end,
		function(s, f)
			if f == WALK + BACK + 60 and s.loftDeg <= tw.flight.tune.loftDefaultDeg then error("B + crank did not raise the loft") end
			return s.input:finished()
		end,
	},
	check = function(s)
		if math.abs(s.playerX - 1.5) > 0.1 then return string.format("walked to x %.2f", s.playerX) end
		if math.abs(s.playerY + 1.0) > 0.1 then return string.format("stepped back to y %.2f", s.playerY) end
		if s.swivel ~= 0 then return string.format("double tap A left swivel %.1f", math.deg(s.swivel)) end
		if s.loftDeg ~= tw.flight.tune.loftDefaultDeg then return "double tap B left loft " .. s.loftDeg end
		if s.swing.phase ~= "idle" then return "the crank wound up while A was held" end
	end,
}
