-- Drilling a kubb (DESIGN.md "Kubbs (drilling)"). Pure Lua: no playdate.*.
--
-- The aim is a landing marker on the ground in the far half. The thrower
-- stands on the baseline straight behind it (no walk step). The game solves
-- a launch that lands a clean drill on the marker: a low loft chosen by the
-- distance, and the speed that carries the kubb there. The crank swing is
-- then judged against that launch:
--   power      against a target band (the power the distance needs): in the
--              band the speed barely moves, outside it the kubb goes short or long
--   smoothness a clean flick keeps the nose down and the kubb dies near the
--              marker; a jerky one wobbles it and it runs on
--   tilt       pushes the line a little sideways (right when the swing
--              passed the release, left when it slowed into it)
--   cut        A or B held at release spins the kubb about its long axis, and
--              the ground turns that into a curve after landing
--
-- All in one frame: x across, y away from the thrower (the throw scene's view
-- frame). world.launchDrill (core/world) makes the body from drill.launch's
-- numbers.
import "core/tw"
import "core/flight"
import "core/swing"

local sqrt, sin, cos, atan, rad, deg, abs, min, max =
	math.sqrt, math.sin, math.cos, math.atan, math.rad, math.deg, math.abs, math.min, math.max

local drill = {}
local flight, swing = tw.flight, tw.swing

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
	slideAllow = 0.1,       -- m a clean drill moves on after its first touch (measured
	                        -- on grass: tests/lua/test_drill.lua); it is aimed this much short
	-- the body at release (world.launchDrill)
	noseDownDeg = 10,       -- the long axis this far below the horizontal: the nose leads
	rollLandDeg = 45,       -- roll about the long axis when it lands: on a long edge, so
	                        -- the cut always bites the same way (the release roll is
	                        -- solved backwards from the flight time and the spin)
	digGain = 3,            -- how much harder a drilled kubb's first touches dig in than a
	                        -- baton's (body.digGain); 1 lets a clean drill skid 1 to 4 m
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
	cutSpin = 25,           -- rad/s about the long axis with A or B held at release
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
-- thrower's baseline at lineY). Fills and returns `out`:
--   x          where the thrower stands on the baseline
--   swivel     radians, + = right
--   loft       degrees
--   dist       m from the thrower to the marker
--   speed      m/s of the clean launch
--   band       swing power that gives exactly that speed (band center)
--   T          s from release until the kubb's edge reaches the grass
function drill.solve(mx, my, lineY, out)
	local t = drill.tune
	out = out or {}
	local x = max(-t.throwerXMax, min(t.throwerXMax, mx))
	local dx, dy = mx - x, my - lineY
	local d = sqrt(dx * dx + dy * dy)
	local f = max(0, min(1, (d - t.markerNear) / (t.markerFar - t.markerNear)))
	local loft = lerp(t.loftNearDeg, t.loftFarDeg, f)
	local ft = flight.tune
	local h0 = ft.handHeight - t.landZ
	local e = rad(loft)
	local R = max(0.5, d - t.slideAllow)
	local v = speedFor(R, e, h0, ft.g)
	local vz = v * sin(e)
	out.x, out.swivel, out.loft, out.dist, out.speed = x, atan(dx, dy), loft, d, v
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

-- The launch for swing result `r` (power, smoothness, tilt, how) against the
-- solution `sol`, with cut drill.CUT_NONE / CUT_A / CUT_B. Fills and returns
-- `out`: swivel, loft, speed, noseDown, rollLand, spin, wobble, digGain (the
-- arguments of world.launchDrill after x and lineY), plus jerk (0..1).
function drill.launch(sol, r, cut, out)
	local t = drill.tune
	out = out or {}
	local e = drill.powerError(r.power or 0, sol.band)
	out.speed = sol.speed * max(t.speedMinFrac, 1 + t.speedPerPower * e)
	local push = rad(t.tiltPushDeg * (r.tilt or 0))
	-- the hand that let go before the bottom of the turn: "slowed" under the
	-- old release, a stop short of the bottom under the release at the stop
	local early = r.how == "slowed" or (r.how == "stopped" and (r.releaseAngle or 0) < 0)
	if early then push = -push end
	out.swivel = sol.swivel + push
	out.loft = sol.loft
	out.noseDown = t.noseDownDeg
	out.rollLand = t.rollLandDeg
	-- positive spin about the forward long axis curves the kubb to the left
	-- (measured: test_drill), so A (+1) spins it negative and curves right
	out.spin = -(cut or 0) * t.cutSpin
	local jerk = max(0, (t.cleanAbove - (r.smoothness or 1)) / t.cleanAbove)
	out.jerk = jerk
	local wob = t.wobbleRate * jerk
	if early then wob = -wob end
	out.wobble = wob
	out.digGain = t.digGain
	return out
end

-- The swing power that gives `speed` on the plain lob (swing.tune's linear
-- launch range): the autothrow and the readout use it.
function drill.powerForSpeed(speed)
	local st = swing.tune
	return (speed - st.launchMin) / (st.launchMax - st.launchMin)
end

tw.drill = drill
