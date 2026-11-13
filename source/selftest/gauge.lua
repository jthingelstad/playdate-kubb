-- Scenario "gauge": the throw gauge at rest (prompt WIND BACK), wound past
-- full power (the prompt inverts: FLICK!), mid swing (no prompt) and after
-- the release (the power chip and the result flag instead of the gauge).
import "selftest/_throw"

local seen = {}

tw.selftest.scenarios.gauge = tw.selftest.throwScenario {
	script = { { n = 3 }, tw.selftest.windup(130, 20), { n = 6 },
		tw.selftest.flick { 6, 12, 18, 22, 24, 24, 24 }, { n = 40 } },
	shots = {
		function(s, f) if f == 2 then seen[1] = s.promptText; return true end end,
		function(s, f) if f == 27 then seen[2] = s.promptText; return true end end,
		function(s, f)
			if s.swing.phase == "swinging" and s.swing.n >= 4 then seen[3] = s.promptText or false; return true end
		end,
		function(s, f) return s.mode == "flight" and f >= 45 end,
	},
	check = function(s)
		if s.throws ~= 1 then return "throws " .. s.throws end
		if seen[1] ~= "WIND BACK" then return "at rest the prompt was " .. tostring(seen[1]) end
		if seen[2] ~= "FLICK!" then return "at full power the prompt was " .. tostring(seen[2]) end
		if seen[3] then return "mid swing the prompt was " .. tostring(seen[3]) end
	end,
}
