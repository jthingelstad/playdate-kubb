-- Scenario "clock-plan": A walks and B plans (DESIGN 4). From the default
-- aim at b3: A + right walks about 1 m along the line (the clock's power
-- target moves with the distance, the swivel turns to face b3), B + up twice
-- moves the planned release two ticks up from 3 o'clock, B + right tilts the
-- baton a tick (TILT R 1); then the pitch turns to drilling and B + right
-- twice spins the kubb two ticks (SPIN R 0.5), B + down once lowers its arc a
-- tick (plan.tune arcTickDeg, tiltTickDeg, spinTick: engine 0.9). The d-pad alone then
-- moves the drill's circle (it never snaps), and back on batons throw.aimAt
-- near b2 snaps onto it; then the d-pad moves the circle a little off b2 and
-- it stays there (the let-go never snaps: Tyler's play test, 2026-11-15). No
-- throw is made. Frames: 1 the default aim, 2 after the walk, 3 the arc and
-- tilt, 4 the drill with its spin, 5 the circle snapped onto b2, 6 the
-- circle moved off b2 and let go.
import "selftest/_throw"

local st = tw.selftest
local throw = tw.scenes.throw
local first = {}
local seen = {}

local function B(btn) return { hold = { "b" }, press = { btn } } end

st.scenarios["clock-plan"] = st.throwScenario {
	setup = function(s) first.powerLo, first.swivel = s.sol.powerLo, s.swivel end,
	script = {
		{ n = 3 },
		{ n = 42, hold = { "a", "right" } },     -- about 1 m (1.2 m/s, 50 fps)
		{ n = 3 },
		B("up"), { n = 2, hold = { "b" } }, B("up"), { n = 2, hold = { "b" } }, B("right"),
		{ n = 6 },
		{ n = 3 },                                -- (the pitch turns to drilling here)
		B("right"), { n = 2, hold = { "b" } }, B("right"), { n = 2, hold = { "b" } }, B("down"),
		{ n = 6 },
		{ n = 20, hold = { "up" } },              -- the drill's circle out
		{ n = 6 },
		{ n = 3 },                                -- (back to batons)
		{ n = 6 },
		{ n = 8, hold = { "left" } },             -- the circle a little off b2
		{ n = 6 },
	},
	shots = {
		function(s, f) return f == 2 end,
		function(s, f)
			if f == 47 then seen.walkX, seen.walkLo, seen.walkSw = s.playerX, s.sol.powerLo, s.swivel; return true end
		end,
		function(s, f)
			if f == 63 then
				seen.release, seen.tilt, seen.relLo = s.release, s.tilt, s.sol.releaseLo
				throw.setDrill(s, true)
				return true
			end
		end,
		function(s, f)
			if f == 75 then seen.spin, seen.drillRel, seen.my0 = s.spin, s.release, s.markerY; return true end
		end,
		function(s, f)
			if f == 106 then
				seen.my1, seen.drillOn = s.markerY, s.markerOn
				throw.setDrill(s, false)
				-- let go near b2 (at -1, 8): it snaps
				throw.aimAt(s, -0.85, 7.85)
				return false
			end
			if f == 112 then
				local on = s.markerOn
				seen.snapped = on and on.id == "b2" and s.markerX == on.x and s.markerY == on.y
				seen.b2x, seen.snapPX = on and on.x, s.playerX
				return true
			end
		end,
		function(s, f) return f == 126 end,

	},
	maxFrames = 200,
	check = function(s)
		if s.throws ~= 0 or s.swing.phase ~= "idle" then return "the crank threw while A or B was held" end
		if math.abs(seen.walkX - 1.0) > 0.08 then return string.format("walked to %.2f", seen.walkX) end
		if seen.walkLo == first.powerLo then return "the power target did not move with the stance" end
		if not (seen.walkSw < -0.05) then return string.format("swivel %.3f: not facing b3", seen.walkSw) end
		local pt = tw.plan.tune
		local rel = tw.plan.arcFor("base") + 2 * pt.arcTickDeg
		if seen.release ~= rel then return "release " .. tostring(seen.release) end
		if seen.relLo ~= rel - tw.plan.levels.club.releaseHalf then return "release target " .. tostring(seen.relLo) end
		if seen.tilt ~= pt.tiltTickDeg then return "tilt " .. tostring(seen.tilt) end
		if seen.spin ~= 2 * pt.spinTick then return "spin " .. tostring(seen.spin) end
		if seen.drillRel ~= tw.plan.arcFor("drill") - pt.arcTickDeg then return "the drill's arc " .. tostring(seen.drillRel) end
		if not (seen.my1 > seen.my0 + 0.3) or seen.drillOn then return "the drill's circle did not move freely" end
		if not seen.snapped then return "no snap onto b2" end
		if math.abs(seen.snapPX - seen.b2x) > 1e-6 then return "the stance did not follow the snapped circle" end
		local off = seen.b2x - s.markerX
		if s.markerOn or not (off > 0.03 and off < 0.25) then
			return string.format("the circle let go %.3f m off b2 snapped back or did not move", off)
		end
	end,
}
