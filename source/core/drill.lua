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
--   cut        spins the kubb about its long axis; once it is down the spin
--              rolls it sideways, face over face (+ right)
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
	-- a clean drill rests past its aim, by the loft (these lofts; between them in a line,
	-- outside them the nearest) and the ground. Measured (tools/drillscatter.lua part 3's
	-- markers, 8 grounds each, aimed with none) and checked with these in place.
	slideLofts = { 26, 37, 47, 57 },
	spinSlide = 0.15,       -- a drill with planned spin (rollSpin and over) plugs and rolls: it runs on
	                        -- only this share of that along the throw
	slide = {
		grass = { 0.91, 0.62, 0.38, 0.24 },
		sand = { 0.40, 0.19, 0.10, 0.06 },
		snow = { 1.52, 1.16, 0.81, 0.53 },
	},
	-- ... at a marker slideRefM out (about the middle of those markers); a longer drill
	-- is faster and runs on slidePerM more each metre farther, a shorter one less
	-- (measured 4 to 8.6 m out, 2026-11-16)
	slideRefM = 6,
	slidePerM = { grass = 0.13, sand = 0.07, snow = 0.17 },
	-- the body in the air (world.launchDrill, world.drillLaunchState). Jamie, 2026-11-16:
	-- "the Kubbs are still 'flying' flat, that is also totally unrealistic. They change
	-- angle in the air."
	noseDownDeg = 15,       -- the clean throw's long axis this far below the horizontal when the nose
	                        -- first touches (Jamie, 2026-11-15: "about 15 degrees"); the release
	                        -- attitude is solved back from it through the turn below
	pitchDps = 70,          -- deg/s it comes nose over in the air (no spin: it leaves the hand nose up
	                        -- along its flight, 55 degrees up at the 47 arc, 35 at 30, and comes over;
	                        -- a fast spin holds the axis, so with taps it leaves the hand about as it lands)
	pitchSdDps = 15,        -- deg/s sd of the swing's own scatter in that turn ...
	yawSdDps = 15,          -- ... in a turn across the line (about the kubb's own up) ...
	spinSd = 0.5,           -- ... rad/s in its roll about the long axis ...
	scatterJerk = 1.5,      -- ... each this much more again for a jerky swing (smoothness 0)
	rollLandDeg = -15,      -- roll about the long axis when the nose first touches: this far short of
	                        -- flat on its bottom face, the spin turning it flat during the catch (flat
	                        -- with no spin; -15 rolled the most evenly of -30..30)
	digGain = 1,            -- how much harder a drilled kubb's first touches dig in than a plain
	                        -- kubb's (body.digGain): none (25 to 2026-11-16, with a plug ten times a
	                        -- plain dig's and no landing bump: every drill stopped within 2 cm of where
	                        -- it landed, flat and square to the throw)
	-- on the ground (world.launchDrill). A drill without planned spin is a plain kubb
	-- there: it bounces, tumbles and rolls on like any block of wood on grass. One
	-- with planned spin (2026-11-15, THE WALL) is a drilled kubb on the ground: it
	-- plugs a little and rolls sideways, face over face (body.lua: edgeRound,
	-- digBySpin, slipDrag, rollDrag, plugGain, bumpGain). Measured with
	-- tools/spinwall.lua against the per-tap targets
	rollSpin = 10,          -- rad/s of planned spin from which it is the rolling body (a tap is 22)
	spinDigGain = 5,        -- its first touches dig in this much harder than a plain kubb's (25 to
	                        -- 2026-11-16: it stopped dead; 1 and the plug no longer held the tumble,
	                        -- and the spin threw it a metre either way)
	edgeRound = 0.032,      -- m: its long edges roll on the turf as if rounded to this (of a 0.035 m
	                        -- half side): a sharp square keeps a quarter of its roll at each edge it
	                        -- tips onto and cannot roll past one face; the grass mat and worn edges
	                        -- make the section roll nearly round, and it still settles on a face
	rollDrag = 0.8,         -- share of the grass texture's drag that brushes its roll (viscous: the
	                        -- roll dies in proportion to its speed, so the distance grows ~ the spin)
	bumpGain = 1,           -- share of the texture's landing bump: all of it, as any piece (0 to
	                        -- 2026-11-16: the nose was held to plug, never glancing off a tilted patch)
	plugGain = 10,          -- how much harder the plug holds its tumble and turn (not its roll) than
	                        -- a plain dig: without it a low drill (loft 30) vaulted onto its nose
	                        -- and, spinning, fell any way
	-- when the drill is over (core/world: the body becomes a plain kubb, sharp edges and
	-- the grass's grip): at once when it strikes a piece (not a stake), else once it is
	-- on the ground and moving slower than both of these (Tyler's play test, 2026-11-15:
	-- a drill that hit a kubb rolled 16 turns, and drills rocked on their rounded edges
	-- for seconds; 0.2 m/s and 4 rad/s cost the spin rolls 0.1 m)
	settleV = 0.1,          -- m/s
	settleW = 2,            -- rad/s
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

-- The aim short of the marker that a clean drill at this loft (degrees)
-- runs on after it lands, on this ground (nil: grass): tune.slide by
-- tune.slideLofts (a lower, faster drill runs on farther), and by d, the
-- distance to the marker (m, nil: slideRefM), slidePerM a metre. With
-- planned spin (rad/s, nil: none) of rollSpin or more, spinSlide of the
-- loft's share alone (a spun drill plugs and rolls; how far it goes along the
-- throw hardly grows with the distance).
function drill.slideFor(loftDeg, surface, spin, d)
	local t = drill.tune
	local ground = t.slide[surface or "grass"] and surface or "grass"
	local v, L = t.slide[ground], t.slideLofts
	local k = (spin and (spin >= t.rollSpin or spin <= -t.rollSpin)) and t.spinSlide or 1
	local s = v[#v]
	if loftDeg <= L[1] then
		s = v[1]
	else
		for i = 2, #L do
			if loftDeg <= L[i] then s = lerp(v[i - 1], v[i], (loftDeg - L[i - 1]) / (L[i] - L[i - 1])); break end
		end
	end
	if d and k == 1 then s = s + t.slidePerM[ground] * (d - t.slideRefM) end
	return k * max(0, s)
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
	local R = max(0.5, d - drill.slideFor(loftDeg, surface, spin, d))
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
-- rollLand, spin, wobble, digGain (the arguments of world.launchDrill after
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
	-- positive spin about the forward long axis rolls the kubb to the right
	-- once it is down (the bottom face moves left), so A (+1) spins it positive
	return drill.body(r.smoothness or 1, pull, (cut or 0) * t.cutSpin, out)
end

-- The drilled kubb's body at release (world.launchDrill's arguments after
-- the line of flight): fills `out` with noseDown, rollLand, spin (rad/s about
-- the long axis, as given), wobble, digGain and jerk (0..1). smoothness is the
-- swing's (or the plan's effective smoothness: core/throwplan); under
-- cleanAbove the kubb wobbles nose over tail, up to wobbleRate at 0 and
-- never more. pull (+1 or -1) is the wobble's sign.
function drill.body(smoothness, pull, spin, out)
	local t = drill.tune
	local jerk = (t.cleanAbove - smoothness) / t.cleanAbove
	if jerk < 0 then jerk = 0 elseif jerk > 1 then jerk = 1 end
	out.noseDown, out.rollLand, out.spin = t.noseDownDeg, t.rollLandDeg, spin
	out.jerk = jerk
	out.wobble = pull * t.wobbleRate * jerk
	out.digGain = t.digGain
	return out
end


tw.drill = drill
