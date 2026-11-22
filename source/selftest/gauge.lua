-- Scenario "gauge": the prompt over the clock (hud.clock) for the default
-- aim at b3: WIND BACK at rest (frame 1) and while the backswing is short of
-- the power target (frame 2), FLICK! inverted inside it (frame 3), EASE OFF
-- past it (frame 4), nothing during the flick, and after the release the
-- clock with the throw's dots and the result flag (frame 5).
import "selftest/_throw"

local st = tw.selftest
local seen = {}
local sol

tw.selftest.scenarios.gauge = tw.selftest.throwScenario {
	-- wound slowly, 2 degrees a frame, to 25 past the target, then a flick to 3 o'clock
	-- (past the release target since engine 0.10's arc for 8 m, 4 o'clock: it only has to throw)
	script = function(s)
		sol = { lo = s.sol.powerLo, hi = s.sol.powerHi }
		local back = s.sol.powerHi + 25
		return st.swingTo(back, 90, 60, { lead = 3, frames = math.floor(back / 2), pause = 3 })
	end,
	shots = {
		function(s, f) if f == 2 then seen[1] = s.promptText; return true end end,
		function(s)
			local sw = s.swing
			if sw.phase == "winding" and sw.back > 60 and sw.back < sol.lo - 5 then seen[2] = s.promptText; return true end
		end,
		function(s)
			local sw = s.swing
			-- anywhere inside it: on the person's meter (engine 0.13) the power target at
			-- 8 m is 2 degrees either side, so 2 inside each edge was its centre alone
			if sw.phase == "winding" and sw.back > sol.lo and sw.back < sol.hi then seen[3] = s.promptText; return true end
		end,
		function(s)
			local sw = s.swing
			if sw.phase == "winding" and sw.back > sol.hi + 10 then seen[4] = s.promptText; return true end
		end,
		function(s)
			if s.swing.phase == "swinging" then seen[5] = s.promptText or false end
			return s.mode == "flight" and s.showTime > 0.3
		end,
	},
	check = function(s)
		if s.throws ~= 1 then return "throws " .. s.throws end
		if seen[1] ~= "WIND BACK" then return "at rest the prompt was " .. tostring(seen[1]) end
		if seen[2] ~= "WIND BACK" then return "short of the target the prompt was " .. tostring(seen[2]) end
		if seen[3] ~= "FLICK!" then return "in the target the prompt was " .. tostring(seen[3]) end
		if seen[4] ~= "EASE OFF" then return "past the target the prompt was " .. tostring(seen[4]) end
		if seen[5] then return "mid swing the prompt was " .. tostring(seen[5]) end
		if s.lastBack == nil or s.lastStop == nil then return "no dots for the last throw" end
	end,
}
