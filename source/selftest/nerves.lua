-- Scenario "nerves": the clean planned swing of "clock-throw" with the
-- nerves on (plan.tune "Nerves"), at a base kubb from the baseline. The
-- swing is the plan's, so the power, release and steadiness verdicts are
-- ON ON STEADY; the nerves' seeded draw (from the swing and the plan, so the
-- same every run) still moves the throw off the line, and the fourth cell
-- shows which way the throw went.
-- Frames: 1 aiming, 2 at rest, 3 aiming again (the four verdicts).
import "selftest/_throw"

local st = tw.selftest

st.scenarios["nerves"] = st.throwScenario {
	nerves = true,
	setup = function(s) tw.scenes.throw.aimAt(s, 2, 8) end,
	script = function(s) return st.planned(s) end,
	shots = {
		function(s, f) return f == 3 end,
		st.restShot(30),
		function(s) return s.mode == "aim" and s.throws == 1 end,
	},
	maxFrames = 500,
	check = function(s)
		local l = s.last
		if not l.sideDeg or l.sideDeg == 0 then return "no nerves on the throw: " .. tostring(l.sideDeg) end
		-- the draw is seeded from the swing and the plan: the same every run. Engine 0.9's
		-- lower aim (aimHeightShare 0.3) changed the plan, so the draw went from pulled
		-- left (to 0.8) to pulled right
		if s.vSide ~= 1 then return "want PULLED RIGHT, got sideV " .. tostring(s.vSide) end
		if s.vPower ~= 0 or s.vRelease ~= 0 or not s.vSteady then
			return string.format("verdicts %s %s %s", tostring(s.vPower), tostring(s.vRelease), tostring(s.vSteady))
		end
		if s.vSide ~= l.sideV or (s.vSide ~= -1 and s.vSide ~= 0 and s.vSide ~= 1) then
			return "side verdict " .. tostring(s.vSide)
		end
		if not s.showVerdicts then return "no verdicts on the next aim" end
		local r = s.result
		return nil, string.format("side=%.2fdeg len=%.3f sideV=%d hit=%s", l.sideDeg, l.lenShare, s.vSide,
			tostring(r and r.firstHit and r.firstHit.with))
	end,
}
