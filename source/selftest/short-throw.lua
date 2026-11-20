-- Scenario "short-throw": the plan's clean crank throw at a field kubb a
-- step away (selftest/_short) topples it.
import "selftest/_short"

local st = tw.selftest

st.scenarios["short-throw"] = st.throwScenario {
	setup = st.shortSetup,
	script = function(s) return st.planned(s) end,
	shots = { function(s, f) return f == 3 end, st.restShot(30) },
	maxFrames = 400,
	check = st.shortCheck(true),
}
