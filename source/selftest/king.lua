-- Scenario "king": a medium throw from the center straight at the king, to
-- look at how the king is drawn (crown and groove) from the impact camera.
-- Frames: 1 the baton arriving, 2 just after, 3 at rest.
import "selftest/_throw"

local st = tw.selftest

st.scenarios.king = st.throwScenario {
	setup = function(s) s.loftDeg = 30 end,
	script = {
		{ n = 5 },
		st.windup(120, 30),
		{ n = 5 },
		st.flick { 4, 8, 11, 12, 12, 12, 12 },
		{ n = 300 },
	},
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
