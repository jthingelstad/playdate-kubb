-- The throw plan (DESIGN.md section 4, "The throw: the crank as a clock").
-- Pure Lua: no playdate.*.
--
-- The player picks a target (a point in the far half), a stance (where they
-- stand on or behind the throwing line) and a plan (the arc as a release
-- angle on the clock, a tilt for a baton, spin for a kubb). tw.plan turns
-- those into the gauge's two targets, the power target (the backswing this
-- throw needs) and the release target (where to stop the crank), and turns a
-- measured swing (core/swing's result) into a launch for core/world.
--
-- The clock, in degrees from 6 o'clock: the backswing goes up the left side
-- (30 = 7 o'clock, 90 = 9, 120 = 10, 180 = 12), the forward swing up the
-- right (30 = 5 o'clock, 90 = 3, 150 = 1, 180 = 12).
--
-- Two scales:
--   power  the backswing sets a launch speed (plan.speedFor). Its scale is
--          the reach (plan.reach): how far a clean baton at the reference
--          arc (3 o'clock, refLoftDeg) carries on flat ground from the hand.
--          0 m at 7 o'clock, 4 m at 9, 8 m at 10, and on up a quadratic:
--          corner to corner (9.4 m) at about 10:17, 13.3 m at 11, 20 m at 12.
--   loft   the release angle sets the launch angle (plan.loftFor), a line
--          through 5 o'clock = 12 degrees and 3 o'clock = 32 (half past 1 =
--          47, 12 o'clock = 62).
--
-- One frame throughout: the thrower's view frame (core/frame), throwing
-- from lineY toward +y, x to the right. Swivel is radians from straight
-- downfield, + = toward +x (right), as core/flight and core/world use it.
--
-- The functions the throw scene calls every aim frame (stance, snap, solve,
-- the scales) make no tables or closures: they fill an `out` table.
import "core/tw"
import "core/flight"
import "core/drill"

local sqrt, sin, cos, tan, atan, rad, deg = math.sqrt, math.sin, math.cos, math.tan, math.atan, math.rad, math.deg

local plan = {}
local flight, drill = tw.flight, tw.drill

plan.tune = {
	-- the power scale (plan.reach): reach = a u + c u^2 with u = back - reachZeroDeg,
	-- a and c fitted through the two anchors below. A quadratic through
	-- (30, 0), (90, 4), (120, 8) has a = 1/45 and c = 1/1350, both positive, so
	-- it rises from zero, is smooth and monotonic, and gets steeper past 10
	-- o'clock: 9.4 m (corner to corner) at 128.6 degrees (about 10:17), 13.3 m
	-- at 11 o'clock, 20 m at 12 (overpowered: more than any throw needs).
	reachZeroDeg = 30,     -- backswing degrees where the reach is 0 (7 o'clock; the dead zone ends)
	reachAnchor1Deg = 90,  -- 9 o'clock ...
	reachAnchor1 = 4.0,    -- ... carries about 4 m
	reachAnchor2Deg = 120, -- 10 o'clock ...
	reachAnchor2 = 8.0,    -- ... carries 8 m: a baseline baton
	refLoftDeg = 32,       -- the reference arc the reach is measured at: 3 o'clock (loftFor(90))
	-- the loft scale (plan.loftFor): a line through two points
	loftRel1 = 30,  loftAt1 = 12,  -- 5 o'clock: low and flat
	loftRel2 = 90,  loftAt2 = 32,  -- 3 o'clock: the normal throw
	loftMinDeg = 2,        -- the launch angle never goes under this ...
	loftMaxDeg = 75,       -- ... or over this (a sky ball reaches it)
	-- the plan (B + d-pad)
	arc = { base = 90, king = 75, field = 60, drill = 135 }, -- default release by target: 3
	                       -- o'clock at base kubbs, half past 3 at the king, 4 at field
	                       -- kubbs, half past 1 for a drilled kubb
	arcStepDeg = 15,       -- B + up/down moves the release target half an hour
	releaseMinDeg = 15,    -- the planned release stays between half past 5 ...
	releaseMaxDeg = 165,   -- ... and half past 12
	tiltStepDeg = 5,       -- B + left/right on a baton: one tap tilts the spin plane this much. Measured
	                       -- (tools/tiltgroups.lua, 2026-11-15): tilt deflects the baton after its first
	                       -- hit by only about 0.15 degrees per degree, so finer steps make no visible
	                       -- difference
	tiltMaxDeg = 20,       -- ... up to this either way (Jamie, 2026-11-15: tap up to 20 in steps of 5).
	                       -- With the shake it adds up toward legalTiltDeg, the helicopter
	spinSteps = 3,         -- B + left/right on a kubb: up to this many taps either way
	spinPerStep = 22,      -- rad/s about the long axis per tap (+ rolls right). Measured (tools/spinwall.lua,
	                       -- 2026-11-15, the plan's clean drill on grass at loft 47): 0 taps rests within
	                       -- 0.01 m of where it lands, 1 tap rolls 0.27 m sideways, 2 taps 0.61, 3 taps 0.90
	                       -- (loft 30: 0.24, 0.52, 0.81; sand about 45% of that), forward 0.04 to 0.19 m back
	defaultLevel = "club", -- the level when none is given
	-- the swing against the plan (plan.launch)
	skyExtraDeg = 45,      -- a sky ball (the crank on past 12): its release counts as this
	                       -- many degrees past where it stopped (at least 12 o'clock), so it
	                       -- leaves near loftMaxDeg, high and short: the large error
	legalTiltDeg = 30,     -- a tilt over this is a helicopter (II.B.1); the old swing's
	                       -- 90 * (1 - smoothness) was legal at 30 or under
	shakeTiltDeg = 90,     -- tilt of a throw with shake 1 at full cost (the old mapping)
	lateralDeg = 3,        -- swivel pull of a throw with shake 1 at full cost (first guess:
	                       -- a baton at 8 m only hits within about 0.4 degrees)
	overPerDeg = 30,       -- the overpower multiplier grows by overGain per this many
	                       -- degrees of backswing past the power target
	steadyBelow = 0.25,    -- shake under this is STEADY
	-- the baton's tumble from its launch speed (the old swing: 4.5 rad/s at 4.0 m/s
	-- to 7.0 at 9.2 m/s, a line through those), clamped
	tumbleV1 = 4.0, tumbleAt1 = 4.5,
	tumbleV2 = 9.2, tumbleAt2 = 7.0,
	tumbleMin = 3.0, tumbleMax = 9.0,
}

-- Throw levels (DESIGN 4 "Throw levels"): how wide the gauge's targets are and
-- how much a miss costs. First guesses, to be fitted from play.
--   powerHalf    degrees either side of the power target's center
--   releaseHalf  degrees either side of the release target's center
--   inGain       share of an error inside a target that still counts
--   shakeGain    share of the shake's tilt and pull that counts
--   overGain     how fast overpowering multiplies the shake's costs
plan.levels = {
	beginner = { powerHalf = 15, releaseHalf = 30, inGain = 0.1, shakeGain = 0.5,  overGain = 0.5 },
	club     = { powerHalf = 8,  releaseHalf = 18, inGain = 0.3, shakeGain = 0.75, overGain = 0.75 },
	pro      = { powerHalf = 4,  releaseHalf = 10, inGain = 0.6, shakeGain = 1,    overGain = 1 },
}
plan.LEVELS = { "beginner", "club", "pro" }

-- The level table for a name or a level table (nil: tune.defaultLevel).
function plan.level(l)
	if type(l) == "table" then return l end
	return plan.levels[l or plan.tune.defaultLevel] or plan.levels[plan.tune.defaultLevel]
end
local levelOf = plan.level

-- ---------------------------------------------------------------------------
-- The scales

-- The quadratic's coefficients from the anchors (worked out per call from the
-- tune, so a change to it takes at once; a few multiplications).
local function reachCoeffs()
	local t = plan.tune
	local u1, u2 = t.reachAnchor1Deg - t.reachZeroDeg, t.reachAnchor2Deg - t.reachZeroDeg
	local c = (t.reachAnchor2 / u2 - t.reachAnchor1 / u1) / (u2 - u1)
	return t.reachAnchor1 / u1 - c * u1, c
end

-- Meters a clean baton thrown with this backswing (degrees) carries at the
-- reference arc on flat ground from the hand height: the power scale.
function plan.reach(backDeg)
	local u = backDeg - plan.tune.reachZeroDeg
	if u <= 0 then return 0 end
	local a, c = reachCoeffs()
	return a * u + c * u * u
end

-- The backswing (degrees) whose reach is reachM: plan.reach's inverse.
function plan.backFor(reachM)
	local z = plan.tune.reachZeroDeg
	if reachM <= 0 then return z end
	local a, c = reachCoeffs()
	if c < 1e-12 then return z + reachM / a end
	return z + (-a + sqrt(a * a + 4 * c * reachM)) / (2 * c)
end

-- The speed that carries R (m) from hand height h to the ground at loft e
-- (radians), the drag-free arc of flight.predict.
local function carrySpeed(R, e, h, g)
	local ce = cos(e)
	return sqrt(g * R * R / (2 * ce * ce * (R * tan(e) + h)))
end

-- The launch speed (m/s) a backswing gives with a full flick: the speed whose
-- clean flight at refLoftDeg carries plan.reach(backDeg).
function plan.speedFor(backDeg)
	local R = plan.reach(backDeg)
	if R <= 0 then return 0 end
	local ft = flight.tune
	return carrySpeed(R, rad(plan.tune.refLoftDeg), ft.handHeight, ft.g)
end

-- How far a launch speed carries at the reference arc (m): the reach it is.
function plan.reachForSpeed(speed)
	local _, ly = flight.predict(0, 0, 0, plan.tune.refLoftDeg, speed)
	return ly
end

-- The backswing (degrees) that gives this launch speed with a full flick.
function plan.backForSpeed(speed)
	if speed <= 0 then return plan.tune.reachZeroDeg end
	return plan.backFor(plan.reachForSpeed(speed))
end

-- The launch angle (degrees) for a release angle (degrees past 6 o'clock on
-- the forward side), clamped to loftMinDeg..loftMaxDeg.
function plan.loftFor(releaseDeg)
	local t = plan.tune
	local l = t.loftAt1 + (releaseDeg - t.loftRel1) * (t.loftAt2 - t.loftAt1) / (t.loftRel2 - t.loftRel1)
	if l < t.loftMinDeg then return t.loftMinDeg end
	if l > t.loftMaxDeg then return t.loftMaxDeg end
	return l
end

-- The release angle (degrees) for a launch angle: plan.loftFor's inverse.
function plan.releaseFor(loftDeg)
	local t = plan.tune
	if loftDeg < t.loftMinDeg then loftDeg = t.loftMinDeg elseif loftDeg > t.loftMaxDeg then loftDeg = t.loftMaxDeg end
	return t.loftRel1 + (loftDeg - t.loftAt1) * (t.loftRel2 - t.loftRel1) / (t.loftAt2 - t.loftAt1)
end

-- The baton's tumble rate (rad/s) for a launch speed.
function plan.tumbleFor(speed)
	local t = plan.tune
	local r = t.tumbleAt1 + (speed - t.tumbleV1) * (t.tumbleAt2 - t.tumbleAt1) / (t.tumbleV2 - t.tumbleV1)
	if r < t.tumbleMin then return t.tumbleMin end
	if r > t.tumbleMax then return t.tumbleMax end
	return r
end

-- Clamp a planned release to releaseMinDeg..releaseMaxDeg.
function plan.clampRelease(releaseDeg)
	local t = plan.tune
	if releaseDeg < t.releaseMinDeg then return t.releaseMinDeg end
	if releaseDeg > t.releaseMaxDeg then return t.releaseMaxDeg end
	return releaseDeg
end

-- The default release for a target kind: "base", "king", "field" or "drill".
function plan.arcFor(kind)
	return plan.tune.arc[kind] or plan.tune.arc.base
end

-- ---------------------------------------------------------------------------
-- Stance, snap and solve (every aim frame)

-- The default stance: straight behind the target (x clamped inside
-- +/- halfWidth, the line's ends), as far forward as allowed (forwardY, the
-- advantage line or the baseline; nil = lineY). Fills out.x, out.y.
function plan.stance(tx, ty, lineY, forwardY, halfWidth, out)
	local x = tx
	if x < -halfWidth then x = -halfWidth elseif x > halfWidth then x = halfWidth end
	out.x, out.y = x, forwardY or lineY
	return out
end

-- The nearest of targets[1..n] (each {x, y}: standing kubbs and the king)
-- within radius of (tx, ty), and its index; nil when none is that close.
function plan.snap(tx, ty, targets, n, radius)
	local best, bi, bd = nil, nil, radius * radius
	for i = 1, n do
		local p = targets[i]
		local dx, dy = p.x - tx, p.y - ty
		local d = dx * dx + dy * dy
		if d <= bd then best, bi, bd = p, i, d end
	end
	return best, bi
end

-- Solve the plan. q = { projectile = "baton" | "kubb", px, py (the stance),
-- tx, ty (the target), release (planned degrees, clamped to the plan's
-- range), level (name or table), surface and spin (a kubb's ground and
-- planned spin in taps: how far it runs on, drill.slideFor; nil: grass, none) }. Fills and returns `out`:
--   swivel     radians, + = right
--   dist       m from the stance to the target
--   loft       degrees, loftFor(release)
--   speed      m/s of the clean launch: a baton's center comes down on the
--              target (flight.predict); a kubb's drill rests on it
--              (drill.solveAt at that loft)
--   back       the backswing that gives that speed with a full flick
--   powerLo, powerHi      the power target: back -/+ level.powerHalf
--   release, releaseLo, releaseHi   the release target: release -/+ level.releaseHalf
--   projectile, px, py, tx, ty, level (the level table)
-- For a kubb also drill.solveAt's x, band and T.
function plan.solve(q, out)
	local lv = levelOf(q.level)
	local rel = plan.clampRelease(q.release or plan.tune.arc.base)
	local loft = plan.loftFor(rel)
	local px, py, tx, ty = q.px, q.py, q.tx, q.ty
	if q.projectile == "kubb" then
		drill.solveAt(tx, ty, py, loft, out, px, q.surface, (q.spin or 0) * plan.tune.spinPerStep)
	else
		local dx, dy = tx - px, ty - py
		local d = sqrt(dx * dx + dy * dy)
		local ft = flight.tune
		out.swivel, out.dist, out.loft = atan(dx, dy), d, loft
		out.speed = carrySpeed(d > 0.1 and d or 0.1, rad(loft), ft.handHeight, ft.g)
	end
	local back = plan.backForSpeed(out.speed)
	out.back, out.powerLo, out.powerHi = back, back - lv.powerHalf, back + lv.powerHalf
	out.release, out.releaseLo, out.releaseHi = rel, rel - lv.releaseHalf, rel + lv.releaseHalf
	out.projectile, out.px, out.py, out.tx, out.ty, out.level = q.projectile or "baton", px, py, tx, ty, lv
	return out
end

-- ---------------------------------------------------------------------------
-- The launch (once per throw)

-- An error e against a target half width h: inside the target it counts
-- inGain of itself; outside, the part beyond the edge counts in full. The two
-- meet at the edge (continuous).
function plan.shrink(e, h, inGain)
	if e >= -h and e <= h then return e * inGain end
	if e > 0 then return h * inGain + (e - h) end
	return -h * inGain + (e + h)
end
local shrink = plan.shrink

local NO_OPTS = {}

-- Which side of the range [lo, hi] v is on: -1, 0, 1.
local function side(v, lo, hi)
	if v < lo then return -1 end
	if v > hi then return 1 end
	return 0
end

-- The launch for swing result `r` against the solution `sol`. r: back,
-- releaseAngle, flickFrac, smoothness, shake, pull (+1 / -1), how ("stopped"
-- or "sky"). opts = { projectile, tilt (planned degrees, a baton), spin
-- (planned taps, a kubb: + rolls right), level } (projectile and level
-- default to the solution's). Fills and returns `out`:
--   speed, loft, swivel, tilt, tumble   the launch (world.launchBaton's arguments)
--   legal      false for a helicopter: |tilt| over legalTiltDeg (a baton; a kubb is always legal)
--   powerV     -1 short, 0 on, 1 long: the power the throw got (backswing times flick)
--              against the power target; -2 slow: the backswing was enough, the flick was not
--   releaseV   -1 low, 0 on, 1 high: where the crank stopped against the release target
--   steady     shake under steadyBelow
--   over       how much overpowering multiplied the shake's costs (0 = none)
--   back, release   the effective backswing and release after the target's forgiveness
-- For a kubb also noseDown, rollLand, spin (rad/s), wobble, digGain, jerk
-- (drill.body: world.launchDrill's arguments after the loft and speed);
-- tumble is 0 and tilt is only the shake's.
function plan.launch(sol, r, opts, out)
	local t = plan.tune
	opts = opts or NO_OPTS
	local lv = levelOf(opts.level or sol.level)
	local kubb = (opts.projectile or sol.projectile) == "kubb"
	local shake = r.shake or (1 - (r.smoothness or 1))
	local pull = (r.pull or 1) < 0 and -1 or 1
	local flick = r.flickFrac or 1
	local back = r.back or 0
	-- power: the backswing, forgiven inside the target, sets the speed; the
	-- flick delivers its share of it
	local effBack = sol.back + shrink(back - sol.back, lv.powerHalf, lv.inGain)
	out.speed = plan.speedFor(effBack) * flick
	-- release: where the crank stopped, forgiven inside the target, sets the
	-- loft; a sky ball counts skyExtraDeg past 12 o'clock or where it stopped
	local rel = r.releaseAngle or sol.release
	if r.how == "sky" then
		if rel < 180 then rel = 180 end
		rel = rel + t.skyExtraDeg
	end
	if rel < 0 then rel = 0 end
	local effRel = sol.release + shrink(rel - sol.release, lv.releaseHalf, lv.inGain)
	out.loft = plan.loftFor(effRel)
	-- overpower: every 30 degrees past the power target multiplies the shake's costs
	local past = back - sol.powerHi
	local m = 1 + lv.overGain * (past > 0 and past or 0) / t.overPerDeg
	local se = shake * lv.shakeGain * m -- the shake as it counts
	local shakeTilt = t.shakeTiltDeg * se
	out.swivel = sol.swivel + rad(pull * t.lateralDeg * se)
	-- the power verdict goes by what the throw got: the backswing times the
	-- flick (Jamie's first play-test throw, 2026-11-15: back on the target, a
	-- 534 deg/s flick, 2.6 m of an 8 m throw, and the verdict said ON). Short
	-- of the target with the backswing on it or past it is a slow flick: -2.
	local got = plan.backForSpeed(plan.speedFor(back) * flick)
	local pv = side(got, sol.powerLo, sol.powerHi)
	if pv < 0 and back >= sol.powerLo then pv = -2 end
	out.powerV = pv
	out.releaseV = r.how == "sky" and 1 or side(r.releaseAngle or sol.release, sol.releaseLo, sol.releaseHi)
	out.steady = shake < t.steadyBelow
	out.over = m - 1
	out.back, out.release = effBack, effRel
	if kubb then
		out.tilt = pull * shakeTilt
		out.legal = true
		out.tumble = 0
		drill.body(1 - se, pull, (opts.spin or 0) * t.spinPerStep, out)
	else
		local tilt = (opts.tilt or 0) + pull * shakeTilt
		out.tilt = tilt
		out.legal = (tilt < 0 and -tilt or tilt) <= t.legalTiltDeg
		out.tumble = plan.tumbleFor(out.speed)
	end
	return out
end

local POWER = { [-2] = "SLOW", [-1] = "SHORT", [0] = "ON", [1] = "LONG" }
local RELEASE = { [-1] = "LOW", [0] = "ON", [1] = "HIGH" }

-- The HUD's verdicts after a throw, a word each: power (SLOW, SHORT, ON, LONG),
-- release (LOW, ON, HIGH) and steadiness (STEADY, SHAKY).
function plan.verdictText(out)
	return POWER[out.powerV or 0], RELEASE[out.releaseV or 0], out.steady and "STEADY" or "SHAKY"
end

tw.plan = plan
