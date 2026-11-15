-- Scenario "clock-plan": A walks and B plans (DESIGN 4). From the default
-- aim at b3: A + right walks about 1 m along the line (the clock's power
-- target moves with the distance, the swivel turns to face b3), B + up twice
-- moves the planned release from 3 to 2 o'clock, B + right tilts the baton
-- (TILT R 5); then the pitch turns to drilling and B + right twice spins
-- the kubb (SPIN R 2), B + down once lowers its arc. The d-pad alone then
-- moves the drill's circle (it never snaps), and back on batons a circle let
-- go near b2 snaps onto it. No throw is made. Frames: 1 the default aim,
-- 2 after the walk, 3 the arc and tilt, 4 the drill with its spin, 5 the
-- circle snapped onto b2.
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
			return f == 112
		end,
	},
	maxFrames = 200,
	check = function(s)
		if s.throws ~= 0 or s.swing.phase ~= "idle" then return "the crank threw while A or B was held" end
		if math.abs(seen.walkX - 1.0) > 0.08 then return string.format("walked to %.2f", seen.walkX) end
		if seen.walkLo == first.powerLo then return "the power target did not move with the stance" end
		if not (seen.walkSw < -0.05) then return string.format("swivel %.3f: not facing b3", seen.walkSw) end
		if seen.release ~= 120 then return "release " .. tostring(seen.release) end
		if seen.relLo ~= 120 - tw.plan.levels.club.releaseHalf then return "release target " .. tostring(seen.relLo) end
		if seen.tilt ~= 5 then return "tilt " .. tostring(seen.tilt) end
		if seen.spin ~= 2 then return "spin " .. tostring(seen.spin) end
		if seen.drillRel ~= 120 then return "the drill's arc " .. tostring(seen.drillRel) end
		if not (seen.my1 > seen.my0 + 0.3) or seen.drillOn then return "the drill's circle did not move freely" end
		local on = s.markerOn
		if not on or on.id ~= "b2" or s.markerX ~= on.x or s.markerY ~= on.y then return "no snap onto b2" end
		if math.abs(s.playerX - on.x) > 1e-6 then return "the stance did not follow the snapped circle" end
	end,
}
