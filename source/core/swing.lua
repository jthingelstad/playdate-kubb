-- The crank swing (DESIGN.md section 4, "The throw"). Pure Lua: no playdate.*.
--
-- Fed one crank sample per frame: the change in degrees since the last frame
-- (as playdate.getCrankChange returns it) and the frame time in seconds.
--
--   idle      -> crank back past windStartDeg      -> winding
--   winding   -> more back: the backswing grows (capped at backswingMaxDeg)
--             -> slow forward: lets the wind-up down; back at the start
--                angle = "letdown", no throw
--             -> forward faster than swingStartDps -> swinging
--   swinging  -> released when the forward swing passes the angle the wind-up
--                started from, or when forward speed falls below half its
--                peak -> "release", with swing.result filled in
--
-- Angles inside are "forward degrees": the raw crank change times
-- tune.forwardSign, so forward is positive and the wind-up is negative.
--
-- Crank sign. getCrankChange is negative anti-clockwise. Tried on hardware
-- (2026-11-13): with forwardSign = 1 the wind-up and the throw felt swapped,
-- so the forward swing is the anti-clockwise direction: forwardSign = -1.
-- It is the one constant to flip; nothing else changes.
import "core/tw"

local abs, min, max = math.abs, math.min, math.max

local swing = {}

swing.tune = {
	forwardSign = -1,       -- -1: anti-clockwise (negative getCrankChange) is the forward swing
	windStartDeg = 6,       -- back motion from idle needed before it counts as a wind-up
	backswingMaxDeg = 180,  -- the backswing stops growing here; more back motion is ignored
	fullBackswingDeg = 120, -- backswing that allows full power; less caps power at backswing / this
	swingStartDps = 200,    -- forward speed (deg/s) that starts the swing; slower forward lets the wind-up down
	fullSpeedDps = 1100,    -- forward speed (deg/s) at release that gives power 1
	speedWindow = 2,        -- frames averaged for "forward speed" (release test and release speed),
	                        -- so one slow sample in a jittery flick does not release it early
	releaseDropFrac = 0.5,  -- release when forward speed falls below this fraction of its peak (DESIGN 4)
	launchMin = 4.0,        -- m/s at power 0 (a mid-loft throw lands about 2 m out)
	launchMax = 9.2,        -- m/s at power 1 (a mid-loft throw lands about 8.9 m out)
	tumbleMin = 4.5,        -- rad/s at power 0
	tumbleMax = 7.0,        -- rad/s at power 1: about 1.2 turns over 8 m at mid loft
	roughFull = 1.0,        -- roughness (mean second difference of speed / mean speed) that gives
	                        -- smoothness 0; a steady or steadily accelerating flick is near 0
	tiltMaxDeg = 90,        -- tilt of the rotation plane at smoothness 0 (a full helicopter)
	legalTiltDeg = 30,      -- tilt at or under this is a legal end-over-end throw
	maxSamples = 512,       -- swing samples kept (about 10 s at 50 fps); later ones are dropped
}

function swing.new()
	return {
		phase = "idle",
		angle = 0,        -- forward degrees from where the wind-up started (negative = wound)
		pending = 0,      -- back motion seen while idle, before it counts as a wind-up
		backswing = 0,    -- degrees wound back at the start of the swing (or now, while winding)
		peak = 0,         -- peak forward speed of this swing, deg/s
		n = 0,            -- forward-swing speed samples
		speeds = {},      -- deg/s per frame of the forward swing (reused)
		lastSpeed = 0,    -- previous frame's forward speed
		result = {},      -- filled at release (reused)
	}
end

function swing.reset(s)
	s.phase, s.angle, s.pending, s.backswing, s.peak, s.n, s.lastSpeed = "idle", 0, 0, 0, 0, 0, 0
end

-- Power cap from the current (or swing-start) backswing, 0..1.
function swing.powerCap(s)
	return min(1, s.backswing / swing.tune.fullBackswingDeg)
end

-- Smoothness 0..1 of speeds[1..n]: one minus the mean absolute second
-- difference relative to the mean speed. A flick that speeds up evenly has
-- small second differences; alternating fast and slow frames have large ones.
-- With fewer than three samples there is no evidence of jerk: 1.
function swing.smoothness(speeds, n)
	if n < 3 then return 1 end
	local sum = 0
	for i = 1, n do sum = sum + speeds[i] end
	local mean = sum / n
	if mean <= 0 then return 0 end
	local r = 0
	for i = 2, n - 1 do
		r = r + abs(speeds[i] - 0.5 * (speeds[i - 1] + speeds[i + 1]))
	end
	r = r / (n - 2) / mean
	return max(0, min(1, 1 - r / swing.tune.roughFull))
end

local function windowSpeed(s, upto)
	local w = swing.tune.speedWindow
	local lo = max(1, upto - w + 1)
	local sum = 0
	for i = lo, upto do sum = sum + s.speeds[i] end
	return sum / (upto - lo + 1)
end

local function release(s, releaseSpeed, nUsed, how)
	local t = swing.tune
	local r = s.result
	local cap = swing.powerCap(s)
	local p = max(0, min(releaseSpeed / t.fullSpeedDps, cap, 1))
	local sm = swing.smoothness(s.speeds, nUsed)
	r.power = p
	r.powerCap = cap
	r.backswing = s.backswing
	r.releaseSpeed = releaseSpeed
	r.peakSpeed = s.peak
	r.frames = nUsed
	r.how = how
	r.launchSpeed = t.launchMin + (t.launchMax - t.launchMin) * p
	r.tumbleRate = t.tumbleMin + (t.tumbleMax - t.tumbleMin) * p
	r.smoothness = sm
	r.tilt = t.tiltMaxDeg * (1 - sm)
	r.legal = r.tilt <= t.legalTiltDeg
	s.phase, s.angle, s.pending, s.peak, s.n = "idle", 0, 0, 0, 0
	-- s.backswing is kept until the next wind-up so the HUD can show it
	return "release"
end

-- Feed one frame. Returns nil, "letdown" or "release" (then s.result holds
-- the throw).
function swing.update(s, delta, dt)
	local t = swing.tune
	if dt <= 0 then return nil end
	local fwd = delta * t.forwardSign
	local phase = s.phase

	if phase == "idle" then
		if fwd < 0 then
			s.pending = s.pending - fwd
			if s.pending >= t.windStartDeg then
				s.phase = "winding"
				s.angle = -min(s.pending, t.backswingMaxDeg)
				s.backswing = -s.angle
			end
		elseif fwd > 0 then
			s.pending = 0
		end
		return nil
	end

	if phase == "winding" then
		local speed = fwd / dt
		if fwd <= 0 then
			s.angle = max(s.angle + fwd, -t.backswingMaxDeg)
		elseif speed >= t.swingStartDps then
			s.phase = "swinging"
			s.backswing = -s.angle
			s.n, s.peak = 0, 0
			return swing.update(s, delta, dt)
		else
			s.angle = s.angle + fwd
			if s.angle >= 0 then
				s.phase, s.angle, s.pending, s.backswing = "idle", 0, 0, 0
				return "letdown"
			end
		end
		s.backswing = -s.angle
		return nil
	end

	-- swinging
	local speed = fwd / dt
	local n = s.n
	if n < t.maxSamples then
		n = n + 1
		s.speeds[n] = speed
		s.n = n
	end
	s.angle = s.angle + fwd
	local w = windowSpeed(s, n)
	if w > s.peak then s.peak = w end
	if s.angle >= 0 then
		return release(s, w, n, "passed")
	end
	if w < t.releaseDropFrac * s.peak then
		-- the hand let go in the frames before this one
		local used = max(1, n - 1)
		return release(s, windowSpeed(s, used), used, "slowed")
	end
	return nil
end

-- Run a recorded swing through a fresh state. `samples` is a flat array
-- {dt1, delta1, dt2, delta2, ...}. Returns the first event ("release" or
-- "letdown") and, for a release, the result table; or nil if the samples end
-- mid-swing.
function swing.replay(samples)
	local s = swing.new()
	for i = 1, #samples - 1, 2 do
		local ev = swing.update(s, samples[i + 1], samples[i])
		if ev then return ev, (ev == "release") and s.result or nil end
	end
	return nil
end

tw.swing = swing
