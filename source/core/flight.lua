-- Baton flight for stage 1: a plain ballistic arc with tumble, no collisions.
-- Pure Lua: no playdate.*.
--
-- The baton leaves the hand at (x, lineY, handHeight), heading along the
-- swivel (0 = straight downfield, positive = toward +x) at the loft angle
-- above the horizontal. Gravity only. It turns end over end at the tumble
-- rate; the plane it turns in is tilted about the line of flight by the
-- swing's tilt (0 = clean end over end, 90 = a flat helicopter) and wobbles
-- around that tilt. It stops dead the moment its center reaches the ground
-- and lies flat there (stage 2 replaces all of this with the rigid body).
import "core/tw"

local sqrt, sin, cos, rad, abs, min, max = math.sqrt, math.sin, math.cos, math.rad, math.abs, math.min, math.max

local flight = {}

flight.tune = {
	g = 9.81,              -- m/s^2
	handHeight = 0.6,      -- m; release height at the throwing line
	batonLength = 0.30,    -- m (DESIGN 2)
	batonRadius = 0.022,   -- m (4.4 cm diameter)
	loftMinDeg = 5,        -- d-pad down limit: a low, hard throw (Jamie, 2026-11-14: was 15)
	loftMaxDeg = 55,       -- d-pad up limit: a high arc
	loftStepDeg = 5,       -- one d-pad press
	loftDefaultDeg = 35,   -- mid loft
	boostBelowDeg = 35,    -- under this loft a throw is harder (flight.loftBoost): full
	                       -- power carries as far as it does at this loft
	startAngle = math.pi / 2, -- tumble angle at release: upright in the hand
	wobbleAmp = 0.25,      -- the plane's tilt swings by this fraction of the tilt ...
	wobblePerTurn = 0.6,   -- ... this many times per tumble turn
	maxStep = 1 / 120,     -- s; flight.step subdivides longer frames
}

-- Unit launch velocity direction.
local function launchDir(swivel, loftDeg)
	local e = rad(loftDeg)
	local ce = cos(e)
	return sin(swivel) * ce, cos(swivel) * ce, sin(e)
end

-- Time from a launch height z0 with upward speed vz until z = 0.
local function timeToGround(z0, vz, g)
	return (vz + sqrt(vz * vz + 2 * g * z0)) / g
end

-- Predicted landing point and flight time of the baton's center:
-- lx, ly, T. Exact for the arc flight.step follows.
function flight.predict(x, lineY, swivel, loftDeg, speed)
	local t = flight.tune
	local dx, dy, dz = launchDir(swivel, loftDeg)
	local T = timeToGround(t.handHeight, speed * dz, t.g)
	return x + speed * dx * T, lineY + speed * dy * T, T
end

-- The aim preview: where a full-power throw at this loft would land.
function flight.aimPreview(x, lineY, swivel, loftDeg, fullSpeed)
	local lx, ly = flight.predict(x, lineY, swivel, loftDeg, fullSpeed)
	return lx, ly
end

-- How much harder a baton is thrown at this loft (Jamie, 2026-11-14: a field
-- kubb near the baseline is hit low and hard, to roll it into others). Under
-- boostBelowDeg the launch speed is multiplied so that a throw carries as far
-- as the same power does at boostBelowDeg: full power (fullSpeed, the swing's
-- launchMax) lands as far at 10 degrees as at 35, flatter and faster. 1 at and
-- above boostBelowDeg. The speed that carries R from handHeight at loft e is
-- sqrt(g R^2 / (2 cos^2 e (R tan e + h))). The last answer is kept (the aim
-- preview asks every frame).
local lastLoft, lastFull, lastBoost = nil, nil, 1
function flight.loftBoost(loftDeg, fullSpeed)
	local t = flight.tune
	if loftDeg >= t.boostBelowDeg then return 1 end
	if loftDeg == lastLoft and fullSpeed == lastFull then return lastBoost end
	local _, R = flight.predict(0, 0, 0, t.boostBelowDeg, fullSpeed)
	local h = t.handHeight
	local function need(e)
		local c = cos(e)
		return sqrt(t.g * R * R / (2 * c * c * (R * math.tan(e) + h)))
	end
	lastLoft, lastFull = loftDeg, fullSpeed
	lastBoost = max(1, need(rad(loftDeg)) / need(rad(t.boostBelowDeg)))
	return lastBoost
end

function flight.new()
	return {
		x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0,
		t = 0, T = 0,         -- time since release, predicted flight time
		phi = 0, rate = 0,    -- tumble angle (rad) and rate (rad/s)
		tilt = 0,             -- rotation plane tilt, radians
		dx = 0, dy = 1,       -- horizontal line of flight (unit)
		ox = 0, oy = 0,       -- launch point (ground)
		lx = 0, ly = 0,       -- predicted landing point
		landed = false,
		restAx = 1, restAy = 0, -- axis when lying on the ground
	}
end

-- Start a throw. tiltDeg comes from the swing (0 = clean).
function flight.launch(fl, x, lineY, swivel, loftDeg, speed, tumbleRate, tiltDeg)
	local t = flight.tune
	local dx, dy, dz = launchDir(swivel, loftDeg)
	fl.x, fl.y, fl.z = x, lineY, t.handHeight
	fl.vx, fl.vy, fl.vz = speed * dx, speed * dy, speed * dz
	fl.ox, fl.oy = x, lineY
	fl.dx, fl.dy = sin(swivel), cos(swivel)
	fl.t, fl.phi, fl.rate, fl.tilt = 0, t.startAngle, tumbleRate, rad(tiltDeg or 0)
	fl.lx, fl.ly, fl.T = flight.predict(x, lineY, swivel, loftDeg, speed)
	fl.landed = false
	return fl
end

-- Current tilt of the rotation plane, with its wobble.
function flight.planeTilt(fl)
	local t = flight.tune
	local turns = (t.startAngle - fl.phi) / (2 * math.pi)
	return fl.tilt * (1 + t.wobbleAmp * sin(2 * math.pi * t.wobblePerTurn * turns))
end

-- Unit baton axis: ax, ay, az. In flight it turns in the plane spanned by
-- the line of flight d and the "up" of the plane u, where u is z rotated
-- about d by the plane tilt (so a 90 degree tilt is a flat helicopter).
-- The top end tips forward: phi falls from pi/2 (upright) through 0 (along d).
function flight.axis(fl)
	if fl.landed then return fl.restAx, fl.restAy, 0 end
	local tau = flight.planeTilt(fl)
	local dx, dy = fl.dx, fl.dy
	local rx, ry = dy, -dx               -- right of the line of flight
	local ct, st = cos(tau), sin(tau)
	local ux, uy, uz = rx * st, ry * st, ct
	local cp, sp = cos(fl.phi), sin(fl.phi)
	return dx * cp + ux * sp, dy * cp + uy * sp, uz * sp
end

local function settle(fl)
	local ax, ay = flight.axis(fl)
	local n = sqrt(ax * ax + ay * ay)
	if n < 1e-3 then ax, ay, n = fl.dx, fl.dy, 1 end
	fl.restAx, fl.restAy = ax / n, ay / n
	fl.landed = true
	fl.z = 0
	fl.vx, fl.vy, fl.vz = 0, 0, 0
end

-- Advance by dt seconds. Exact for constant gravity; the step that reaches
-- the ground is cut at the contact instant. Returns true on the step that lands.
function flight.step(fl, dt)
	if fl.landed then return false end
	local g = flight.tune.g
	local maxStep = flight.tune.maxStep
	while dt > 0 do
		local h = min(dt, maxStep)
		dt = dt - h
		local z1 = fl.z + fl.vz * h - 0.5 * g * h * h
		if z1 <= 0 then
			-- the root of z + vz*s - g/2 s^2 = 0 in (0, h]
			local s = timeToGround(fl.z, fl.vz, g)
			if s > h then s = h end
			fl.x = fl.x + fl.vx * s
			fl.y = fl.y + fl.vy * s
			fl.t = fl.t + s
			fl.phi = fl.phi - fl.rate * s
			settle(fl)
			return true
		end
		fl.x = fl.x + fl.vx * h
		fl.y = fl.y + fl.vy * h
		fl.z = z1
		fl.vz = fl.vz - g * h
		fl.t = fl.t + h
		fl.phi = fl.phi - fl.rate * h
	end
	return false
end

-- Horizontal distance from the launch point.
function flight.distance(fl)
	local ex, ey = fl.x - fl.ox, fl.y - fl.oy
	return sqrt(ex * ex + ey * ey)
end

-- Fraction of the predicted flight done, 0..1 (for the follow camera).
function flight.progress(fl)
	if fl.landed or fl.T <= 0 then return 1 end
	return max(0, min(1, fl.t / fl.T))
end

-- Whole tumble turns so far.
function flight.turns(fl)
	return abs(flight.tune.startAngle - fl.phi) / (2 * math.pi)
end

tw.flight = flight
