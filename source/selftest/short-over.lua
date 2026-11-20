-- Scenario "short-over": the crank wound three power bands past the target
-- at a field kubb a step away (selftest/_short) leaves it standing.
import "selftest/_short"

local st = tw.selftest

st.scenarios["short-over"] = st.throwScenario {
	setup = st.shortSetup,
	script = function(s) return st.planned(s, 6 * s.sol.level.powerHalf, 0) end,
	shots = { function(s, f) return f == 3 end, st.restShot(30) },
	maxFrames = 400,
	check = st.shortCheck(false),
}
