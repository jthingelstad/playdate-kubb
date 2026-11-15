-- Scenario "windup": crank back 80 degrees and hold, mid wind-up (short of
-- the power target for b3: the prompt says WIND BACK). The clock's hand and
-- the backswing's peak dot show it.
import "selftest/_throw"

tw.selftest.scenarios.windup = tw.selftest.throwScenario {
	script = { { n = 2 }, tw.selftest.windup(80, 20), { n = 10 } },
	shots = { function(s, f) return f == 26 end },
	check = function(s)
		if s.swing.phase ~= "winding" then return "phase " .. s.swing.phase end
		if math.abs(s.swing.back - 80) > 0.5 then return "back " .. s.swing.back end
		if s.promptText ~= "WIND BACK" then return "prompt " .. tostring(s.promptText) end
	end,
}
