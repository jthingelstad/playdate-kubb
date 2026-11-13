-- Scenario "windup": crank back 80 degrees and hold, mid wind-up. The meter
-- shows the power cap the backswing allows.
import "selftest/_throw"

tw.selftest.scenarios.windup = tw.selftest.throwScenario {
	script = { { n = 2 }, tw.selftest.windup(80, 20), { n = 10 } },
	shots = { function(s, f) return f == 26 end },
	check = function(s)
		if s.swing.phase ~= "winding" then return "phase " .. s.swing.phase end
		if math.abs(s.swing.backswing - 80) > 0.5 then return "backswing " .. s.swing.backswing end
	end,
}
