-- The physics world (DESIGN 5): 3D rigid bodies on a ground plane, fixed
-- step, impulse-based contacts with Coulomb friction and restitution.
-- Pure Lua: no playdate.*.
--
-- One step (world.step), after Box2D v3's soft-step order with one substep:
--   1. gravity and the gyroscopic term for awake bodies
--   2. contacts: body pairs first (an awake body moving into a sleeping one
--      wakes it), then the ground for every awake body
--   3. prepare the contacts and warm start the ground contacts from the
--      impulses of the step before
--   4. `iterations` sequential-impulse passes with a position bias (pushes
--      overlapping pieces apart, lets speculative contacts close their gap)
--   5. move and turn the bodies
--   6. `relaxIterations` passes without the push bias, so pushing apart
--      does not leave pieces with extra speed (no energy gain)
--   7. restitution, from each contact's approach speed before the solve
--   8. rolling resistance and dig, sleep, topple and touch bookkeeping
-- Tipping about an edge, rocking back and falling are all just contacts.
--
-- Surfaces are parameter sets (world.surfaces). "Dig": when a corner, edge
-- or baton end arrives steeply and fast, that contact loses its bounce, gets
-- extra friction for as long as it lasts (it is ploughed in), and the body
-- gets a rolling-resistance lever that fades over digTime (it is plugged).
--
-- Usage:
--   local w = world.new{ surface = "grass", pieces = { {id=, kind=, x=, y=, yaw=}, ... } }
--   world.launchBaton(w, x, lineY, swivel, loftDeg, speed, tumbleRate, tiltDeg)
--   while not world.isAtRest(w) do world.step(w) end
--   local r = world.result(w)
import "core/tw"
import "core/quat"
import "core/body"
import "core/collide"
import "core/flight"
import "core/pitch"

local quat, body, collide = tw.quat, tw.body, tw.collide
local sqrt, abs, min, max, sin, cos, rad, exp = math.sqrt, math.abs, math.min, math.max, math.sin, math.cos, math.rad, math.exp

local world = {}

world.tune = {
	dt = 1 / 240,          -- s, the fixed step (DESIGN 5)
	g = 9.81,              -- m/s^2
	iterations = 4,        -- velocity passes per step with the position bias (guess: enough for
	                       -- a kubb on its edge and three-kubb dominoes at 240 Hz)
	relaxIterations = 1,   -- passes without the bias
	slop = 0.0005,         -- m of overlap left alone (stops resting contacts flickering)
	pushRate = 0.2,        -- fraction of the overlap beyond slop removed per step
	maxPush = 0.5,         -- m/s cap on the push-apart speed
	margin = 0.002,        -- m; contacts are made this far before touching, plus the distance
	                       -- the pieces can close in one step (speculative contacts)
	restitutionSpeed = 0.4,-- m/s; slower impacts do not bounce
	restitutionIterations = 4, -- bounce passes (one pass over a flat landing's corners overshoots)
	pairMu = 0.4,          -- wood on wood friction (guess; dry wood 0.25 to 0.5)
	pairE = 0.35,          -- wood on wood bounce (guess)
	warm = 0.9,            -- fraction of last step's ground impulses applied up front
	gyro = true,           -- gyroscopic term (torque-free precession; implicit, stable)
	sleepLin = 0.03,       -- m/s: below this ...
	sleepAng = 0.3,        -- rad/s: ... and this ...
	sleepTime = 0.25,      -- s: ... for this long while touching something: the body sleeps
	wakeLin = 0.05,        -- m/s: a touching awake body moving faster than this (or turning
	wakeAng = 0.5,         -- faster than this, rad/s) wakes a sleeping one
	toppleDeg = 5,         -- toppled: the long axis came within this of parallel to the ground
	pitchHalfWidth = 2.5,  -- m (DESIGN 2)
	pitchLength = 8,
	outMargin = 0.04,      -- m beyond a pitch line before a center counts as out (base kubbs
	                       -- stand centered on the baselines)
	maxTime = 12,          -- s; a throw is called at rest after this long regardless
	stakeHeight = 0.30,    -- m above the ground; stakes are fixed posts of radius pitch.stakeRadius
}

-- Ground surfaces: one parameter set each (DESIGN 5). All guesses, to be
-- tuned on hardware in stages 2 and 4.
--   mu          Coulomb friction, wood on the ground
--   e           restitution (bounce)
--   dig         how strongly a steep, fast arrival digs in (0 = never). The
--               dig amount of a new contact is dig * steepness * ramp, where
--               steepness = approach speed / contact speed (1 = straight in)
--               and ramp goes 0 -> 1 between digSpeed and digSpeed + digRamp
--   digSpeed, digRamp  m/s
--   digLever    m; rolling resistance lever (per unit dig) a dug-in body gets
--   digTime     s; how fast that lever fades
--   roll        m; rolling resistance lever for the round baton at all times
world.surfaces = {
	grass = {
		name = "grass", mu = 0.7, e = 0.15,
		dig = 1.0, digSpeed = 0.3, digRamp = 1.5, digLever = 0.006, digTime = 0.15,
		roll = 0.01,
	},
	sand = {
		name = "sand", mu = 0.9, e = 0.03,
		dig = 3.0, digSpeed = 0.2, digRamp = 1.0, digLever = 0.03, digTime = 0.5,
		roll = 0.03,
	},
	-- ICE (stage 7, not built): very low friction for the Minnesota slide,
	-- something like mu = 0.05, e = 0.1, dig = 0, roll = 0.0005. Add it
	-- here as a third parameter set; nothing else should need to change.
}

-- ---------------------------------------------------------------------------
-- Building a world

function world.new(opts)
	opts = opts or {}
	local surf = opts.surface or "grass"
	if type(surf) == "string" then surf = assert(world.surfaces[surf], "unknown surface " .. surf) end
	local w = {
		bodies = {}, n = 0, byId = {},
		surface = surf,
		time = 0, steps = 0,
		projectile = nil,
		firstContact = nil,   -- the projectile's first contact: {t, x, y, z, with}
		firstHit = nil,       -- its first contact with another body: same fields
		contacts = 0,         -- contacts in the last step (for the bench)
		awakeCount = 0,       -- awake bodies in the last step
	}
	if opts.stakes ~= false then world.addStakes(w) end
	for _, p in ipairs(opts.pieces or {}) do world.addPiece(w, p) end
	return w
end

-- The six pitch stakes (core/pitch) as static posts, ids stake1 .. stake6.
-- They never move or wake; anything touching one marks it touched.
function world.addStakes(w)
	local h, r = world.tune.stakeHeight, tw.pitch.stakeRadius
	for i, s in ipairs(tw.pitch.stakes) do
		local b = world.addBody(w, "stake", "stake" .. i)
		b.r = r
		b.hl = h / 2 - r
		b.radius = h / 2
		body.setPose(b, s.x, s.y, h / 2, 1, 0, 0, 0)
		b.awake = false
	end
end

function world.addBody(w, kind, id)
	local b = body.new(kind, id)
	w.n = w.n + 1
	b.index = w.n
	w.bodies[w.n] = b
	w.byId[b.id] = b
	return b
end

-- Add a piece at rest on the ground. p = { id, kind, x, y, yaw } stands a
-- kubb or king up (a baton lies along yaw); or give a full pose
-- p.qw, p.qx, p.qy, p.qz (z is then chosen so it rests on the ground unless
-- p.z is given). Pieces start asleep.
function world.addPiece(w, p)
	local b = world.addBody(w, p.kind, p.id)
	local qw, qx, qy, qz = p.qw, p.qx, p.qy, p.qz
	if not qw then
		qw, qx, qy, qz = quat.fromAxisAngle(0, 0, 1, p.yaw or 0)
		if p.kind == "baton" then
			-- lie down: local z (the segment) along the yaw direction
			local tw_, tx, ty, tz = quat.fromAxisAngle(1, 0, 0, -math.pi / 2)
			qw, qx, qy, qz = quat.mul(qw, qx, qy, qz, tw_, tx, ty, tz)
		end
	end
	body.setPose(b, p.x or 0, p.y or 0, 0, qw, qx, qy, qz)
	if p.z then
		b.z = p.z
	else
		b.z = -body.lowestZ(b)
	end
	b.awake = false
	-- a piece that is already down (from an earlier throw) stays toppled
	b.toppled = p.toppled or (b.shape == 1 and body.lying(b, sin(rad(world.tune.toppleDeg))))
	b.wasToppled = b.toppled
	return b
end

local function wake(b)
	if not b.awake and not b.static then
		b.awake = true
		b.everAwake = true
		b.sleepTime = 0
	end
end
world.wake = wake

-- Launch a projectile body (baton or kubb) with a full pose and velocity.
-- Angular velocity is in the world frame.
function world.launch(w, kind, id, x, y, z, qw, qx, qy, qz, vx, vy, vz, wx, wy, wz)
	local b = world.addBody(w, kind, id)
	body.setPose(b, x, y, z, qw, qx, qy, qz)
	body.setVelocity(b, vx, vy, vz, wx, wy, wz)
	wake(b)
	b.touched = true
	w.projectile = b
	return b
end

-- Unit horizontal direction of the swivel and the launch direction at the
-- loft (the same conventions as core/flight).
local function launchDir(swivel, loftDeg)
	local e = rad(loftDeg)
	local ce = cos(e)
	return sin(swivel) * ce, cos(swivel) * ce, sin(e)
end

-- The baton launch from stage 1's swing outputs: it leaves the hand at
-- (x, lineY, flight.tune.handHeight) heading along the swivel at the loft,
-- held upright, turning end over end at tumbleRate (rad/s) with the top end
-- tipping forward. tiltDeg tilts the plane it turns in about the line of
-- flight (0 = clean end over end, 90 = a flat helicopter): the angular
-- velocity is about the tilted axis, so a helicopter really spins flat.
-- Returns the pose and velocities as 13 numbers.
function world.batonLaunchState(x, lineY, swivel, loftDeg, speed, tumbleRate, tiltDeg)
	local dx, dy = sin(swivel), cos(swivel)
	local lx, ly, lz = launchDir(swivel, loftDeg)
	local tau = rad(tiltDeg or 0)
	-- u: "up" of the turning plane, z turned about d toward the right by tau
	local rx, ry = dy, -dx
	local st, ct = sin(tau), cos(tau)
	local ux, uy, uz = rx * st, ry * st, ct
	-- k = d x u, the axis the baton turns about
	local kx, ky, kz = dy * uz, -dx * uz, dx * uy - dy * ux
	local kn = sqrt(kx * kx + ky * ky + kz * kz)
	kx, ky, kz = kx / kn, ky / kn, kz / kn
	-- local axes: x = k, y = d, z = u (the baton starts along u)
	local qw, qx, qy, qz = quat.fromAxes(kx, ky, kz, dx, dy, 0, ux, uy, uz)
	local h = tw.flight.tune.handHeight
	return x, lineY, h, qw, qx, qy, qz,
		speed * lx, speed * ly, speed * lz,
		-tumbleRate * kx, -tumbleRate * ky, -tumbleRate * kz
end

function world.launchBaton(w, x, lineY, swivel, loftDeg, speed, tumbleRate, tiltDeg, id)
	return world.launch(w, "baton", id or "baton",
		world.batonLaunchState(x, lineY, swivel, loftDeg, speed, tumbleRate, tiltDeg))
end

-- ---------------------------------------------------------------------------
-- The solver's contact arrays (reused every step; no tables per contact)

local C = collide.C
local cA, cB, cSlot = C.A, C.B, C.slot
local cPx, cPy, cPz, cNx, cNy, cNz, cSep = C.px, C.py, C.pz, C.nx, C.ny, C.nz, C.sep

local SA, SB = {}, {}             -- dynamic bodies (SB false = ground or a sleeping body)
local T1x, T1y, T1z, T2x, T2y, T2z = {}, {}, {}, {}, {}, {}
-- A's angular terms: (ra x d) and I^-1 (ra x d) for d = n, t1, t2
local AnX, AnY, AnZ, WAnX, WAnY, WAnZ = {}, {}, {}, {}, {}, {}
local A1X, A1Y, A1Z, WA1X, WA1Y, WA1Z = {}, {}, {}, {}, {}, {}
local A2X, A2Y, A2Z, WA2X, WA2Y, WA2Z = {}, {}, {}, {}, {}, {}
local BnX, BnY, BnZ, WBnX, WBnY, WBnZ = {}, {}, {}, {}, {}, {}
local B1X, B1Y, B1Z, WB1X, WB1Y, WB1Z = {}, {}, {}, {}, {}, {}
local B2X, B2Y, B2Z, WB2X, WB2Y, WB2Z = {}, {}, {}, {}, {}, {}
local MN, MT1, MT2 = {}, {}, {}   -- effective masses
local BIAS, RELAX = {}, {}        -- velocity targets with and without the push
local V0, MU, E = {}, {}, {}
local LN, LT1, LT2 = {}, {}, {}   -- accumulated impulses
local LNMAX = {}                  -- largest normal impulse seen (restitution needs > 0)
local ACTIVE = {}

-- Fill the angular terms of one direction for body b at arm (rx, ry, rz).
-- Returns jx, jy, jz (r x d), wx, wy, wz (I^-1 (r x d)), and (r x d).I^-1(r x d).
local function angular(b, rx, ry, rz, dx, dy, dz)
	local jx, jy, jz = ry * dz - rz * dy, rz * dx - rx * dz, rx * dy - ry * dx
	local wx = b.i11 * jx + b.i12 * jy + b.i13 * jz
	local wy = b.i12 * jx + b.i22 * jy + b.i23 * jz
	local wz = b.i13 * jx + b.i23 * jy + b.i33 * jz
	return jx, jy, jz, wx, wy, wz, jx * wx + jy * wy + jz * wz
end

-- Implicit gyroscopic step (Bullet's computeGyroscopicImpulseImplicit_Body):
-- one Newton step of I w' = I w - dt w' x I w' in the body frame. Keeps a
-- spinning baton or kubb precessing correctly without blowing up.
local function gyro(b, dt)
	local r11, r12, r13, r21, r22, r23, r31, r32, r33 =
		b.r11, b.r12, b.r13, b.r21, b.r22, b.r23, b.r31, b.r32, b.r33
	local wx, wy, wz = b.wx, b.wy, b.wz
	-- body frame
	local ox = r11 * wx + r21 * wy + r31 * wz
	local oy = r12 * wx + r22 * wy + r32 * wz
	local oz = r13 * wx + r23 * wy + r33 * wz
	local Ix, Iy, Iz = b.Ix, b.Iy, b.Iz
	local ix, iy, iz = Ix * ox, Iy * oy, Iz * oz
	-- f = dt * (o x I o)
	local fx = dt * (oy * iz - oz * iy)
	local fy = dt * (oz * ix - ox * iz)
	local fz = dt * (ox * iy - oy * ix)
	if fx * fx + fy * fy + fz * fz < 1e-20 then return end
	-- J = I + dt (skew(o) I - skew(I o))
	local a11 = Ix
	local a12 = dt * (-oz * Iy + iz)
	local a13 = dt * (oy * Iz - iy)
	local a21 = dt * (oz * Ix - iz)
	local a22 = Iy
	local a23 = dt * (-ox * Iz + ix)
	local a31 = dt * (-oy * Ix + iy)
	local a32 = dt * (ox * Iy - ix)
	local a33 = Iz
	-- solve J d = f (Cramer)
	local c11 = a22 * a33 - a23 * a32
	local c12 = a23 * a31 - a21 * a33
	local c13 = a21 * a32 - a22 * a31
	local det = a11 * c11 + a12 * c12 + a13 * c13
	if abs(det) < 1e-30 then return end
	local inv = 1 / det
	local dx = (c11 * fx + (a13 * a32 - a12 * a33) * fy + (a12 * a23 - a13 * a22) * fz) * inv
	local dy = (c12 * fx + (a11 * a33 - a13 * a31) * fy + (a13 * a21 - a11 * a23) * fz) * inv
	local dz = (c13 * fx + (a12 * a31 - a11 * a32) * fy + (a11 * a22 - a12 * a21) * fz) * inv
	ox, oy, oz = ox - dx, oy - dy, oz - dz
	b.wx = r11 * ox + r12 * oy + r13 * oz
	b.wy = r21 * ox + r22 * oy + r23 * oz
	b.wz = r31 * ox + r32 * oy + r33 * oz
end

-- How pointed the body meets the ground, 0..1. A box flat on a face is 0
-- (the load spreads, nothing digs); on an edge at 45 degrees or on a corner,
-- 1. A baton lying flat is 0; at 45 degrees or steeper, end first, 1.
local SQRT_HALF = math.sqrt(0.5)
local function pointed(b)
	if b.shape == 1 then
		local m = max(abs(b.r31), abs(b.r32), abs(b.r33))
		return min(1, (1 - m) / (1 - SQRT_HALF))
	end
	return min(1, abs(b.r33) / SQRT_HALF)
end
world.pointed = pointed

local function moving(b, lin, ang)
	return b.vx * b.vx + b.vy * b.vy + b.vz * b.vz > lin * lin
		or b.wx * b.wx + b.wy * b.wy + b.wz * b.wz > ang * ang
end

-- Speed bound of any point of b (for the speculative margin).
local function pointSpeed(b)
	if not b.awake then return 0 end
	return sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
		+ sqrt(b.wx * b.wx + b.wy * b.wy + b.wz * b.wz) * b.radius
end

local function pair(w, a, b, margin)
	if a.shape == 1 then
		if b.shape == 1 then collide.boxBox(a, b, margin)
		else collide.capsuleBox(b, a, margin) end
	else
		if b.shape == 1 then collide.capsuleBox(a, b, margin)
		else collide.capsuleCapsule(a, b, margin) end
	end
end

local function noteContact(w, b, other, px, py, pz)
	local rec = { t = w.time, x = px, y = py, z = pz, with = other and other.id or "ground" }
	if not w.firstContact then w.firstContact = rec end
	if other and not w.firstHit then w.firstHit = rec end
end

-- One sequential-impulse pass over the contacts.
local function solve(n, useBias)
	for i = 1, n do
		if ACTIVE[i] then
			local a, b = SA[i], SB[i]
			local ima = a.im
			local nx, ny, nz = cNx[i], cNy[i], cNz[i]
			local avx, avy, avz, awx, awy, awz = a.vx, a.vy, a.vz, a.wx, a.wy, a.wz
			local bvx, bvy, bvz, bwx, bwy, bwz, imb = 0, 0, 0, 0, 0, 0, 0
			if b then
				bvx, bvy, bvz, bwx, bwy, bwz, imb = b.vx, b.vy, b.vz, b.wx, b.wy, b.wz, b.im
			end
			local dvx, dvy, dvz = avx - bvx, avy - bvy, avz - bvz
			-- normal
			local vn = dvx * nx + dvy * ny + dvz * nz
				+ awx * AnX[i] + awy * AnY[i] + awz * AnZ[i]
				- bwx * BnX[i] - bwy * BnY[i] - bwz * BnZ[i]
			local target = useBias and BIAS[i] or RELAX[i]
			local old = LN[i]
			local lam = old - MN[i] * (vn - target)
			if lam < 0 then lam = 0 end
			LN[i] = lam
			if lam > LNMAX[i] then LNMAX[i] = lam end
			local d = lam - old
			if d ~= 0 then
				avx, avy, avz = avx + ima * d * nx, avy + ima * d * ny, avz + ima * d * nz
				awx, awy, awz = awx + d * WAnX[i], awy + d * WAnY[i], awz + d * WAnZ[i]
				if b then
					bvx, bvy, bvz = bvx - imb * d * nx, bvy - imb * d * ny, bvz - imb * d * nz
					bwx, bwy, bwz = bwx - d * WBnX[i], bwy - d * WBnY[i], bwz - d * WBnZ[i]
				end
			end
			-- friction: both tangents, clamped to the circular cone mu * lambda_n
			local t1x, t1y, t1z, t2x, t2y, t2z = T1x[i], T1y[i], T1z[i], T2x[i], T2y[i], T2z[i]
			dvx, dvy, dvz = avx - bvx, avy - bvy, avz - bvz
			local v1 = dvx * t1x + dvy * t1y + dvz * t1z
				+ awx * A1X[i] + awy * A1Y[i] + awz * A1Z[i]
				- bwx * B1X[i] - bwy * B1Y[i] - bwz * B1Z[i]
			local v2 = dvx * t2x + dvy * t2y + dvz * t2z
				+ awx * A2X[i] + awy * A2Y[i] + awz * A2Z[i]
				- bwx * B2X[i] - bwy * B2Y[i] - bwz * B2Z[i]
			local o1, o2 = LT1[i], LT2[i]
			local l1, l2 = o1 - MT1[i] * v1, o2 - MT2[i] * v2
			local cap = MU[i] * lam
			local m2 = l1 * l1 + l2 * l2
			if m2 > cap * cap then
				local s = (m2 > 0) and (cap / sqrt(m2)) or 0
				l1, l2 = l1 * s, l2 * s
			end
			LT1[i], LT2[i] = l1, l2
			local d1, d2 = l1 - o1, l2 - o2
			if d1 ~= 0 or d2 ~= 0 then
				local px, py, pz = d1 * t1x + d2 * t2x, d1 * t1y + d2 * t2y, d1 * t1z + d2 * t2z
				avx, avy, avz = avx + ima * px, avy + ima * py, avz + ima * pz
				awx = awx + d1 * WA1X[i] + d2 * WA2X[i]
				awy = awy + d1 * WA1Y[i] + d2 * WA2Y[i]
				awz = awz + d1 * WA1Z[i] + d2 * WA2Z[i]
				if b then
					bvx, bvy, bvz = bvx - imb * px, bvy - imb * py, bvz - imb * pz
					bwx = bwx - d1 * WB1X[i] - d2 * WB2X[i]
					bwy = bwy - d1 * WB1Y[i] - d2 * WB2Y[i]
					bwz = bwz - d1 * WB1Z[i] - d2 * WB2Z[i]
				end
			end
			a.vx, a.vy, a.vz, a.wx, a.wy, a.wz = avx, avy, avz, awx, awy, awz
			if b then b.vx, b.vy, b.vz, b.wx, b.wy, b.wz = bvx, bvy, bvz, bwx, bwy, bwz end
		end
	end
end

-- Apply impulse lam along the normal of contact i.
local function applyNormal(i, d)
	local a, b = SA[i], SB[i]
	local nx, ny, nz = cNx[i], cNy[i], cNz[i]
	local ima = a.im
	a.vx, a.vy, a.vz = a.vx + ima * d * nx, a.vy + ima * d * ny, a.vz + ima * d * nz
	a.wx, a.wy, a.wz = a.wx + d * WAnX[i], a.wy + d * WAnY[i], a.wz + d * WAnZ[i]
	if b then
		local imb = b.im
		b.vx, b.vy, b.vz = b.vx - imb * d * nx, b.vy - imb * d * ny, b.vz - imb * d * nz
		b.wx, b.wy, b.wz = b.wx - d * WBnX[i], b.wy - d * WBnY[i], b.wz - d * WBnZ[i]
	end
end

local function normalVelocity(i)
	local a, b = SA[i], SB[i]
	local vn = a.vx * cNx[i] + a.vy * cNy[i] + a.vz * cNz[i]
		+ a.wx * AnX[i] + a.wy * AnY[i] + a.wz * AnZ[i]
	if b then
		vn = vn - (b.vx * cNx[i] + b.vy * cNy[i] + b.vz * cNz[i])
			- (b.wx * BnX[i] + b.wy * BnY[i] + b.wz * BnZ[i])
	end
	return vn
end

-- Rolling resistance: an angular impulse of lever * normal impulse against
-- the body's spin, never more than stops it.
local function rollResist(b, lever, impulse)
	local L = lever * impulse
	if L <= 0 then return end
	local wx, wy, wz = b.wx, b.wy, b.wz
	local w2 = wx * wx + wy * wy + wz * wz
	if w2 < 1e-12 then return end
	local wn = sqrt(w2)
	local ux, uy, uz = wx / wn, wy / wn, wz / wn
	local ix, iy, iz = body.invInertiaMul(b, ux, uy, uz)
	-- angular impulse that stops the spin along u: wn / (u . I^-1 u)
	local stop = wn / (ux * ix + uy * iy + uz * iz)
	if L >= stop then
		b.wx, b.wy, b.wz = 0, 0, 0
	else
		b.wx, b.wy, b.wz = wx - L * ix, wy - L * iy, wz - L * iz
	end
end

-- ---------------------------------------------------------------------------
-- The step

function world.step(w)
	local t = world.tune
	local dt = t.dt
	local invDt = 1 / dt
	local surf = w.surface
	local bodies, nb = w.bodies, w.n
	local stamp = w.steps

	-- 1. forces
	local awakeCount = 0
	for i = 1, nb do
		local b = bodies[i]
		if b.awake then
			awakeCount = awakeCount + 1
			b.vz = b.vz - t.g * dt
			if t.gyro then gyro(b, dt) end
			b.groundImpulse = 0
		end
	end
	w.awakeCount = awakeCount

	-- 2. contacts: pairs, then the ground
	collide.reset()
	for i = 1, nb do
		local a = bodies[i]
		local sa = pointSpeed(a)
		for j = i + 1, nb do
			local b = bodies[j]
			if a.awake or b.awake then
				local margin = t.margin + (sa + pointSpeed(b)) * dt
				local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
				local reach = a.radius + b.radius + margin
				if dx * dx + dy * dy + dz * dz < reach * reach then
					local before = C.n
					pair(w, a, b, margin)
					if C.n > before then
						-- wake a sleeper that an awake, moving body touches
						if not a.awake and not a.static and moving(b, t.wakeLin, t.wakeAng) then
							wake(a); a.vz = a.vz - t.g * dt; a.groundImpulse = 0
						elseif not b.awake and not b.static and moving(a, t.wakeLin, t.wakeAng) then
							wake(b); b.vz = b.vz - t.g * dt; b.groundImpulse = 0
						end
					end
				end
			end
		end
	end
	local nPair = C.n
	for i = 1, nb do
		local b = bodies[i]
		if b.awake then
			local margin = t.margin + max(0, -b.vz) * dt
				+ sqrt(b.wx * b.wx + b.wy * b.wy + b.wz * b.wz) * b.radius * dt
			if b.shape == 1 then collide.groundBox(b, margin) else collide.groundCapsule(b, margin) end
		end
	end
	local n = C.n
	w.contacts = n

	-- 3. prepare
	local slop, pushRate, maxPush = t.slop, t.pushRate, t.maxPush
	for i = 1, n do
		local a, b = cA[i], cB[i]
		local nx, ny, nz = cNx[i], cNy[i], cNz[i]
		if not a.awake then
			-- A is asleep: if B is awake, make B the dynamic side
			if b and b.awake then
				a, b = b, a
				nx, ny, nz = -nx, -ny, -nz
				cNx[i], cNy[i], cNz[i] = nx, ny, nz
			else
				a = nil
			end
		end
		if a and b and not b.awake then b = false end
		if not a then
			ACTIVE[i] = false
		else
			ACTIVE[i] = true
			SA[i], SB[i] = a, b
			local px, py, pz = cPx[i], cPy[i], cPz[i]
			-- tangents
			local t1x, t1y, t1z, t2x, t2y, t2z
			if i > nPair then
				t1x, t1y, t1z, t2x, t2y, t2z = 1, 0, 0, 0, 1, 0
			else
				if abs(nx) < 0.57 then
					t1x, t1y, t1z = 0, nz, -ny
				else
					t1x, t1y, t1z = nz, 0, -nx
				end
				local l = 1 / sqrt(t1x * t1x + t1y * t1y + t1z * t1z)
				t1x, t1y, t1z = t1x * l, t1y * l, t1z * l
				t2x, t2y, t2z = ny * t1z - nz * t1y, nz * t1x - nx * t1z, nx * t1y - ny * t1x
			end
			T1x[i], T1y[i], T1z[i], T2x[i], T2y[i], T2z[i] = t1x, t1y, t1z, t2x, t2y, t2z
			local rax, ray, raz = px - a.x, py - a.y, pz - a.z
			local kn, k1, k2 = a.im, a.im, a.im
			local jx, jy, jz, wx, wy, wz, kk = angular(a, rax, ray, raz, nx, ny, nz)
			AnX[i], AnY[i], AnZ[i], WAnX[i], WAnY[i], WAnZ[i] = jx, jy, jz, wx, wy, wz
			kn = kn + kk
			jx, jy, jz, wx, wy, wz, kk = angular(a, rax, ray, raz, t1x, t1y, t1z)
			A1X[i], A1Y[i], A1Z[i], WA1X[i], WA1Y[i], WA1Z[i] = jx, jy, jz, wx, wy, wz
			k1 = k1 + kk
			jx, jy, jz, wx, wy, wz, kk = angular(a, rax, ray, raz, t2x, t2y, t2z)
			A2X[i], A2Y[i], A2Z[i], WA2X[i], WA2Y[i], WA2Z[i] = jx, jy, jz, wx, wy, wz
			k2 = k2 + kk
			if b then
				local rbx, rby, rbz = px - b.x, py - b.y, pz - b.z
				kn, k1, k2 = kn + b.im, k1 + b.im, k2 + b.im
				jx, jy, jz, wx, wy, wz, kk = angular(b, rbx, rby, rbz, nx, ny, nz)
				BnX[i], BnY[i], BnZ[i], WBnX[i], WBnY[i], WBnZ[i] = jx, jy, jz, wx, wy, wz
				kn = kn + kk
				jx, jy, jz, wx, wy, wz, kk = angular(b, rbx, rby, rbz, t1x, t1y, t1z)
				B1X[i], B1Y[i], B1Z[i], WB1X[i], WB1Y[i], WB1Z[i] = jx, jy, jz, wx, wy, wz
				k1 = k1 + kk
				jx, jy, jz, wx, wy, wz, kk = angular(b, rbx, rby, rbz, t2x, t2y, t2z)
				B2X[i], B2Y[i], B2Z[i], WB2X[i], WB2Y[i], WB2Z[i] = jx, jy, jz, wx, wy, wz
				k2 = k2 + kk
			else
				BnX[i], BnY[i], BnZ[i], WBnX[i], WBnY[i], WBnZ[i] = 0, 0, 0, 0, 0, 0
				B1X[i], B1Y[i], B1Z[i], WB1X[i], WB1Y[i], WB1Z[i] = 0, 0, 0, 0, 0, 0
				B2X[i], B2Y[i], B2Z[i], WB2X[i], WB2Y[i], WB2Z[i] = 0, 0, 0, 0, 0, 0
			end
			MN[i], MT1[i], MT2[i] = 1 / kn, 1 / k1, 1 / k2
			LN[i], LT1[i], LT2[i], LNMAX[i] = 0, 0, 0, 0
			local v0 = normalVelocity(i)
			V0[i] = v0
			-- velocity targets: a speculative contact may close its gap this
			-- step; an overlapping one is pushed apart (relax: not pushed)
			local sep = cSep[i]
			if sep > 0 then
				BIAS[i], RELAX[i] = -sep * invDt, -sep * invDt
			elseif sep < -slop then
				BIAS[i], RELAX[i] = min(pushRate * (-sep - slop) * invDt, maxPush), 0
			else
				BIAS[i], RELAX[i] = 0, 0
			end
			if i > nPair then
				-- ground: surface friction and bounce, dig, warm start
				local k = cSlot[i]
				local mu, e = surf.mu, surf.e
				local dig
				if a.gStamp[k] == stamp - 1 then
					dig = a.gDig[k]
					local wf = t.warm
					LN[i], LT1[i], LT2[i] = a.gN[k] * wf, a.gT1[k] * wf, a.gT2[k] * wf
				else
					-- a new contact: how steeply and how fast did it arrive?
					dig = 0
					if v0 < -surf.digSpeed and surf.dig > 0 then
						local vt1 = a.vx + a.wy * raz - a.wz * ray
						local vt2 = a.vy + a.wz * rax - a.wx * raz
						local steep = -v0 / sqrt(v0 * v0 + vt1 * vt1 + vt2 * vt2)
						local ramp = min(1, (-v0 - surf.digSpeed) / surf.digRamp)
						dig = surf.dig * steep * ramp * pointed(a)
						local lever = surf.digLever * min(1, dig)
						if lever > a.dig then a.dig = lever end
					end
				end
				a.gDig[k] = dig
				MU[i] = mu * (1 + dig)
				E[i] = e * max(0, 1 - dig)
			else
				MU[i], E[i] = t.pairMu, t.pairE
			end
			-- warm start
			if LN[i] > 0 or LT1[i] ~= 0 or LT2[i] ~= 0 then
				local l, l1, l2 = LN[i], LT1[i], LT2[i]
				local qx, qy, qz = l * nx + l1 * t1x + l2 * t2x, l * ny + l1 * t1y + l2 * t2y, l * nz + l1 * t1z + l2 * t2z
				a.vx, a.vy, a.vz = a.vx + a.im * qx, a.vy + a.im * qy, a.vz + a.im * qz
				a.wx = a.wx + l * WAnX[i] + l1 * WA1X[i] + l2 * WA2X[i]
				a.wy = a.wy + l * WAnY[i] + l1 * WA1Y[i] + l2 * WA2Y[i]
				a.wz = a.wz + l * WAnZ[i] + l1 * WA1Z[i] + l2 * WA2Z[i]
			end
		end
	end

	-- 4. solve with the push bias
	for _ = 1, t.iterations do solve(n, true) end

	-- 5. integrate positions
	for i = 1, nb do
		local b = bodies[i]
		if b.awake then
			b.x, b.y, b.z = b.x + b.vx * dt, b.y + b.vy * dt, b.z + b.vz * dt
			b.qw, b.qx, b.qy, b.qz = quat.integrate(b.qw, b.qx, b.qy, b.qz, b.wx, b.wy, b.wz, dt)
			body.updateDerived(b)
		end
	end

	-- 6. relax: remove the push-apart speed
	for _ = 1, t.relaxIterations do solve(n, false) end

	-- 7. restitution
	-- (several passes: a box landing flat has four corners, and one pass
	-- in order over them tips it and overshoots the bounce)
	local rs = t.restitutionSpeed
	for _ = 1, t.restitutionIterations do
		for i = 1, n do
			if ACTIVE[i] and V0[i] < -rs and LNMAX[i] > 0 and E[i] > 0 then
				local vn = normalVelocity(i)
				local old = LN[i]
				local lam = old - MN[i] * (vn + E[i] * V0[i])
				if lam < 0 then lam = 0 end
				LN[i] = lam
				if lam ~= old then applyNormal(i, lam - old) end
			end
		end
	end

	-- 8. store ground impulses; touches
	for i = 1, n do
		if ACTIVE[i] then
			local a, b = SA[i], SB[i]
			if i > nPair then
				local k = cSlot[i]
				a.gStamp[k], a.gN[k], a.gT1[k], a.gT2[k] = stamp, LN[i], LT1[i], LT2[i]
				a.groundImpulse = a.groundImpulse + LN[i]
				if LNMAX[i] > 0 and a == w.projectile and not w.firstContact then
					noteContact(w, a, nil, cPx[i], cPy[i], cPz[i])
				end
			elseif LNMAX[i] > 0 then
				local other = cB[i]
				local first = cA[i]
				first.touched, other.touched = true, true
				local proj = w.projectile
				if proj and not w.firstHit and (first == proj or other == proj) then
					noteContact(w, proj, (first == proj) and other or first, cPx[i], cPy[i], cPz[i])
				end
			end
		end
	end

	-- rolling resistance and dig, then sleep and bookkeeping
	w.time = w.time + dt
	w.steps = stamp + 1
	local digFade = 1
	local sinTopple = sin(rad(t.toppleDeg))
	local half, len, om = t.pitchHalfWidth, t.pitchLength, t.outMargin
	for i = 1, nb do
		local b = bodies[i]
		if b.awake then
			local gi = b.groundImpulse
			if gi > 0 then
				local lever = b.dig
				if b.shape == 2 then lever = lever + surf.roll end
				rollResist(b, lever, gi)
			end
			if b.dig > 0 then
				b.dig = b.dig * exp(-dt / surf.digTime)
				if b.dig < 1e-5 then b.dig = 0 end
			end
			if b.shape == 1 and not b.toppled and abs(b.r33) <= sinTopple then b.toppled = true end
			if abs(b.x) > half + om or b.y < -om or b.y > len + om then b.leftPitch = true end
			local v2 = b.vx * b.vx + b.vy * b.vy + b.vz * b.vz
			local w2 = b.wx * b.wx + b.wy * b.wy + b.wz * b.wz
			if v2 < t.sleepLin * t.sleepLin and w2 < t.sleepAng * t.sleepAng and gi > 0 then
				b.sleepTime = b.sleepTime + dt
				if b.sleepTime >= t.sleepTime then
					b.awake = false
					b.vx, b.vy, b.vz, b.wx, b.wy, b.wz = 0, 0, 0, 0, 0, 0
					b.dig = 0
				end
			else
				b.sleepTime = 0
			end
		end
	end
	return w
end

-- Everything asleep (or the throw ran past tune.maxTime).
function world.isAtRest(w)
	if w.time >= world.tune.maxTime then return true end
	local bodies = w.bodies
	for i = 1, w.n do
		if bodies[i].awake then return false end
	end
	return true
end

-- Step until at rest or for at most `seconds` more.
function world.run(w, seconds)
	local stop = w.time + (seconds or world.tune.maxTime)
	while not world.isAtRest(w) and w.time < stop - 1e-9 do world.step(w) end
	return w
end

-- Is the center outside the pitch (beyond tune.outMargin)?
function world.outside(x, y)
	local t = world.tune
	return abs(x) > t.pitchHalfWidth + t.outMargin or y < -t.outMargin or y > t.pitchLength + t.outMargin
end

-- The outcome of the throw:
--   time, steps           simulated time and steps
--   touched               ids of bodies something touched (the projectile included)
--   stakesTouched         ids of stakes something touched (stake1 .. stake6, core/pitch order)
--   toppled               ids of kubbs and kings that toppled in this throw
--   kingToppled           true if a king toppled
--   outNotToppled         ids of kubbs that ended outside the pitch without toppling
--   bodies[id]            {kind, x, y, z, qw, qx, qy, qz, toppled, touched, out, leftPitch}
--   firstContact, firstHit  the projectile's first contact (any) and first body hit
function world.result(w)
	local r = {
		time = w.time, steps = w.steps,
		touched = {}, toppled = {}, outNotToppled = {}, kingToppled = false,
		stakesTouched = {},
		bodies = {},
		firstContact = w.firstContact, firstHit = w.firstHit,
	}
	for i = 1, w.n do
		local b = w.bodies[i]
		local out = world.outside(b.x, b.y)
		r.bodies[b.id] = {
			kind = b.kind, x = b.x, y = b.y, z = b.z, qw = b.qw, qx = b.qx, qy = b.qy, qz = b.qz,
			toppled = b.toppled, touched = b.touched, out = out, leftPitch = b.leftPitch,
		}
		if b.touched then
			if b.static then r.stakesTouched[#r.stakesTouched + 1] = b.id
			else r.touched[#r.touched + 1] = b.id end
		end
		if b.shape == 1 and b.toppled and not b.wasToppled and b ~= w.projectile then
			r.toppled[#r.toppled + 1] = b.id
			if b.kind == "king" then r.kingToppled = true end
		end
		if b.shape == 1 and out and not b.toppled and b ~= w.projectile then
			r.outNotToppled[#r.outNotToppled + 1] = b.id
		end
	end
	return r
end

-- Total energy (kinetic + potential) of all moving bodies, J.
function world.energy(w)
	local e = 0
	for i = 1, w.n do
		local b = w.bodies[i]
		if not b.static then e = e + body.energy(b, world.tune.g) end
	end
	return e
end

tw.world = world
