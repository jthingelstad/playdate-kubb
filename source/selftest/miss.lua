-- Scenario "miss": the circle on bare ground half a meter right of b3 (it
-- does not snap: b3 is farther than the circle's radius), the stance behind
-- it and the plan's clean throw: the baton passes between b3 and b4, lands past the far baseline and touches
-- nothing. Frames: 1 the impact camera near the landing, 2 at rest.
import "selftest/_throw"

local st = tw.selftest

st.scenarios.miss = st.throwScenario {
	setup = function(s) tw.scenes.throw.aimAt(s, 0.5, 8) end,
	script = function(s) return st.planned(s) end,
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
