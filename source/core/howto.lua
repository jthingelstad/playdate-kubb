-- HOW TO THROW, the walkthrough (Jamie, 2026-11-14: "it is static. Without
-- being a real tool that uses the crank to show you each step it is not
-- useful ... an interactive thing that walks the player through the
-- different steps and meaning of the crank for the throw"). Pure: no
-- playdate.*; render/howto draws it, the throw scene runs it over itself.
--
-- The player's own crank runs the game's own swing (core/swing), armed at
-- the bottom of the turn as a throw is, and each throw is shown from the side:
-- the angle it left at (where the crank stopped against the notch,
-- swing.releaseLoft) and how far it carried, against a kubb 8 m out.
--
--   steps   "wind"   wind back to the back notch (full power)
--           "throw"  flick and stop on the front notch, until one throw is
--                    on the notch (EARLY / LATE say which way to correct)
--           "notch"  hold A and turn the crank: the notch (the loft) moves
--           "done"   A to play
--   B leaves at any step.
--
--   howto.new(loftDeg)          a walkthrough at that loft
--   howto.update(h, p, dt)      one frame of an input provider; "close" when it ends
--   howto.flight(loftDeg, speed)  carry (m) and flight time (s) from the hand
import "core/tw"
import "core/swing"
import "core/flight"

local swing, flight = tw.swing, tw.flight
local sin, cos, rad, sqrt, max, min, floor = math.sin, math.cos, math.rad, math.sqrt, math.max, math.min, math.floor

local howto = {}

howto.tune = {
	notchMoveDeg = 10,   -- degrees the notch must move in step 3
	kubbAt = 8,          -- m: the kubb the side view throws at
	loftGear = 0.15,     -- degrees of loft per degree of crank with A held (scenes/throw's loftGear)
}

function howto.new(loftDeg)
	return {
		step = "wind",
		loft = loftDeg,
		loft0 = loftDeg,     -- the loft at the start of step 3
		sw = swing.new(),
		arm = nil,           -- the crank as the throwing arm (swing.armAngle)
		armed = false,
		last = nil,          -- the last throw: { power, angle, launch, speed, carry, miss }
		note = nil,          -- "letdown" after a wind-up let down
		throws = 0,
	}
end

-- Where a baton thrown from the hand at `loftDeg` and `speed` first touches
-- the ground: the carry (m) and the flight time (s).
function howto.flight(loftDeg, speed)
	local t = flight.tune
	local e = rad(loftDeg)
	local vz, vx = speed * sin(e), speed * cos(e)
	local T = (vz + sqrt(vz * vz + 2 * t.g * t.handHeight)) / t.g
	return vx * T, T
end

-- The full-power throw at the loft set (the dashed arc: what the notch aims).
function howto.aimSpeed(loftDeg)
	local st = swing.tune
	return st.launchMax * flight.loftBoost(loftDeg, st.launchMax)
end

local function thrown(h, r)
	local st = swing.tune
	local launch = swing.releaseLoft(h.loft, r.releaseAngle)
	local speed = r.launchSpeed * flight.loftBoost(h.loft, st.launchMax)
	local carry = howto.flight(launch, speed)
	h.last = {
		power = r.power, angle = r.releaseAngle, launch = launch, speed = speed,
		carry = carry, miss = swing.releaseMiss(h.loft, r.releaseAngle), legal = r.legal,
	}
	h.throws = h.throws + 1
	if h.step == "throw" and h.last.miss == 0 then
		h.step = "notch"
		h.loft0 = h.loft
	end
end

-- One frame. p: an input provider (input.lua), already advanced this frame.
function howto.update(h, p, dt)
	if p:pressed("b") then return "close" end
	if h.step == "done" and p:pressed("a") then return "close" end
	local delta = p:crank()
	local arm = swing.armAngle(p:crankPos())
	local prevArm = h.arm
	h.arm = arm
	local sw = h.sw
	-- hold A: the crank moves the notch (the loft), as when aiming
	if p:held("a") then
		local ft = flight.tune
		h.loft = max(ft.loftMinDeg, min(ft.loftMaxDeg, h.loft + delta * swing.tune.forwardSign * howto.tune.loftGear))
		if sw.phase ~= "idle" then swing.reset(sw) end
		h.armed = false
		if h.step == "notch" and math.abs(h.loft - h.loft0) >= howto.tune.notchMoveDeg then h.step = "done" end
		return nil
	end
	-- the crank throws: armed when it crosses the bottom of the turn going
	-- back (as scenes/throw's swingInput)
	if sw.phase == "idle" then
		if not h.armed then
			if swing.crossedBack(prevArm, arm) then
				h.armed = true
				delta = arm * swing.tune.forwardSign
			else
				delta = 0
			end
		elseif arm >= 0 then
			h.armed = false
			sw.pending = 0
			delta = 0
		end
	end
	local ev = swing.update(sw, delta, dt)
	if ev then h.armed = false end
	if sw.phase == "winding" then h.note = nil end
	if h.step == "wind" and sw.phase ~= "idle" and swing.powerCap(sw) >= 1 then h.step = "throw" end
	if ev == "letdown" then
		h.note = "letdown"
	elseif ev == "release" then
		h.note = nil
		thrown(h, sw.result)
		if h.step == "wind" then h.step = "throw" end
	end
	return nil
end

-- What the walkthrough says now: the step's title and two lines, and a
-- line on the last throw (nil before one). Strings only; render/howto draws.
local TEXT = {
	wind = { "1  WIND BACK", "TURN THE CRANK BACK PAST THE BOTTOM", "TO THE BACK NOTCH: THAT IS FULL POWER." },
	throw = { "2  FLICK, THEN STOP", "FLICK THE CRANK FORWARD HARD AND STOP IT", "ON THE FRONT NOTCH: THAT IS THE ANGLE." },
	notch = { "3  MOVE THE NOTCH", "HOLD A AND TURN THE CRANK: THE NOTCH", "MOVES, AND THE THROW GOES HIGHER OR LOWER." },
	done = { "THAT IS THE THROW", "BACK FOR POWER, STOP ON THE NOTCH FOR THE", "ANGLE: BATONS AND KUBBS ALIKE. A: PLAY" },
}
howto.TEXT = TEXT

function howto.lines(h)
	local t = TEXT[h.step]
	local say = nil
	local l = h.last
	if h.note == "letdown" then
		say = "TOO SLOW: THAT LETS THE WIND-UP DOWN. FLICK!"
	elseif l then
		local verdict = (l.miss == 0 and "ON THE NOTCH") or (l.miss < 0 and "EARLY: LOW") or "LATE: HIGH"
		say = string.format("%s   ANGLE %d   %.1f M", verdict, floor(l.launch + 0.5), max(0, l.carry))
	end
	return t[1], t[2], t[3], say
end

tw.howto = howto
