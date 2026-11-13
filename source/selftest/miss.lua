-- Scenario "miss": the hit throw from half a meter right of center: the
-- baton passes between b3 and b4, lands past the far baseline and touches
-- nothing. Frames: 1 the impact camera near the landing, 2 at rest.
import "selftest/_throw"

local st = tw.selftest

st.scenarios.miss = st.throwScenario {
	setup = function(s) s.loftDeg, s.playerX = 30, 0.5 end,
	script = {
		{ n = 5 },
		st.windup(120, 30),
		{ n = 5 },
		st.flick { 6, 12, 18, 22, 24, 24, 24 },
		{ n = 300 },
	},
	shots = {
		function(s) local d = st.sinceContact(s); return d and d >= -0.05 end,
		st.restShot(30),
	},
	maxFrames = 400,
	check = function(s)
		local r = s.result
		if not r then return "no result" end
		if r.firstHit then return "hit " .. r.firstHit.with end
		if #r.toppled > 0 then return "toppled " .. table.concat(r.toppled, ",") end
		if #r.touched ~= 1 then return "touched " .. table.concat(r.touched, ",") end
		if #r.stakesTouched > 0 then return "stake touched" end
	end,
}
