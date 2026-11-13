-- Scenario "gauge": the throw gauge at rest, wound past full power, mid
-- swing and after the release.
import "selftest/_throw"

tw.selftest.scenarios.gauge = tw.selftest.throwScenario {
	script = { { n = 3 }, tw.selftest.windup(130, 20), { n = 6 },
		tw.selftest.flick { 6, 12, 18, 22, 24, 24, 24 }, { n = 40 } },
	shots = {
		function(s, f) return f == 2 end,
		function(s, f) return f == 27 end,
		function(s, f) return s.swing.phase == "swinging" and s.swing.n >= 4 end,
		function(s, f) return s.mode == "flight" and f >= 45 end,
	},
	check = function(s)
		if s.throws ~= 1 then return "throws " .. s.throws end
	end,
}
