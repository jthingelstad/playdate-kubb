-- Scenario "clock-throw": point and throw (DESIGN 4), no A or B pressed.
-- The circle starts on the nearest live target (b3), the thrower stands
-- behind it, the arc is the base kubb's (3 o'clock); the crank winds into
-- the power target and stops at 3 o'clock: the baton takes a base kubb
-- down. Frames: 1 aiming (the circle, the arc, the clock's targets), 2 the
-- wind-up inside the power target (FLICK!), 3 in flight, 4 at rest (the
-- result flag and ON ON STEADY), 5 aiming again (the verdicts and the last
-- throw's dots on the clock, until the next wind-up).
import "selftest/_throw"

local st = tw.selftest
local promptSeen

st.scenarios["clock-throw"] = st.throwScenario {
	script = function(s) return st.planned(s) end,
	shots = {
		function(s, f) return f == 3 end,
		function(s)
			local sw = s.swing
			if sw.phase == "winding" and sw.back >= s.sol.powerLo + 2 then promptSeen = s.promptText; return true end
		end,
		function(s) return s.mode == "flight" and s.showTime > 0.35 end,
		st.restShot(30),
		function(s) return s.mode == "aim" and s.throws == 1 end,
	},
	maxFrames = 500,
	check = function(s)
		if s.stanceSet or s.arcSet then return "the stance or the arc was set by hand" end
		if math.abs(s.playerX) > 1e-6 or math.abs(s.sol.release - 90) > 1e-6 then
			return string.format("stance %.2f, release %.0f", s.playerX, s.sol.release)
		end
		if promptSeen ~= "FLICK!" then return "in the power target the prompt was " .. tostring(promptSeen) end
		local r = s.result
		if not r or not r.firstHit or not r.firstHit.with:match("^b%d$") then
			return "first hit " .. tostring(r and r.firstHit and r.firstHit.with)
		end
		local down = 0
		for _, id in ipairs(r.toppled) do if id:match("^b%d$") then down = down + 1 end end
		if down < 1 then return "no base kubb down: " .. table.concat(r.toppled, ",") end
		if s.vPower ~= 0 or s.vRelease ~= 0 or not s.vSteady then
			return string.format("verdicts %s %s %s", tostring(s.vPower), tostring(s.vRelease), tostring(s.vSteady))
		end
		if not s.showVerdicts or not s.lastBack or not s.lastStop then return "no verdicts or dots on the next aim" end
		if math.abs(s.lastStop - 90) > 0.01 then return "stopped at " .. s.lastStop end
		return nil, string.format("back=%.0f/%.0f-%.0f down=%d", s.lastBack, s.sol.powerLo, s.sol.powerHi, down)
	end,
}
