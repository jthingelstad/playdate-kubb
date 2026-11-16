-- Scenario "clock-drill": a drilled kubb (DESIGN 4 "Kubbs (drilling)") on
-- the practice pitch. The circle 0.6 m right of the middle and 6.2 m out
-- (where the kubb should rest), the thrower behind it on the baseline, the
-- drill arc (half past 1) and one tap of spin; the crank winds into the
-- power target and stops at half past 1: the kubb rests within 1 m of the
-- circle and stays on the pitch (0.4 m until 2026-11-16; a drill now runs on
-- and its tap rolls it, so where it ends varies with the ground: 0.18 m on the
-- Simulator then). Frames: 1 aiming (the circle and
-- its line, SPIN R 1), 2 in flight, 3 at rest (n CM AWAY, the verdicts),
-- 4 aiming again with the drilled kubb lying there.
import "selftest/_throw"

local st = tw.selftest
local throw = tw.scenes.throw
local MX, MY = 0.6, 6.2

st.scenarios["clock-drill"] = st.throwScenario {
	setup = function(s)
		throw.setDrill(s, true)
		throw.aimAt(s, MX, MY)
		throw.setSpin(s, 1)
	end,
	script = function(s) return st.planned(s) end,
	shots = {
		function(s, f) return f == 3 end,
		function(s) return s.mode == "flight" and s.showTime > 0.35 end,
		st.restShot(30),
		st.restShot(70),
	},
	maxFrames = 500,
	check = function(s)
		local l = s.last
		if not l or not l.drill then return "the throw was not a drill" end
		if math.abs(s.sol.release - 135) > 1e-6 then return "the drill arc is " .. s.sol.release end
		if math.abs(s.markerX - MX) > 1e-6 or math.abs(s.markerY - MY) > 1e-6 then return "the circle moved" end
		local d = math.sqrt((l.restX - MX) ^ 2 + (l.restY - MY) ^ 2)
		if d > 1.0 then return string.format("rested %.2f m from the circle", d) end
		if not s.restText then return "no rest distance shown" end
		local kept = st.item(s, "d1")
		if not kept or math.abs(kept.x - l.restX) > 1e-3 then return "the drilled kubb was not kept" end
		if s.mode ~= "aim" then return "mode " .. s.mode end
		return nil, string.format("land_m=%.2f rest_m=%.2f loft=%.1f", math.sqrt((l.landX - MX) ^ 2 + (l.landY - MY) ^ 2),
			d, l.launchLoft)
	end,
}
