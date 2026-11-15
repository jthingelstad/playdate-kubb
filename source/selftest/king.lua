-- Scenario "king": the circle on the king (the king arc, half past 3) and
-- the plan's clean throw, to
-- look at how the king is drawn (crown and groove) from the impact camera.
-- Frames: 1 the baton arriving, 2 just after, 3 at rest.
import "selftest/_throw"

local st = tw.selftest

st.scenarios.king = st.throwScenario {
	setup = function(s) tw.scenes.throw.aimAt(s, 0, 4) end,
	script = function(s) return st.planned(s) end,
	shots = {
		function(s) return s.mode == "flight" and tw.flight.progress(s.flight) >= 0.85 end,
		function(s) return s.mode == "flight" and tw.flight.progress(s.flight) >= 1 end,
		st.restShot(30),
	},
	maxFrames = 400,
	check = function(s)
		if not s.result then return "no result" end
	end,
}
