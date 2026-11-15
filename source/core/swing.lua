-- The crank swing (DESIGN.md section 4, "The throw"). Pure Lua: no playdate.*.
--
-- Fed one crank sample per frame: the change in degrees since the last frame
-- (as playdate.getCrankChange returns it) and the frame time in seconds.
--
--   idle      -> crank back past windStartDeg      -> winding
--                (the throw scene only feeds the crank while idle once it
--                has crossed the bottom of the turn going back: armAngle,
--                crossedBack)
--   winding   -> more back: the backswing grows (capped at backswingMaxDeg)
--             -> slow forward: lets the wind-up down; back at the start
--                angle = "letdown", no throw
--             -> forward faster than swingStartDps -> swinging
--   swinging  -> released where the crank stops (Jamie and Tyler, 2026-11-14:
--                "you stop the crank where you release the baton"): when the
--                forward speed falls below releaseStopDps, the crank all but
--                halted -> "release", with swing.result filled in. (It was
--                half the flick's peak: on the device that fired while the
--                hand was still turning the crank at 300 deg/s, or well after
--                the stop Jamie meant; 13 swings of 2026-11-14 left from -27
--                to 137 degrees against a 25 to 35 target.) The crank is the throwing arm, and a
--                hand swung on an arm leaves at right angles to it, so the
--                arm's angle past the bottom of the turn at the stop is the
--                launch angle (result.releaseAngle; the throw scene turns it
--                into the loft, swing.releaseLoft): within releaseTolDeg of
--                the notch (the loft set) is perfect; beyond it, stop early
--                and the baton goes lower, late and it goes higher, by
--                releaseGain of the miss (Jamie, 2026-11-14: a forgiving
--                notch; the crank moves 20 to 30 degrees a frame in a flick,
--                so a degree for a degree threw batons into the ground). The power is the
--                flick's peak speed. A swing that never stops is released at
--                releaseMaxDeg. (Before 2026-11-14 the baton was released as
--                the arm passed the bottom, at the loft set by hand; a state
--                with passRelease keeps that, for traces recorded then.)
--
-- The tempo rule (s.tempo, Jamie and Tyler, 2026-11-14, after a play test of
-- the stop: "far too difficult to throw with any control"; the old release
-- before it was too easy, every full-power flick hit the baseline): released
-- as the arm passes the bottom (the old release: "passed" or "slowed"), but
-- the wind-up picks the distance (power = backswing / fullBackswingDeg) and
-- the flick only has to match a steady tempo. Its release speed against
-- tempoDps moves the launch speed by tempoGain m/s per 100 deg/s (more,
-- tempoFarGain, beyond tempoKneeDps): too fast goes long, too slow short.
-- The gain is the difficulty (swing.presets). Replaying 226 recorded swings
-- against a baseline kubb with real physics, each against the player's own
-- usual speed: gain 0.05 hit 81%, 0.10 64%, 0.15 44%, 0.20 35%. The flick's
-- timing (where its speed peaked, against the release) is recorded, not used.
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
	releaseDropFrac = 0.5,  -- the old release (passRelease): let go early when the speed falls below
	                        -- this fraction of its peak ("slowed")
	releaseStopDps = 150,   -- release when the forward speed (speedWindow frames) falls below this: the
	                        -- crank has all but stopped (3 degrees a 20 ms frame)
	releaseMaxDeg = 150,    -- forward degrees past the bottom: a swing that has not stopped by here
	                        -- is released (straight up and over)
	releaseTolDeg = 10,     -- a stop within this of the notch (the loft set) launches at the loft set
	releaseGain = 1 / 3,    -- beyond it, this much of the rest of the miss goes into the launch angle
	releaseLoftMin = -30,   -- degrees: the launch angle's range (below 0 the baton is thrown down)
	releaseLoftMax = 85,
	-- the tempo rule (s.tempo, above)
	tempoDps = 850,         -- the flick's target release speed: the median of 226 recorded flicks
	tempoGain = 0.10,       -- m/s of launch speed per 100 deg/s off tempo (swing.presets)
	tempoKneeDps = 400,     -- beyond this far off tempo ...
	tempoFarGain = 0.47,    -- ... each 100 deg/s more costs this (the old slope: a lazy flick is short)
	tempoOnMps = 0.15,      -- launch speed error shown as ON TEMPO (the baseline window is about +-0.18)
	launchFloor = 1.5,      -- m/s: the slowest a tempo-rule throw leaves the hand
	launchMin = 4.0,        -- m/s at power 0 (a mid-loft throw lands about 2 m out)
	launchMax = 9.2,        -- m/s at power 1 (a mid-loft throw lands about 8.9 m out)
	tumbleMin = 4.5,        -- rad/s at power 0
	tumbleMax = 7.0,        -- rad/s at power 1: about 1.2 turns over 8 m at mid loft
	roughFull = 3.0,        -- roughness (mean second difference of speed / mean speed) that gives
	                        -- smoothness 0. Hardware traces (2026-11-13): a flick is only 4 to 7
	                        -- frames at about 41 ms each and honest flicks measure up to 0.67
	                        -- from sampling jitter alone, so only a clearly stuttered swing
	                        -- (roughness over 1.0) is a helicopter
	tiltMaxDeg = 90,        -- tilt of the rotation plane at smoothness 0 (a full helicopter)
	legalTiltDeg = 30,      -- tilt at or under this is a legal end-over-end throw
	maxSamples = 512,       -- swing samples kept (about 10 s at 50 fps); later ones are dropped
}

-- The difficulty of the tempo rule: tempoGain for each System Menu "Swing"
-- choice ("stop" is the release where the crank stops, kept to compare).
-- Hit rates from the replay above (the player's own usual speed; a fixed
-- tempo adds what the player has not yet learned of it).
swing.presets = { easy = 0.05, mid = 0.10, hard = 0.20 }
swing.PRESETS = { "easy", "mid", "hard", "stop" }

-- Set the rule: a preset name from swing.PRESETS.
function swing.setPreset(name)
	local t = swing.tune
	if swing.presets[name] then
		t.rule, t.tempoGain = "tempo", swing.presets[name]
	else
		t.rule = "stop"
	end
end
swing.tune.rule = "tempo"   -- "tempo" or "stop": what the throw scene gives a new swing

-- Does this swing release where the crank stops (the notch rule)?
function swing.stops(s)
	return not s.passRelease and not s.tempo
end

-- Launch speed added by a release at `releaseSpeed` deg/s (the tempo rule).
function swing.tempoMps(releaseSpeed)
	local t = swing.tune
	local d = releaseSpeed - t.tempoDps
	local a = d < 0 and -d or d
	local v = t.tempoGain * min(a, t.tempoKneeDps) / 100
	if a > t.tempoKneeDps then v = v + t.tempoFarGain * (a - t.tempoKneeDps) / 100 end
	return d < 0 and -v or v
end

-- -1 slow (short), 0 on tempo, 1 fast (long): the flag after a throw.
function swing.tempoMiss(mps)
	local on = swing.tune.tempoOnMps
	if mps > on then return 1 elseif mps < -on then return -1 end
	return 0
end

function swing.new()
	return {
		phase = "idle",
		angle = 0,        -- forward degrees from where the wind-up started (negative = wound;
		                  -- held at -backswingMaxDeg while winding: the power's backswing)
		arm = 0,          -- the same, never held: where the crank really is (the release angle;
		                  -- Codex on #73: wound past the cap, `angle` no longer was)
		pending = 0,      -- back motion seen while idle, before it counts as a wind-up
		backswing = 0,    -- degrees wound back at the start of the swing (or now, while winding)
		peak = 0,         -- peak forward speed of this swing, deg/s
		n = 0,            -- forward-swing speed samples
		speeds = {},      -- deg/s per frame of the forward swing (reused)
		lastSpeed = 0,    -- previous frame's forward speed
		passRelease = false, -- true: the old release as the arm passes the bottom (old traces)
		tempo = false,    -- true: the tempo rule (above): the old release, the wind-up's distance
		peakArm = 0,      -- `arm` where the forward speed peaked (the flick's timing)
		result = {},      -- filled at release (reused)
	}
end

function swing.reset(s)
	s.phase, s.angle, s.pending, s.backswing, s.peak, s.n, s.lastSpeed = "idle", 0, 0, 0, 0, 0, 0
	s.arm, s.peakArm = 0, 0
end

-- Where the crank is, as the throwing arm: forward degrees from the bottom of
-- the turn, in (-180, 180]. `pos` is getCrankPosition (0 = straight up,
-- growing clockwise). Negative = on the wind-up side.
function swing.armAngle(pos)
	local a = ((pos - 180) * swing.tune.forwardSign) % 360
	if a > 180 then a = a - 360 end
	return a
end

-- The throw starts at the bottom of the turn: true when the arm went from
-- `prev` (at or ahead of the bottom) to `a` (behind it) in one frame. The
-- 90 degree limit keeps the jump across the top of the turn from counting.
function swing.crossedBack(prev, a)
	return prev ~= nil and prev >= 0 and a < 0 and (prev - a) < 90
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
	r.releaseAngle = s.arm     -- forward degrees past the bottom of the turn at the release
	r.timing = s.peakArm - s.arm   -- degrees before the release that the speed peaked
	r.rule, r.tempoDev, r.tempoMps, r.tempoPower, r.tempoGain = nil, nil, nil, nil, nil
	if s.tempo then
		-- the wind-up is the distance, the flick's tempo the error
		p = cap
		r.power = p
		local dv = swing.tempoMps(releaseSpeed)
		r.rule, r.tempoDev, r.tempoMps, r.tempoGain = "tempo", releaseSpeed - t.tempoDps, dv, t.tempoGain
		r.tempoPower = dv / (t.launchMax - t.launchMin)
	end
	r.launchSpeed = t.launchMin + (t.launchMax - t.launchMin) * p + (r.tempoMps or 0)
	if s.tempo and r.launchSpeed < t.launchFloor then r.launchSpeed = t.launchFloor end
	r.tumbleRate = t.tumbleMin + (t.tumbleMax - t.tumbleMin) * p
	r.smoothness = sm
	r.tilt = t.tiltMaxDeg * (1 - sm)
	r.legal = r.tilt <= t.legalTiltDeg
	s.phase, s.angle, s.pending, s.peak, s.n, s.arm, s.peakArm = "idle", 0, 0, 0, 0, 0, 0
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
				s.arm = -s.pending
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
			s.arm = s.arm + fwd
			s.angle = max(s.angle + fwd, -t.backswingMaxDeg)
		elseif speed >= t.swingStartDps then
			s.phase = "swinging"
			s.backswing = -s.angle
			s.n, s.peak = 0, 0
			return swing.update(s, delta, dt)
		else
			s.angle = s.angle + fwd
			s.arm = s.arm + fwd
			if s.angle >= 0 then
				s.phase, s.angle, s.pending, s.backswing, s.arm = "idle", 0, 0, 0, 0
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
	s.arm = s.arm + fwd
	local w = windowSpeed(s, n)
	if w > s.peak then s.peak, s.peakArm = w, s.arm end
	if s.passRelease or s.tempo then
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
	if w < t.releaseStopDps then
		-- stopped: released here, at the flick's speed (the frames since it
		-- slowed are not part of the throw)
		local used = n
		while used > 1 and s.speeds[used] < t.releaseStopDps do used = used - 1 end
		return release(s, s.peak, used, "stopped")
	end
	if s.arm >= t.releaseMaxDeg then
		return release(s, s.peak, n, "over")
	end
	return nil
end

-- The launch angle for a release at arm angle `releaseAngle` with the loft
-- set to `target` (degrees; releaseTolDeg, releaseGain, releaseLoftMin/Max).
function swing.releaseLoft(target, releaseAngle)
	local t = swing.tune
	local miss, tol = releaseAngle - target, t.releaseTolDeg
	if miss > tol then miss = miss - tol elseif miss < -tol then miss = miss + tol else miss = 0 end
	local a = target + t.releaseGain * miss
	if a < t.releaseLoftMin then return t.releaseLoftMin end
	if a > t.releaseLoftMax then return t.releaseLoftMax end
	return a
end

-- Where a stop at arm angle `releaseAngle` fell against the notch (the loft
-- set, `target`): 0 on it (within releaseTolDeg), -1 early (lower), 1 late
-- (higher). The throw scene's verdict flag after a throw.
function swing.releaseMiss(target, releaseAngle)
	local miss, tol = releaseAngle - target, swing.tune.releaseTolDeg
	if miss > tol then return 1 elseif miss < -tol then return -1 end
	return 0
end

-- Run a recorded swing through a fresh state. `samples` is a flat array
-- {dt1, delta1, dt2, delta2, ...}. Returns the first event ("release" or
-- "letdown") and, for a release, the result table; or nil if the samples end
-- mid-swing. passRelease: the old release at the bottom of the turn (traces
-- recorded before 2026-11-14). tempo: the tempo rule, at today's tune.
function swing.replay(samples, passRelease, tempo)
	local s = swing.new()
	s.passRelease = passRelease or false
	s.tempo = tempo or false
	for i = 1, #samples - 1, 2 do
		local ev = swing.update(s, samples[i + 1], samples[i])
		if ev then return ev, (ev == "release") and s.result or nil end
	end
	return nil
end

tw.swing = swing
