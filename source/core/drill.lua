-- Drilling a kubb (DESIGN.md "Kubbs (drilling)"). Pure Lua: no playdate.*.
--
-- The aim is a landing marker on the ground in the far half. The thrower
-- stands on the baseline straight behind it (no walk step). The game solves
-- a launch that lands a clean drill on the marker: a low loft chosen by the
-- distance (drill.solve), or the plan's arc (drill.solveAt, which
-- core/throwplan solves with), and the speed that carries the kubb there.
--
-- Play launches a drill with tw.plan.launch (core/throwplan), which judges
-- the swing against the plan and gives drill.body's numbers. drill.launch
-- is the older launch against a power band, kept for core/bench, the tools
-- and tests that throw a clean drill, and the throw scene until it
-- launches drills through the plan:
--   power      against a target band (the power the distance needs): in the
--              band the speed barely moves, outside it the kubb goes short or long
--   smoothness a clean flick keeps the nose down and the kubb dies near the
--              marker; a jerky one wobbles it and it runs on
--   tilt       pushes the line a little sideways, the way pull says (+1 right)
--   cut        spins the kubb about its long axis (+ clockwise from behind): it
--              holds the kubb's attitude to the touch; on the ground it moves
--              it a little either way (which corner strikes first decides)
--
-- All in one frame: x across, y away from the thrower (the throw scene's view
-- frame). world.launchDrill (core/world) makes the body from drill.body's
-- numbers.
import "core/tw"
import "core/flight"

local sqrt, sin, cos, atan, rad, abs, min, max =
	math.sqrt, math.sin, math.cos, math.atan, math.rad, math.abs, math.min, math.max

local drill = {}
local flight = tw.flight

drill.tune = {
	-- the marker (relative to the thrower's baseline)
	markerXMax = 3.0,       -- m either side of the middle: a little past the 2.5 m sidelines
	markerNear = 3.5,       -- m out: a little short of the middle line (4 m)
	markerFar = 8.6,        -- m out: a little past the far baseline (8 m)
	markerStartY = 5.5,     -- m out where the marker starts
	markerSpeed = 0.6,      -- m/s the d-pad moves the marker at first ...
	markerSpeedMax = 3.0,   -- ... rising to this while held
	markerAccel = 3.0,      -- m/s^2 between the two
	throwerXMax = 2.4,      -- m: the thrower stands on the baseline inside the stakes
	-- the solved launch
	loftNearDeg = 26,       -- loft for the nearest marker (guess; a low drill)
	loftFarDeg = 30,        -- loft for the farthest (higher, so a full swing reaches it)
	landZ = 0.07,           -- m: the kubb's center height when its lowest edge reaches the grass
	-- The run on (2026-11-16): a clean drill does not stop where it lands; it bounces,
	-- tumbles and rolls on (Jamie: "it is impossible to stop that much energy with just
	-- the ground and grass"). It is aimed short by the mean distance along the throw that
	-- a clean drill rests past where it lands, by the loft (slideLofts, a row each) and
	-- how far out it lands (slideR, a column each), in a line between them and the
	-- nearest outside them. A faster landing runs on farther until it digs in harder (on
	-- sand soonest). Measured with the drill as a plain body with the turf's bite
	-- (2026-11-16: 3 lines x 20 grounds a cell, aimed with none; the release attitude
	-- and spiral below).
	slideLofts = { 26, 37, 47, 57 },
	slideR = { 1.5, 3, 4.5, 6, 7.5 },
	slide = {
		grass = { { 0.51, 1.47, 2.26, 2.11, 1.59 }, { 0.35, 0.92, 1.47, 1.39, 1.06 },
			{ 0.26, 0.68, 0.87, 0.99, 0.69 }, { 0.18, 0.38, 0.64, 0.81, 0.61 } },
		sand = { { 0.22, 0.74, 0.99, 0.50, 0.36 }, { 0.14, 0.44, 0.51, 0.31, 0.15 },
			{ 0.07, 0.35, 0.29, 0.19, 0.14 }, { 0.06, 0.17, 0.20, 0.17, 0.12 } },
		snow = { { 0.50, 1.58, 2.05, 1.90, 2.05 }, { 0.37, 0.99, 1.46, 1.42, 1.53 },
			{ 0.23, 0.71, 0.92, 1.09, 1.12 }, { 0.17, 0.39, 0.59, 0.83, 0.87 } },
	},
	slideRefM = 6,          -- m: the landing distance slideFor reads when given none
	-- the body at release (world.drillLaunchState, 2026-11-16: the drill is a plain
	-- rigid body, like a baton). Jamie: "we didn't treat Kubb throws with the same
	-- physics as baton throws" and "Good drillers would never let a Kubb flip in the
	-- air". Held by its back end at the bottom of an underhand swing, the kubb hangs
	-- nose forward and down; the wrist's snap spirals it about its long axis, a
	-- gyroscope, so it lands about as it left the hand: nose first.
	noseDownDeg = 45,       -- the long axis this far below the horizontal at release on the
	                        -- planned arc (Jamie's technique: it lands nose first at about 45).
	                        -- A spun drill (a tap or more) holds it to the touch; with only the
	                        -- small natural spiral the air turns the kubb toward broadside to its
	                        -- fall, so it lands steeper (about 60 to 65) and less the same each
	                        -- time. A later release (higher loft) lifts the nose with the arm,
	                        -- degree for degree, an earlier one drops it.
	spiral = 3,             -- rad/s: the small spiral the wrist always gives a drill (+ = clockwise
	                        -- from behind; Jamie: "even if the thrower indicates no spin, there
	                        -- would always be some small, subtle amount of rotation"); B +
	                        -- left/right taps add to it (plan.tune.spinPerStep)
	pitchSdDps = 30,        -- deg/s sd of the swing's nose up or down turn at release ...
	yawSdDps = 15,          -- ... of a turn across the line (about the kubb's own up) ...
	spinSd = 3,             -- ... rad/s of the spiral ...
	noseSdDeg = 4,          -- ... degrees of the release attitude ...
	scatterJerk = 1.5,      -- ... each this much more again for a jerky swing (smoothness 0)
	-- the swing against the band
	bandNear = 0.35,        -- swing power the nearest marker needs (gauge band center)
	bandFar = 0.85,         -- ... and the farthest; leaves room above to throw long
	bandHalf = 0.06,        -- the band is this wide either side of its center
	inBandGain = 0.25,      -- inside the band a power error counts this much
	speedPerPower = 1.0,    -- outside: launch speed changes by this fraction per unit of power
	speedMinFrac = 0.4,     -- never slower than this fraction of the solved speed
	cleanAbove = 0.75,      -- smoothness at or above this is a clean flick: no wobble
	wobbleRate = 10,        -- rad/s of nose-over wobble at smoothness 0 (scales with how far
	                        -- under cleanAbove the swing was)
	tiltPushDeg = 0.05,     -- degrees of line per degree of swing tilt
	cutSpin = 25,           -- rad/s about the long axis with A or B held at release (drill.launch;
	                        -- the plan's spin is plan.tune.spinPerStep a tap)
}

drill.CUT_NONE, drill.CUT_A, drill.CUT_B = 0, 1, -1

local function lerp(a, b, f)
	return a + (b - a) * f
end

-- Keep the marker in its area: mx across, my as distance from lineY.
function drill.clampMarker(mx, my)
	local t = drill.tune
	return max(-t.markerXMax, min(t.markerXMax, mx)), max(t.markerNear, min(t.markerFar, my))
end

-- The speed that lands a launch from height h0 above the landing height at
-- loft e (radians) a horizontal distance R away.
local function speedFor(R, e, h0, g)
	local c = cos(e)
	return sqrt(g * R * R / (2 * c * c * (R * sin(e) / c + h0)))
end

-- Solve the clean drill onto the marker (mx, my in the view frame, the
-- thrower's baseline at lineY) at the loft the distance picks (loftNearDeg to
-- loftFarDeg). Fills and returns `out`:
--   x          where the thrower stands on the baseline
--   swivel     radians, + = right
--   loft       degrees
--   dist       m from the thrower to the marker
--   speed      m/s of the clean launch
--   band       swing power that gives exactly that speed (band center)
--   T          s from release until the kubb's edge reaches the grass
function drill.solve(mx, my, lineY, out)
	local t = drill.tune
	local x = max(-t.throwerXMax, min(t.throwerXMax, mx))
	local dx, dy = mx - x, my - lineY
	local d = sqrt(dx * dx + dy * dy)
	local f = max(0, min(1, (d - t.markerNear) / (t.markerFar - t.markerNear)))
	return drill.solveAt(mx, my, lineY, lerp(t.loftNearDeg, t.loftFarDeg, f), out, x)
end

-- Where a table's sorted keys put x: the index below and the share of the
-- way to the next (clamped at both ends).
local function between(keys, x)
	local n = #keys
	if x <= keys[1] then return 1, 0 end
	if x >= keys[n] then return n - 1, 1 end
	for i = 2, n do
		if x <= keys[i] then return i - 1, (x - keys[i - 1]) / (keys[i] - keys[i - 1]) end
	end
	return n - 1, 1
end

-- How far a clean drill at this loft (degrees) runs on along the throw after
-- it lands R m out (nil: slideRefM), on this ground (nil: grass):
-- tune.slide, between its rows and columns. spin is taken and not used:
-- spin moves a drill across more than along, and in no steady direction
-- (which corner strikes first decides more).
function drill.slideFor(loftDeg, surface, spin, R)
	local t = drill.tune
	local rows = t.slide[surface or "grass"] or t.slide.grass
	local i, fi = between(t.slideLofts, loftDeg)
	local j, fj = between(t.slideR, R or t.slideRefM)
	local a, b = rows[i], rows[i + 1]
	return max(0, lerp(lerp(a[j], a[j + 1], fj), lerp(b[j], b[j + 1], fj), fi))
end

-- The landing distance that runs on to d (m) at this loft: the R with
-- R + slideFor(R) = d (a few steps; the run on changes slower than R).
function drill.landFor(d, loftDeg, surface, spin)
	local R = d
	for _ = 1, 6 do
		R = d - drill.slideFor(loftDeg, surface, spin, R)
		if R < 0.5 then R = 0.5 end
	end
	return R
end

-- The clean drill onto the marker at a given loft (degrees): the plan's arc
-- (core/throwplan). px is where the thrower stands on the baseline (nil:
-- straight behind the marker, inside throwerXMax); surface the ground (nil:
-- grass) and spin the planned spin (rad/s, nil: none), for how far it runs
-- on (drill.slideFor). Fills and returns `out` with the fields of
-- drill.solve. No table is made when `out` is given.
function drill.solveAt(mx, my, lineY, loftDeg, out, px, surface, spin)
	local t = drill.tune
	out = out or {}
	local x = px or max(-t.throwerXMax, min(t.throwerXMax, mx))
	local dx, dy = mx - x, my - lineY
	local d = sqrt(dx * dx + dy * dy)
	local f = max(0, min(1, (d - t.markerNear) / (t.markerFar - t.markerNear)))
	local ft = flight.tune
	local h0 = ft.handHeight - t.landZ
	local e = rad(loftDeg)
	local R = drill.landFor(d, loftDeg, surface, spin)
	local v = speedFor(R, e, h0, ft.g)
	local vz = v * sin(e)
	out.x, out.swivel, out.loft, out.dist, out.speed = x, atan(dx, dy), loftDeg, d, v
	out.band = lerp(t.bandNear, t.bandFar, f)
	out.T = (vz + sqrt(vz * vz + 2 * ft.g * h0)) / ft.g
	return out
end

-- The power error as it reaches the speed: shrunk inside the band.
function drill.powerError(power, band)
	local t = drill.tune
	local err = power - band
	local a = abs(err)
	if a <= t.bandHalf then return err * t.inBandGain end
	local e = t.bandHalf * t.inBandGain + (a - t.bandHalf)
	return err < 0 and -e or e
end

-- "short", "on" or "long": where the swing's power sat against the band.
function drill.judge(power, band)
	local d = power - band
	if d < -drill.tune.bandHalf then return "short" end
	if d > drill.tune.bandHalf then return "long" end
	return "on"
end

-- The band launch for `r` = { power, smoothness, tilt, pull } against the
-- solution `sol` (drill.solve), with cut drill.CUT_NONE / CUT_A / CUT_B: the
-- solved loft, the speed from the power against the band, the line pushed by
-- the tilt the way pull says (+1 right, the default; -1 left, also the
-- wobble's sign). Fills and returns `out`: swivel, loft, speed, noseDown,
-- rollLand, spin, wobble (the arguments of world.launchDrill after
-- x and lineY), plus jerk (0..1). Not the plan's launch (tw.plan.launch):
-- the release angle is not read.
function drill.launch(sol, r, cut, out)
	local t = drill.tune
	out = out or {}
	local e = drill.powerError(r.power or 0, sol.band)
	out.speed = sol.speed * max(t.speedMinFrac, 1 + t.speedPerPower * e)
	local pull = (r.pull or 1) < 0 and -1 or 1
	out.swivel = sol.swivel + pull * rad(t.tiltPushDeg * (r.tilt or 0))
	out.loft = sol.loft
	-- A (+1) spins it positive about the forward long axis (clockwise from
	-- behind), B the other way, on top of the wrist's spiral
	return drill.body(r.smoothness or 1, pull, (cut or 0) * t.cutSpin, out)
end

-- The drilled kubb's body at release (world.launchDrill's arguments after
-- the line of flight): fills `out` with noseDown, rollLand, spin (rad/s about
-- the long axis: as given plus the wrist's spiral), wobble and jerk (0..1). smoothness is the
-- swing's (or the plan's effective smoothness: core/throwplan); under
-- cleanAbove the kubb wobbles nose over tail, up to wobbleRate at 0 and
-- never more. pull (+1 or -1) is the wobble's sign.
function drill.body(smoothness, pull, spin, out, dLoft)
	local t = drill.tune
	local jerk = (t.cleanAbove - smoothness) / t.cleanAbove
	if jerk < 0 then jerk = 0 elseif jerk > 1 then jerk = 1 end
	spin = (spin or 0) + t.spiral
	out.noseDown, out.rollLand, out.spin = t.noseDownDeg - (dLoft or 0), 0, spin
	out.jerk = jerk
	out.wobble = pull * t.wobbleRate * jerk
	return out
end


tw.drill = drill
