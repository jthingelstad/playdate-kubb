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
-- A drilled kubb (world.launchDrill) differs on the ground in a few flagged
-- ways (body.lua), so every other body steps exactly as before: its dig is
-- judged by its centre's arrival, its plug holds its tumble but not its roll
-- about the long axis, the grass drags its slip rather than its roll, its long
-- edges meet the ground rounded, and it gets no landing bump.
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
import "core/drill"

local quat, body, collide = tw.quat, tw.body, tw.collide
local sqrt, abs, min, max, sin, cos, rad, exp = math.sqrt, math.abs, math.min, math.max, math.sin, math.cos, math.rad, math.exp
local floor = math.floor

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
	batonTurnHold = 1,     -- share of the ground's rolling resistance (surf.roll) that also holds a
	                       -- baton's end-over-end turn on the ground (all of it holds its roll
	                       -- about the long axis; the plug, dig, holds both)
	rollCap = 4,           -- a baton's rolling resistance takes the ground's impulse up to this
	                       -- many times its weight a step (a landing's one hard step is far more)
	restitutionIterations = 4, -- bounce passes (one pass over a flat landing's corners overshoots)
	pairMu = 0.4,          -- wood on wood friction (guess; dry wood 0.25 to 0.5)
	boxMu = 0.2,           -- friction between two boxes (kubb on kubb, the king; guess: wood sliding
	                       -- on wood, 0.2). At pairMu a kubb tipped against its neighbour was held
	                       -- up by the rub of its edge down the neighbour's face, and a tight row
	                       -- stood through a blow that fells four kubbs (Jamie, 2026-11-15)
	pairE = 0.2,           -- wood on wood bounce (guess; 0.35 until 2026-11-15: a baton's bounce off a
	                       -- standing kubb is applied with nothing holding the kubb's footing, so
	                       -- part of it drove the kubb down and the ground threw it up; at 0.2,
	                       -- over tools/batonprobe.lua's sweep, half the bounce-backs and a sixth
	                       -- fewer kubbs off the ground for 0.2 s or more)
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
	stakeHeight = 0.15,    -- m above the ground (6 inches, Jamie 2026-11-14); stakes are fixed posts of radius pitch.stakeRadius
	-- wind (Jamie and Tyler, 2026-11-14): air drag per kind, 0.5 rho Cd A / m
	-- (1/m), A the mean area a tumbling piece shows the air (end over end it
	-- shows its narrow end part of the time), Cd about 1: a baton 0.30 x
	-- 0.044 m, 0.25 kg; a lobbed kubb 0.07 x 0.15 m, 0.40 kg. A full 8 m
	-- baton drifts about 0.16 m in a light (2.5 m/s) cross wind, 0.43 in a
	-- strong (6 m/s) one, and loses about 0.95 m into a strong head wind
	windK = { baton = 0.015, kubb = 0.0086 },
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
--   texture     (optional) what a flat plane leaves out (Jamie, 2026-11-14:
--               "in a real game there is always random stuff because of the
--               surface"). The ground is cut into `cell`-sized patches, each
--               with its own values from a hash of the patch and the throw's
--               seed (world.groundSeed), read only when a contact is new:
--     muVar, eVar, digVar  a patch's friction, bounce and dig vary by up to
--               this share either way (clumps, bare spots, soft ground)
--     bump      a steep landing (approach faster than bumpSpeed m/s) is turned
--               sideways by up to bump times its approach speed, as off a patch
--               tilted a few degrees (its travel only, no spin)
--     drag      1/s: a lying piece or a baton touching the ground loses this
--               share of its ground speed a second (the blades hold it)
--     grip, gripSpeed  1/s and m/s: and this much more a second below
--               gripSpeed, so it stops instead of creeping
--     trip      rad/s^2 per m/s: a baton sliding upright on an end (within
--               30 degrees) faster than tripSpeed is tipped toward the way it
--               is going, as its foot catches
--     foot, footSpeed  1/s and m/s: a kubb or the king standing (within 30
--               degrees of upright) whose foot slides faster than footSpeed
--               loses this share of that slip a second, taken at the foot, so
--               it slows and tips the way it is going (plough adds to it)
--     plough    1/s per m (optional): the drag grows with the distance a piece
--               has slid since it last left the ground (snow piles up in front
--               of it), so a slide starts slick and ends heavy
world.surfaces = {
	grass = {
		name = "grass", mu = 0.7, e = 0.15,
		dig = 1.0, digSpeed = 0.3, digRamp = 1.5, digLever = 0.006, digTime = 0.15,
		roll = 0.01,
		texture = { cell = 0.25, muVar = 0.3, eVar = 0.5, digVar = 0.5, bump = 0.12, bumpSpeed = 0.8,
			drag = 2.5, grip = 12, gripSpeed = 0.5, trip = 60, tripSpeed = 0.15, foot = 25, footSpeed = 0.3 },
	},
	-- sand (DESIGN 5): very high dig, almost no bounce or slide; pieces plug where
	-- they land, so placement is all in the air. Its texture: soft and packed
	-- spots (dig varies a lot), ridges and footprints that turn a landing more
	-- than grass does, and sand that drags hard and grabs.
	sand = {
		name = "sand", mu = 0.9, e = 0.03,
		dig = 3.0, digSpeed = 0.2, digRamp = 1.0, digLever = 0.03, digTime = 0.5,
		roll = 0.03,
		texture = { cell = 0.2, muVar = 0.25, eVar = 0.4, digVar = 0.7, bump = 0.18, bumpSpeed = 0.6,
			drag = 6, grip = 20, gripSpeed = 0.6, trip = 120, tripSpeed = 0.1 },
	},
	-- snow (Jamie, 2026-11-14): packed snow is slick to a fast piece, but soft:
	-- a steep landing plugs, almost nothing bounces, and a sliding piece ploughs
	-- snow ahead of it, so it starts fast and stops heavy. Icy and soft patches
	-- (friction and dig vary most of all here).
	snow = {
		name = "snow", mu = 0.25, e = 0.02,
		dig = 2.5, digSpeed = 0.3, digRamp = 1.2, digLever = 0.025, digTime = 0.4,
		roll = 0.004,
		texture = { cell = 0.3, muVar = 0.5, eVar = 0.3, digVar = 0.8, bump = 0.1, bumpSpeed = 0.8,
			drag = 0.6, grip = 4, gripSpeed = 0.3, trip = 70, tripSpeed = 0.15, plough = 1.5,
			foot = 12, footSpeed = 0.3 },
	},
	-- ICE (stage 7, not built): very low friction for the Minnesota slide,
	-- something like mu = 0.05, e = 0.1, dig = 0, roll = 0.0005. Add it
	-- here as another parameter set; nothing else should need to change.
}
-- The surfaces a game can be played on, in the order they are offered.
world.SURFACES = { "grass", "sand", "snow" }

-- Optional profiling (the device autobench): set world.prof to a table
-- from world.newProf(clock) and world.step adds the seconds of each phase
-- into it. nil (the default) costs one test per phase.
world.prof = nil
world.PHASES = { "forces", "pairs", "ground", "prepare", "solve", "integrate", "relax",
	"restitution", "store", "tail", "lone" }
function world.newProf(clock)
	local p = { clock = clock, narrow = 0 }
	for _, k in ipairs(world.PHASES) do p[k] = 0 end
	return p
end

-- The awake set's epoch: bumped whenever any body in any world wakes, falls
-- asleep or is added. A world caches what the lone-flight test needs (the one
-- awake body, the highest point of everything else) and rebuilds it when
-- the epoch has moved. A sleeping body is never moved by hand; if one ever
-- is, call world.touch() so the cache is rebuilt.
local epoch = 0
function world.touch() epoch = epoch + 1 end

-- ---------------------------------------------------------------------------
-- Building a world

function world.new(opts)
	opts = opts or {}
	local surf = opts.surface or "grass"
	if type(surf) == "string" then surf = assert(world.surfaces[surf], "unknown surface " .. surf) end
	-- opts.texture = false: the surface as a flat plane (tests of one piece of
	-- mechanics; tools/groundstats --flat)
	if opts.texture == false and surf.texture then
		local flat = {}
		for k, v in pairs(surf) do flat[k] = v end
		flat.texture = nil
		surf = flat
	end
	local w = {
		bodies = {}, n = 0, byId = {},
		surface = surf,
		time = 0, steps = 0,
		projectile = nil,
		firstContact = nil,   -- the projectile's first contact: {t, x, y, z, with}
		firstHit = nil,       -- its first contact with another body: same fields
		contacts = 0,         -- contacts in the last step (for the bench)
		awakeCount = 0,       -- awake bodies in the last step
		groundSeed = opts.groundSeed or 0,   -- the ground texture's seed (world.launch sets it
		groundSeedFixed = opts.groundSeed ~= nil,   -- from the throw unless one is given here)
		-- the wind (m/s, horizontal): it pushes the thrown piece until its
		-- first contact (windForce); none, and nothing changes
		windX = opts.windX or 0, windY = opts.windY or 0,
		windOn = (opts.windX or 0) ~= 0 or (opts.windY or 0) ~= 0,
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
	epoch = epoch + 1
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
	b.toppled = p.toppled or (b.shape == 1 and (body.lying(b, sin(rad(world.tune.toppleDeg))) or body.wouldFall(b)))
	b.wasToppled = b.toppled
	return b
end

local function wake(b)
	if not b.awake and not b.static then
		epoch = epoch + 1
		b.awake = true
		b.everAwake = true
		b.sleepTime = 0
	end
end
world.wake = wake

-- Launch a projectile body (baton or kubb) with a full pose and velocity.
-- Angular velocity is in the world frame.
-- The ground texture's seed for a throw: from the launch itself, so the same
-- throw meets the same ground (replays, tests) and every other throw its own.
local function seedFrom(...)
	local h = 0x2545F491
	for _, v in ipairs { ... } do
		h = (h ~ math.floor(v * 4096)) * 0x9E3779B1 & 0x7fffffff
	end
	return h
end
world.seedFrom = seedFrom

function world.launch(w, kind, id, x, y, z, qw, qx, qy, qz, vx, vy, vz, wx, wy, wz)
	local b = world.addBody(w, kind, id)
	body.setPose(b, x, y, z, qw, qx, qy, qz)
	body.setVelocity(b, vx, vy, vz, wx, wy, wz)
	if not w.groundSeedFixed then w.groundSeed = seedFrom(x, y, vx, vy, vz, wx, wy, wz) end
	wake(b)
	b.touched = true
	w.projectile = b
	b.windK = world.tune.windK[kind] or 0
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

-- A lobbed kubb (stage 3's simple inkast; drilling and the cut are stage 4):
-- the same launch as a clean baton, upright in the hand and turning end
-- over end at tumbleRate, as body `id` (the kubb's own id).
function world.launchKubb(w, id, x, lineY, swivel, loftDeg, speed, tumbleRate)
	return world.launch(w, "kubb", id,
		world.batonLaunchState(x, lineY, swivel, loftDeg, speed, tumbleRate, 0))
end

-- A drilled kubb (core/drill): it leaves the hand at (x, lineY, handHeight)
-- along the swivel at the loft, its long axis pointing down the line of
-- flight with the nose noseDownDeg below the horizontal (measured from the
-- horizontal, not the flight path: a kubb spinning about its long axis keeps
-- that axis through the flight, so what it lands with is what it leaves the
-- hand with, and it is the angle to the grass that makes the nose catch). It
-- spins about that axis at spinRate (rad/s; + = clockwise seen from behind,
-- which rolls it right once it is down) and the release roll is chosen so
-- that when the nose first touches it is rolled rollLandDeg from flat on a
-- face, toward the way the spin turns it (flat with no spin). wobbleRate
-- (rad/s) turns it nose over tail about the right-hand axis (a jerky swing).
-- digGain is how much harder its first touches dig into the ground than the
-- surface's dig (body.digGain). launchDrill also gives the body the drilled
-- kubb's ground behaviour from drill.tune (body.lua: edgeRound, digBySpin,
-- slipDrag, rollDrag, plugGain, bumpGain).
function world.drillLaunchState(x, lineY, swivel, loftDeg, speed, noseDownDeg, rollLandDeg, spinRate, wobbleRate)
	local dx, dy = sin(swivel), cos(swivel)
	local lx, ly, lz = launchDir(swivel, loftDeg)
	local ft = tw.flight.tune
	local h = ft.handHeight
	local a = rad(noseDownDeg)
	local ca, sa = cos(a), sin(a)
	-- the roll at the first touch: rollLandDeg toward the way the spin rolls
	-- it (flat on a face with no spin)
	local land = rad(rollLandDeg)
	if spinRate < 0 then land = -land elseif spinRate == 0 then land = 0 end
	-- flight time until the nose's lowest point reaches the grass: the kubb
	-- rolled `land`, the nose a below the horizontal, its long edges rounded
	-- to er against the ground (collide.groundBox)
	local kk = body.kinds.kubb
	local er = tw.drill.tune.edgeRound
	local sl = sin(land)
	if sl < 0 then sl = -sl end
	local zc = kk.hz * sa + ca * ((kk.hy - er) * cos(land) + (kk.hx - er) * sl + er)
	local vz = speed * lz
	local h0 = h - zc
	local T = (vz + sqrt(vz * vz + 2 * ft.g * h0)) / ft.g
	-- local z: the long axis; x: the right-hand side, then rolled by phi about z
	local zx, zy, zz = dx * ca, dy * ca, -sa
	local rx, ry, rz = dy, -dx, 0
	local yx, yy, yz = zy * rz - zz * ry, zz * rx - zx * rz, zx * ry - zy * rx
	local phi = land - spinRate * T
	local c, s = cos(phi), sin(phi)
	local xx, xy, xz = c * rx + s * yx, c * ry + s * yy, c * rz + s * yz
	yx, yy, yz = -s * rx + c * yx, -s * ry + c * yy, -s * rz + c * yz
	local qw, qx, qy, qz = quat.fromAxes(xx, xy, xz, yx, yy, yz, zx, zy, zz)
	return x, lineY, h, qw, qx, qy, qz,
		speed * lx, speed * ly, speed * lz,
		spinRate * zx + wobbleRate * rx, spinRate * zy + wobbleRate * ry, spinRate * zz
end

function world.launchDrill(w, id, x, lineY, swivel, loftDeg, speed, noseDownDeg, rollLandDeg, spinRate,
		wobbleRate, digGain)
	local b = world.launch(w, "kubb", id, world.drillLaunchState(x, lineY, swivel, loftDeg, speed,
		noseDownDeg, rollLandDeg, spinRate, wobbleRate))
	b.digGain = digGain or 1
	-- what makes it a drilled kubb on the ground (body.lua, drill.tune)
	local dt = tw.drill.tune
	b.edgeRound, b.rollDrag, b.bumpGain, b.plugGain = dt.edgeRound, dt.rollDrag, dt.bumpGain, dt.plugGain
	b.digBySpin, b.slipDrag = false, true
	return b
end

-- ---------------------------------------------------------------------------
-- The solver's contacts
--
-- Speed on the device (AGENTS.md "Physics", device costs): a Lua function
-- call costs about 9 us there, a C call (math.sqrt, math.abs, math.min) about
-- 4 us and every switch to another table a cache miss, so the hot paths below
-- are written out in full: no helper calls per pair, per contact or per pass,
-- comparisons instead of math.abs/min/max, and each solver contact is one
-- record (the array part of one table, read with constant indices) rather than
-- sixty parallel arrays. The arithmetic is the same as the plain version, term
-- for term and in the same order, so results are unchanged. Ground contacts
-- (normal +z, tangents +x and +y, nothing on the other side) and contacts
-- with a sleeping or static body (nothing moves on the other side) skip the
-- terms that are zero.

local C = collide.C
local cA, cB, cSlot = C.A, C.B, C.slot
local cPx, cPy, cPz, cNx, cNy, cNz, cSep = C.px, C.py, C.pz, C.nx, C.ny, C.nz, C.sep

-- Record fields. Kind: 1 ground, 2 two awake bodies, 3 B asleep or static.
local K_A <const>, K_B <const>, K_KIND <const>, K_IDX <const> = 1, 2, 3, 4
local K_NX <const>, K_NY <const>, K_NZ <const> = 5, 6, 7
local K_T1X <const>, K_T1Y <const>, K_T1Z <const>, K_T2X <const>, K_T2Y <const>, K_T2Z <const> = 8, 9, 10, 11, 12, 13
-- A's angular terms: (ra x d) and I^-1 (ra x d) for d = n, t1, t2; then B's
local K_ANX <const>, K_ANY <const>, K_ANZ <const>, K_WANX <const>, K_WANY <const>, K_WANZ <const> = 14, 15, 16, 17, 18, 19
local K_A1X <const>, K_A1Y <const>, K_A1Z <const>, K_WA1X <const>, K_WA1Y <const>, K_WA1Z <const> = 20, 21, 22, 23, 24, 25
local K_A2X <const>, K_A2Y <const>, K_A2Z <const>, K_WA2X <const>, K_WA2Y <const>, K_WA2Z <const> = 26, 27, 28, 29, 30, 31
local K_BNX <const>, K_BNY <const>, K_BNZ <const>, K_WBNX <const>, K_WBNY <const>, K_WBNZ <const> = 32, 33, 34, 35, 36, 37
local K_B1X <const>, K_B1Y <const>, K_B1Z <const>, K_WB1X <const>, K_WB1Y <const>, K_WB1Z <const> = 38, 39, 40, 41, 42, 43
local K_B2X <const>, K_B2Y <const>, K_B2Z <const>, K_WB2X <const>, K_WB2Y <const>, K_WB2Z <const> = 44, 45, 46, 47, 48, 49
local K_MN <const>, K_MT1 <const>, K_MT2 <const> = 50, 51, 52   -- effective masses
local K_BIAS <const>, K_RELAX <const> = 53, 54                  -- velocity targets with and without the push
local K_V0 <const>, K_MU <const>, K_E <const> = 55, 56, 57
local K_LN <const>, K_LT1 <const>, K_LT2 <const> = 58, 59, 60   -- accumulated impulses
local K_LNMAX <const> = 61                                      -- largest normal impulse seen

local REC = {}   -- the records of this step's active contacts, 1 .. nRec (reused)
local nRec = 0

-- Per body, filled each step: position, bounding radius, awake, speed bound.
local BX, BY, BZ, BR, AW, SPD, NXT = {}, {}, {}, {}, {}, {}, {}
-- Bodies woken in this step's pair loop (indices), and for each the index below
-- which its pairs with sleepers were passed untested (world.step).
local WK, WLO = {}, {}
local WT, WPOS = {}, {}

-- Implicit gyroscopic step (Bullet's computeGyroscopicImpulseImplicit_Body):
-- one Newton step of I w' = I w - dt w' x I w' in the body frame. Keeps a
-- spinning baton or kubb precessing correctly without blowing up.
-- The wind on the thrown piece in the air (Jamie and Tyler, 2026-11-14): its
-- drag in the moving air less its drag in still air, k (|r| r + |v| v) with
-- r = wind - v, so with no wind it is nothing at all (the throws are tuned
-- in still air). Applied by world.step and the lone step alike, right after
-- gravity, only to w.projectile until its first contact: once it lands, the
-- wind's push is lost in the ground's.
local function windForce(w, b, dt)
	local k = b.windK
	if not k or k == 0 then return end
	local vx, vy, vz = b.vx, b.vy, b.vz
	local rx, ry = w.windX - vx, w.windY - vy
	local rel = sqrt(rx * rx + ry * ry + vz * vz)
	local still = sqrt(vx * vx + vy * vy + vz * vz)
	local kd = k * dt
	b.vx = vx + kd * (rel * rx + still * vx)
	b.vy = vy + kd * (rel * ry + still * vy)
	b.vz = vz + kd * (still - rel) * vz
end
world.windForce = windForce

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
	if det < 1e-30 and det > -1e-30 then return end
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

local function noteContact(w, b, other, px, py, pz)
	local rec = { t = w.time, x = px, y = py, z = pz, with = other and other.id or "ground" }
	if not w.firstContact then w.firstContact = rec end
	if other and not w.firstHit then w.firstHit = rec end
end

-- One sequential-impulse pass over the contacts; tk = K_BIAS or K_RELAX.
local function solve(tk)
	for i = 1, nRec do
		local r = REC[i]
		local a, kind = r[K_A], r[K_KIND]
		local ima = a.im
		local avx, avy, avz, awx, awy, awz = a.vx, a.vy, a.vz, a.wx, a.wy, a.wz
		if kind == 1 then
			-- the ground: n = +z, t1 = +x, t2 = +y
			local anx, any = r[K_ANX], r[K_ANY]
			local vn = avz + awx * anx + awy * any
			local old = r[K_LN]
			local lam = old - r[K_MN] * (vn - r[tk])
			if lam < 0 then lam = 0 end
			r[K_LN] = lam
			if lam > r[K_LNMAX] then r[K_LNMAX] = lam end
			local d = lam - old
			if d ~= 0 then
				avz = avz + ima * d
				awx, awy, awz = awx + d * r[K_WANX], awy + d * r[K_WANY], awz + d * r[K_WANZ]
			end
			local a1y, a1z, a2x, a2z = r[K_A1Y], r[K_A1Z], r[K_A2X], r[K_A2Z]
			local v1 = avx + awy * a1y + awz * a1z
			local v2 = avy + awx * a2x + awz * a2z
			local o1, o2 = r[K_LT1], r[K_LT2]
			local l1, l2 = o1 - r[K_MT1] * v1, o2 - r[K_MT2] * v2
			local cap = r[K_MU] * lam
			local m2 = l1 * l1 + l2 * l2
			if m2 > cap * cap then
				local s = (m2 > 0) and (cap / sqrt(m2)) or 0
				l1, l2 = l1 * s, l2 * s
			end
			r[K_LT1], r[K_LT2] = l1, l2
			local d1, d2 = l1 - o1, l2 - o2
			if d1 ~= 0 or d2 ~= 0 then
				avx, avy = avx + ima * d1, avy + ima * d2
				awx = awx + d1 * r[K_WA1X] + d2 * r[K_WA2X]
				awy = awy + d1 * r[K_WA1Y] + d2 * r[K_WA2Y]
				awz = awz + d1 * r[K_WA1Z] + d2 * r[K_WA2Z]
			end
			a.vx, a.vy, a.vz, a.wx, a.wy, a.wz = avx, avy, avz, awx, awy, awz
		elseif kind == 3 then
			-- B asleep or static: nothing moves on its side
			local nx, ny, nz = r[K_NX], r[K_NY], r[K_NZ]
			local vn = avx * nx + avy * ny + avz * nz
				+ awx * r[K_ANX] + awy * r[K_ANY] + awz * r[K_ANZ]
			local old = r[K_LN]
			local lam = old - r[K_MN] * (vn - r[tk])
			if lam < 0 then lam = 0 end
			r[K_LN] = lam
			if lam > r[K_LNMAX] then r[K_LNMAX] = lam end
			local d = lam - old
			if d ~= 0 then
				avx, avy, avz = avx + ima * d * nx, avy + ima * d * ny, avz + ima * d * nz
				awx, awy, awz = awx + d * r[K_WANX], awy + d * r[K_WANY], awz + d * r[K_WANZ]
			end
			local t1x, t1y, t1z, t2x, t2y, t2z = r[K_T1X], r[K_T1Y], r[K_T1Z], r[K_T2X], r[K_T2Y], r[K_T2Z]
			local v1 = avx * t1x + avy * t1y + avz * t1z
				+ awx * r[K_A1X] + awy * r[K_A1Y] + awz * r[K_A1Z]
			local v2 = avx * t2x + avy * t2y + avz * t2z
				+ awx * r[K_A2X] + awy * r[K_A2Y] + awz * r[K_A2Z]
			local o1, o2 = r[K_LT1], r[K_LT2]
			local l1, l2 = o1 - r[K_MT1] * v1, o2 - r[K_MT2] * v2
			local cap = r[K_MU] * lam
			local m2 = l1 * l1 + l2 * l2
			if m2 > cap * cap then
				local s = (m2 > 0) and (cap / sqrt(m2)) or 0
				l1, l2 = l1 * s, l2 * s
			end
			r[K_LT1], r[K_LT2] = l1, l2
			local d1, d2 = l1 - o1, l2 - o2
			if d1 ~= 0 or d2 ~= 0 then
				local px, py, pz = d1 * t1x + d2 * t2x, d1 * t1y + d2 * t2y, d1 * t1z + d2 * t2z
				avx, avy, avz = avx + ima * px, avy + ima * py, avz + ima * pz
				awx = awx + d1 * r[K_WA1X] + d2 * r[K_WA2X]
				awy = awy + d1 * r[K_WA1Y] + d2 * r[K_WA2Y]
				awz = awz + d1 * r[K_WA1Z] + d2 * r[K_WA2Z]
			end
			a.vx, a.vy, a.vz, a.wx, a.wy, a.wz = avx, avy, avz, awx, awy, awz
		else
			-- two awake bodies
			local b = r[K_B]
			local imb = b.im
			local bvx, bvy, bvz, bwx, bwy, bwz = b.vx, b.vy, b.vz, b.wx, b.wy, b.wz
			local nx, ny, nz = r[K_NX], r[K_NY], r[K_NZ]
			local dvx, dvy, dvz = avx - bvx, avy - bvy, avz - bvz
			local vn = dvx * nx + dvy * ny + dvz * nz
				+ awx * r[K_ANX] + awy * r[K_ANY] + awz * r[K_ANZ]
				- bwx * r[K_BNX] - bwy * r[K_BNY] - bwz * r[K_BNZ]
			local old = r[K_LN]
			local lam = old - r[K_MN] * (vn - r[tk])
			if lam < 0 then lam = 0 end
			r[K_LN] = lam
			if lam > r[K_LNMAX] then r[K_LNMAX] = lam end
			local d = lam - old
			if d ~= 0 then
				avx, avy, avz = avx + ima * d * nx, avy + ima * d * ny, avz + ima * d * nz
				awx, awy, awz = awx + d * r[K_WANX], awy + d * r[K_WANY], awz + d * r[K_WANZ]
				bvx, bvy, bvz = bvx - imb * d * nx, bvy - imb * d * ny, bvz - imb * d * nz
				bwx, bwy, bwz = bwx - d * r[K_WBNX], bwy - d * r[K_WBNY], bwz - d * r[K_WBNZ]
			end
			local t1x, t1y, t1z, t2x, t2y, t2z = r[K_T1X], r[K_T1Y], r[K_T1Z], r[K_T2X], r[K_T2Y], r[K_T2Z]
			dvx, dvy, dvz = avx - bvx, avy - bvy, avz - bvz
			local v1 = dvx * t1x + dvy * t1y + dvz * t1z
				+ awx * r[K_A1X] + awy * r[K_A1Y] + awz * r[K_A1Z]
				- bwx * r[K_B1X] - bwy * r[K_B1Y] - bwz * r[K_B1Z]
			local v2 = dvx * t2x + dvy * t2y + dvz * t2z
				+ awx * r[K_A2X] + awy * r[K_A2Y] + awz * r[K_A2Z]
				- bwx * r[K_B2X] - bwy * r[K_B2Y] - bwz * r[K_B2Z]
			local o1, o2 = r[K_LT1], r[K_LT2]
			local l1, l2 = o1 - r[K_MT1] * v1, o2 - r[K_MT2] * v2
			local cap = r[K_MU] * lam
			local m2 = l1 * l1 + l2 * l2
			if m2 > cap * cap then
				local s = (m2 > 0) and (cap / sqrt(m2)) or 0
				l1, l2 = l1 * s, l2 * s
			end
			r[K_LT1], r[K_LT2] = l1, l2
			local d1, d2 = l1 - o1, l2 - o2
			if d1 ~= 0 or d2 ~= 0 then
				local px, py, pz = d1 * t1x + d2 * t2x, d1 * t1y + d2 * t2y, d1 * t1z + d2 * t2z
				avx, avy, avz = avx + ima * px, avy + ima * py, avz + ima * pz
				awx = awx + d1 * r[K_WA1X] + d2 * r[K_WA2X]
				awy = awy + d1 * r[K_WA1Y] + d2 * r[K_WA2Y]
				awz = awz + d1 * r[K_WA1Z] + d2 * r[K_WA2Z]
				bvx, bvy, bvz = bvx - imb * px, bvy - imb * py, bvz - imb * pz
				bwx = bwx - d1 * r[K_WB1X] - d2 * r[K_WB2X]
				bwy = bwy - d1 * r[K_WB1Y] - d2 * r[K_WB2Y]
				bwz = bwz - d1 * r[K_WB1Z] - d2 * r[K_WB2Z]
			end
			a.vx, a.vy, a.vz, a.wx, a.wy, a.wz = avx, avy, avz, awx, awy, awz
			b.vx, b.vy, b.vz, b.wx, b.wy, b.wz = bvx, bvy, bvz, bwx, bwy, bwz
		end
	end
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
	local ix = b.i11 * ux + b.i12 * uy + b.i13 * uz
	local iy = b.i12 * ux + b.i22 * uy + b.i23 * uz
	local iz = b.i13 * ux + b.i23 * uy + b.i33 * uz
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

local boxBox, capsuleBox, capsuleCapsule = collide.boxBox, collide.capsuleBox, collide.capsuleCapsule
local groundBox, groundCapsule = collide.groundBox, collide.groundCapsule

-- The lone flight. A step with exactly one body awake that is clear of the
-- ground and above everything else (its lowest point higher than the
-- highest point of every sleeping or static body, by more than the contact
-- margin the step could use) finds no contact: the full step would then only
-- apply gravity and the gyroscopic term, move and turn that body and do its
-- bookkeeping. loneStep does exactly that and nothing else, in the same
-- order with the same arithmetic, so results are bit-identical; it saves
-- every loop over the other bodies (a thrown baton spends about half its
-- steps like this). The test is conservative: it bounds the speeds after
-- the forces from above and keeps loneSlack (m) in hand for rounding.
world.loneFlight = true
local LONE_SLACK <const> = 0.001
local COS_END <const> = 0.866   -- cos 30 degrees: within this of upright is "on an end"

local function loneRefresh(w)
	local bodies = w.bodies
	local lone, count, top = false, 0, -1e9
	for i = 1, w.n do
		local b = bodies[i]
		if b.awake then
			count = count + 1
			lone = b
		else
			local h = b.z + b.radius
			if h > top then top = h end
		end
	end
	w.lone = (count == 1) and lone or false
	w.loneTop = top
	w.loneEpoch = epoch
end

-- One step of the lone body b, or false if it might touch something.
local function loneStep(w, b, t, P)
	local dt, g = t.dt, t.g
	local vx, vy, vz, wx, wy, wz = b.vx, b.vy, b.vz, b.wx, b.wy, b.wz
	local r = b.radius
	-- after the forces: |v| grows by at most g dt; the gyroscopic step turns
	-- the spin and changes its size by far less than half
	local avz = vz < 0 and -vz or vz
	local spin = sqrt(wx * wx + wy * wy + wz * wz) * 1.5 * r
	local low = b.z - r - t.margin - LONE_SLACK
	-- the ground: every point is above the ground contact margin
	if low <= (avz + g * dt + spin) * dt then return false end
	-- the pairs: higher than every other body's bounding sphere by the reach
	if low - w.loneTop <= (sqrt(vx * vx + vy * vy + vz * vz) + g * dt + spin) * dt then return false end
	local pc, pt
	if P then pc = P.clock; pt = pc() end
	-- 1. forces
	w.awakeCount = 1
	b.vz = vz - g * dt
	if w.windOn and b == w.projectile and not w.firstContact then windForce(w, b, dt) end
	if t.gyro then gyro(b, dt) end
	b.groundImpulse = 0
	b.plough = 0   -- in the air: as the full step does for a body off the ground
	-- 2-4. no contacts
	C.n = 0
	w.contacts = 0
	nRec = 0
	-- 5. integrate
	local h = 0.5 * dt
	b.x, b.y, b.z = b.x + b.vx * dt, b.y + b.vy * dt, b.z + b.vz * dt
	local qw, qx, qy, qz = b.qw, b.qx, b.qy, b.qz
	wx, wy, wz = b.wx, b.wy, b.wz
	local dw = -(wx * qx + wy * qy + wz * qz)
	local dx = wx * qw + wy * qz - wz * qy
	local dy = wy * qw + wz * qx - wx * qz
	local dz = wz * qw + wx * qy - wy * qx
	qw, qx, qy, qz = qw + h * dw, qx + h * dx, qy + h * dy, qz + h * dz
	local qn = sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
	if qn < 1e-12 then
		qw, qx, qy, qz = 1, 0, 0, 0
	else
		qn = 1 / qn
		qw, qx, qy, qz = qw * qn, qx * qn, qy * qn, qz * qn
	end
	b.qw, b.qx, b.qy, b.qz = qw, qx, qy, qz
	local xx, yy, zz = qx * qx, qy * qy, qz * qz
	local xy, xz, yz = qx * qy, qx * qz, qy * qz
	local xw, yw, zw = qw * qx, qw * qy, qw * qz
	local r11, r12, r13 = 1 - 2 * (yy + zz), 2 * (xy - zw), 2 * (xz + yw)
	local r21, r22, r23 = 2 * (xy + zw), 1 - 2 * (xx + zz), 2 * (yz - xw)
	local r31, r32, r33 = 2 * (xz - yw), 2 * (yz + xw), 1 - 2 * (xx + yy)
	b.r11, b.r12, b.r13, b.r21, b.r22, b.r23, b.r31, b.r32, b.r33 = r11, r12, r13, r21, r22, r23, r31, r32, r33
	local ia, ic, ie = b.iIx, b.iIy, b.iIz
	b.i11 = r11 * r11 * ia + r12 * r12 * ic + r13 * r13 * ie
	b.i12 = r11 * r21 * ia + r12 * r22 * ic + r13 * r23 * ie
	b.i13 = r11 * r31 * ia + r12 * r32 * ic + r13 * r33 * ie
	b.i22 = r21 * r21 * ia + r22 * r22 * ic + r23 * r23 * ie
	b.i23 = r21 * r31 * ia + r22 * r32 * ic + r23 * r33 * ie
	b.i33 = r31 * r31 * ia + r32 * r32 * ic + r33 * r33 * ie
	-- 6-8. nothing to relax, bounce or store; the tail for b (no ground
	-- impulse: no rolling resistance, and it cannot fall asleep)
	w.time = w.time + dt
	w.steps = w.steps + 1
	w.loneStep = w.steps
	if b.dig > 0 then
		b.dig = b.dig * exp(-dt / w.surface.digTime)
		if b.dig < 1e-5 then b.dig = 0 end
	end
	local sinTopple = sin(rad(t.toppleDeg))
	if b.shape == 1 and not b.toppled and r33 <= sinTopple and r33 >= -sinTopple then b.toppled = true; b.toppleT = w.time end
	local x, y = b.x, b.y
	local half, len, om = t.pitchHalfWidth, t.pitchLength, t.outMargin
	if x > half + om or x < -(half + om) or y < -om or y > len + om then b.leftPitch = true end
	b.sleepTime = 0
	if P then P.lone = P.lone + pc() - pt end
	return true
end

function world.step(w)
	local t = world.tune
	local P = world.prof
	if world.loneFlight then
		if w.loneEpoch ~= epoch then loneRefresh(w) end
		local b = w.lone
		if b and loneStep(w, b, t, P) then return w end
	end
	local dt = t.dt
	local invDt = 1 / dt
	local surf = w.surface
	local bodies, nb = w.bodies, w.n
	local stamp = w.steps
	local pc, pt
	if P then pc = P.clock; pt = pc() end
	local g = t.g

	-- 1. forces
	local awakeCount = 0
	local useGyro = t.gyro
	local windOn = w.windOn and not w.firstContact
	local proj = w.projectile
	for i = 1, nb do
		local b = bodies[i]
		if b.awake then
			awakeCount = awakeCount + 1
			b.vz = b.vz - g * dt
			if windOn and b == proj then windForce(w, b, dt) end
			if useGyro then gyro(b, dt) end
			b.groundImpulse = 0
		end
	end
	w.awakeCount = awakeCount

	if P then local now = pc(); P.forces = P.forces + now - pt; pt = now end
	-- 2. contacts: pairs, then the ground
	C.n = 0
	-- per body: position, radius, awake and the speed bound of any of its
	-- points (for the speculative margin)
	for i = 1, nb do
		local b = bodies[i]
		BX[i], BY[i], BZ[i], BR[i] = b.x, b.y, b.z, b.radius
		local aw = b.awake
		AW[i] = aw
		if aw then
			local vx, vy, vz, wx, wy, wz = b.vx, b.vy, b.vz, b.wx, b.wy, b.wz
			SPD[i] = sqrt(vx * vx + vy * vy + vz * vz) + sqrt(wx * wx + wy * wy + wz * wz) * b.radius
		else
			SPD[i] = 0
		end
	end
	-- NXT[k]: the first awake body at k or after (nb + 1: none), so a
	-- sleeping body's pairs jump from one awake partner to the next
	local nxt = nb + 1
	for k = nb, 1, -1 do
		if AW[k] then nxt = k end
		NXT[k] = nxt
	end
	local tmargin = t.margin
	local wakeLin2, wakeAng2 = t.wakeLin * t.wakeLin, t.wakeAng * t.wakeAng
	local nWoke = 0
	for i = 1, nb do
		local sa = SPD[i]
		local ax, ay, az, ar = BX[i], BY[i], BZ[i], BR[i]
		local j = i + 1
		while j <= nb do
			if not AW[i] then j = NXT[j] end
			if j > nb then break end
			do
				local margin = tmargin + (sa + SPD[j]) * dt
				local dx, dy, dz = ax - BX[j], ay - BY[j], az - BZ[j]
				local reach = ar + BR[j] + margin
				if dx * dx + dy * dy + dz * dz < reach * reach then
					local a, b = bodies[i], bodies[j]
					local before = C.n
					if P then P.narrow = P.narrow + 1 end
					if a.shape == 1 then
						if b.shape == 1 then boxBox(a, b, margin)
						else capsuleBox(b, a, margin) end
					else
						if b.shape == 1 then capsuleBox(a, b, margin)
						else capsuleCapsule(a, b, margin) end
					end
					if C.n > before then
						-- wake a sleeper that an awake, moving body touches
						local o, s = nil, 0
						if not a.awake and not a.static then
							if b.vx * b.vx + b.vy * b.vy + b.vz * b.vz > wakeLin2
								or b.wx * b.wx + b.wy * b.wy + b.wz * b.wz > wakeAng2
								or b.wokeStep == stamp then o, s = a, i end
						elseif not b.awake and not b.static then
							if a.vx * a.vx + a.vy * a.vy + a.vz * a.vz > wakeLin2
								or a.wx * a.wx + a.wy * a.wy + a.wz * a.wz > wakeAng2
								or a.wokeStep == stamp then o, s = b, j end
						end
						if o then
							epoch = epoch + 1
							o.awake = true
							o.everAwake = true
							o.sleepTime = 0
							o.vz = o.vz - g * dt
							o.groundImpulse = 0
							AW[s] = true
							local vx, vy, vz, wx, wy, wz = o.vx, o.vy, o.vz, o.wx, o.wy, o.wz
							SPD[s] = sqrt(vx * vx + vy * vy + vz * vz) + sqrt(wx * wx + wy * wy + wz * wz) * o.radius
							for k = s, 1, -1 do
								if NXT[k] > s then NXT[k] = s else break end
							end
							-- the group it rests against wakes with it (below)
							o.wokeStep = stamp
							nWoke = nWoke + 1
							WK[nWoke] = s
							WLO[nWoke] = (s == i) and j or s
							WT[s] = i * (nb + 1) + j
							WPOS[s] = nWoke
						end
					end
				end
			end
			j = j + 1
		end
	end
	-- A body woken this step wakes every sleeper it touches, and so on through
	-- the group (Jamie, 2026-11-15: a baton bounced off four field kubbs
	-- standing in a tight row). A sleeper is immovable to the solver, so a
	-- kubb woken by a blow and leaning on a sleeping neighbour stood braced
	-- against a wall for that step: the blow went into the wall and was gone,
	-- and the neighbour woke a step later to nothing. The loop above wakes
	-- the pairs it still comes to (wokeStep); these are the pairs it had
	-- already passed while both slept. Two bodies both woken this step, or a
	-- woken body and a stake, can also be a pair the loop passed while neither
	-- was awake (a baton wakes two kubbs that touch each other): their contact
	-- is made here too, once, so they do not sink into each other for a step
	-- (Codex on the web game's sync). WT is where the pair loop was when a
	-- body woke (past its end for one woken here): a pair it came to before
	-- both of those was skipped. WPOS is a body's place in the queue; the
	-- earlier of two woken bodies makes their contact. Nothing runs here in a
	-- step that wakes nobody.
	if nWoke > 0 then
		local q = 1
		while q <= nWoke do
			local s, lo = WK[q], WLO[q]
			local o = bodies[s]
			local ts = WT[s]
			for k = 1, nb do
				if k ~= s and (AW[k] or bodies[k].static) then
					-- awake already, or a stake: only the contact, nobody wakes
					local c = bodies[k]
					local pt = (k < s) and (k * (nb + 1) + s) or (s * (nb + 1) + k)
					local skipped = ts > pt
					if skipped and not c.static then
						skipped = c.wokeStep == stamp and WT[k] > pt and WPOS[k] > q
					end
					if skipped then
						local margin = tmargin + (SPD[s] + SPD[k]) * dt
						local dx, dy, dz = BX[s] - BX[k], BY[s] - BY[k], BZ[s] - BZ[k]
						local reach = BR[s] + BR[k] + margin
						if dx * dx + dy * dy + dz * dz < reach * reach then
							local a, b = o, c
							if k < s then a, b = c, o end
							if P then P.narrow = P.narrow + 1 end
							if a.shape == 1 then
								if b.shape == 1 then boxBox(a, b, margin)
								else capsuleBox(b, a, margin) end
							else
								if b.shape == 1 then capsuleBox(a, b, margin)
								else capsuleCapsule(a, b, margin) end
							end
						end
					end
				elseif k ~= s and k < lo then
					local c = bodies[k]
					do
						local margin = tmargin + SPD[s] * dt
						local dx, dy, dz = BX[s] - BX[k], BY[s] - BY[k], BZ[s] - BZ[k]
						local reach = BR[s] + BR[k] + margin
						if dx * dx + dy * dy + dz * dz < reach * reach then
							local a, b = o, c
							if k < s then a, b = c, o end
							local before = C.n
							if P then P.narrow = P.narrow + 1 end
							if a.shape == 1 then
								if b.shape == 1 then boxBox(a, b, margin)
								else capsuleBox(b, a, margin) end
							else
								if b.shape == 1 then capsuleBox(a, b, margin)
								else capsuleCapsule(a, b, margin) end
							end
							if C.n > before then
								epoch = epoch + 1
								c.awake = true
								c.everAwake = true
								c.sleepTime = 0
								c.vz = c.vz - g * dt
								c.groundImpulse = 0
								c.wokeStep = stamp
								AW[k] = true
								local vx, vy, vz, wx, wy, wz = c.vx, c.vy, c.vz, c.wx, c.wy, c.wz
								SPD[k] = sqrt(vx * vx + vy * vy + vz * vz) + sqrt(wx * wx + wy * wy + wz * wz) * c.radius
								nWoke = nWoke + 1
								WK[nWoke] = k
								WLO[nWoke] = nb + 1
								WT[k] = (nb + 1) * (nb + 1)
								WPOS[k] = nWoke
							end
						end
					end
				end
			end
			q = q + 1
		end
	end
	if P then local now = pc(); P.pairs = P.pairs + now - pt; pt = now end
	local nPair = C.n
	for i = 1, nb do
		local b = bodies[i]
		if b.awake then
			local nvz = -b.vz
			if nvz < 0 then nvz = 0 end
			local wx, wy, wz = b.wx, b.wy, b.wz
			local margin = tmargin + nvz * dt + sqrt(wx * wx + wy * wy + wz * wz) * b.radius * dt
			if b.shape == 1 then groundBox(b, margin) else groundCapsule(b, margin) end
		end
	end
	if P then local now = pc(); P.ground = P.ground + now - pt; pt = now end
	local n = C.n
	w.contacts = n

	-- 3. prepare: one record per contact with an awake body
	local slop, pushRate, maxPush = t.slop, t.pushRate, t.maxPush
	local warmF, pairMu, pairE = t.warm, t.pairMu, t.pairE
	local boxMu = t.boxMu
	local m = 0
	for i = 1, n do
		local a, b = cA[i], cB[i]
		local nx, ny, nz = cNx[i], cNy[i], cNz[i]
		if not a.awake then
			-- A is asleep: if B is awake, make B the dynamic side
			if b and b.awake then
				a, b = b, a
				nx, ny, nz = -nx, -ny, -nz
			else
				a = nil
			end
		end
		if a and b and not b.awake then b = false end
		if a then
			m = m + 1
			local r = REC[m]
			if not r then r = {}; REC[m] = r end
			r[K_A], r[K_B], r[K_IDX] = a, b, i
			local px, py, pz = cPx[i], cPy[i], cPz[i]
			local ax, ay, az = a.x, a.y, a.z
			local rax, ray, raz = px - ax, py - ay, pz - az
			local ima = a.im
			local i11, i12, i13, i22, i23, i33 = a.i11, a.i12, a.i13, a.i22, a.i23, a.i33
			local avx, avy, avz, awx, awy, awz = a.vx, a.vy, a.vz, a.wx, a.wy, a.wz
			local sep = cSep[i]
			local bias, relax
			if sep > 0 then
				bias, relax = -sep * invDt, -sep * invDt
			elseif sep < -slop then
				bias = pushRate * (-sep - slop) * invDt
				if bias > maxPush then bias = maxPush end
				relax = 0
			else
				bias, relax = 0, 0
			end
			r[K_BIAS], r[K_RELAX] = bias, relax
			r[K_LT1], r[K_LT2] = 0, 0
			r[K_LNMAX] = 0
			if i > nPair then
				-- the ground: n = +z, t1 = +x, t2 = +y. (ra x d) and I^-1 (ra x d)
				-- with the zero terms left out.
				r[K_KIND] = 1
				r[K_NX], r[K_NY], r[K_NZ] = 0, 0, 1
				r[K_T1X], r[K_T1Y], r[K_T1Z], r[K_T2X], r[K_T2Y], r[K_T2Z] = 1, 0, 0, 0, 1, 0
				-- n: j = (ray, -rax, 0)
				local jx, jy = ray, -rax
				local wx, wy, wz = i11 * jx + i12 * jy, i12 * jx + i22 * jy, i13 * jx + i23 * jy
				r[K_ANX], r[K_ANY], r[K_ANZ], r[K_WANX], r[K_WANY], r[K_WANZ] = jx, jy, 0, wx, wy, wz
				local kn = ima + (jx * wx + jy * wy)
				-- t1: j = (0, raz, -ray)
				jy = raz
				local jz = -ray
				wx, wy, wz = i12 * jy + i13 * jz, i22 * jy + i23 * jz, i23 * jy + i33 * jz
				r[K_A1X], r[K_A1Y], r[K_A1Z], r[K_WA1X], r[K_WA1Y], r[K_WA1Z] = 0, jy, jz, wx, wy, wz
				local k1 = ima + (jy * wy + jz * wz)
				-- t2: j = (-raz, 0, rax)
				jx, jz = -raz, rax
				wx, wy, wz = i11 * jx + i13 * jz, i12 * jx + i23 * jz, i13 * jx + i33 * jz
				r[K_A2X], r[K_A2Y], r[K_A2Z], r[K_WA2X], r[K_WA2Y], r[K_WA2Z] = jx, 0, jz, wx, wy, wz
				local k2 = ima + (jx * wx + jz * wz)
				local mn = 1 / kn
				r[K_MN], r[K_MT1], r[K_MT2] = mn, 1 / k1, 1 / k2
				local anx, any = r[K_ANX], r[K_ANY]
				local v0 = avz + awx * anx + awy * any
				r[K_V0] = v0
				-- surface friction and bounce, dig, warm start
				local k = cSlot[i]
				local mu, e = surf.mu, surf.e
				local dig
				local ln, l1, l2 = 0, 0, 0
				if a.gStamp[k] == stamp - 1 then
					dig = a.gDig[k]
					ln, l1, l2 = a.gN[k] * warmF, a.gT1[k] * warmF, a.gT2[k] * warmF
				else
					-- a new contact: how steeply and how fast did it arrive?
					dig = 0
					-- the ground texture: this patch's values (a hash of the
					-- patch and the throw's seed; five numbers in -1..1)
					local tex = surf.texture
					local u1, u2, u3, u4, u5 = 0, 0, 0, 0, 0
					if tex then
						-- (math.floor: a true integer; // leaves a float, which the
						-- device's 32-bit Lua will not take into & and >>)
						local cx, cy = floor(px / tex.cell), floor(py / tex.cell)
						local hh = (cx * 0x1B873593 + cy * 0x5BD1E995 + w.groundSeed) & 0xffffffff
						hh = ((hh ~ (hh >> 15)) * 0x2C1B3C6D) & 0xffffffff
						hh = ((hh ~ (hh >> 12)) * 0x297A2D39) & 0xffffffff
						hh = hh ~ (hh >> 15)
						local h2 = ((hh * 0x85EBCA6B) & 0xffffffff) ~ (hh >> 13)
						u1, u2, u3 = (hh & 1023) / 511.5 - 1, ((hh >> 10) & 1023) / 511.5 - 1, ((hh >> 20) & 1023) / 511.5 - 1
						u4, u5 = (h2 & 1023) / 511.5 - 1, ((h2 >> 10) & 1023) / 511.5 - 1
						a.gMf[k], a.gEf[k] = 1 + tex.muVar * u1, 1 + tex.eVar * u2
						-- a bump: a steep landing is turned a little sideways, as off a
						-- patch tilted a few degrees (the travel only: applied at the
						-- contact point it gave an edge landing a wild spin)
						-- (scaled by how steeply it comes in: a low skidding drill is
						-- barely turned, a baton dropping end first is)
						if v0 < -tex.bumpSpeed then
							local vt1 = avx + awy * raz - awz * ray
							local vt2 = avy + awz * rax - awx * raz
							local steep = -v0 / sqrt(v0 * v0 + vt1 * vt1 + vt2 * vt2)
							local k = -v0 * tex.bump * steep * steep * a.bumpGain
							avx, avy = avx + k * u4, avy + k * u5
							a.vx, a.vy = avx, avy
						end
					else
						a.gMf[k], a.gEf[k] = 1, 1
					end
					-- (a drilled kubb, digBySpin false, is judged by its centre's
					-- arrival: its spin sweeps the edge sideways but does not make
					-- it skim, so a spinning drill digs in as a plain one does)
					local va = v0
					if not a.digBySpin then va = avz end
					if va < -surf.digSpeed and surf.dig > 0 then
						local steep
						if a.digBySpin then
							local vt1 = avx + awy * raz - awz * ray
							local vt2 = avy + awz * rax - awx * raz
							steep = -v0 / sqrt(v0 * v0 + vt1 * vt1 + vt2 * vt2)
						else
							steep = -avz / sqrt(avx * avx + avy * avy + avz * avz)
						end
						local ramp = (-va - surf.digSpeed) / surf.digRamp
						if ramp > 1 then ramp = 1 end
						dig = surf.dig * steep * ramp * pointed(a) * a.digGain
						if tex then dig = dig * (1 + tex.digVar * u3) end
						local lever = surf.digLever * min(1, dig)
						if lever > a.dig then a.dig = lever end
					end
				end
				a.gDig[k] = dig
				r[K_MU] = mu * (1 + dig) * a.gMf[k]
				local ef = 1 - dig
				if ef < 0 then ef = 0 end
				r[K_E] = e * ef * a.gEf[k]
				r[K_LN], r[K_LT1], r[K_LT2] = ln, l1, l2
				-- warm start (n = +z, t1 = +x, t2 = +y)
				if ln > 0 or l1 ~= 0 or l2 ~= 0 then
					a.vx, a.vy, a.vz = avx + ima * l1, avy + ima * l2, avz + ima * ln
					a.wx = awx + ln * r[K_WANX] + l1 * r[K_WA1X] + l2 * r[K_WA2X]
					a.wy = awy + ln * r[K_WANY] + l1 * r[K_WA1Y] + l2 * r[K_WA2Y]
					a.wz = awz + ln * r[K_WANZ] + l1 * r[K_WA1Z] + l2 * r[K_WA2Z]
				end
			else
				r[K_NX], r[K_NY], r[K_NZ] = nx, ny, nz
				-- tangents
				local t1x, t1y, t1z
				if nx < 0.57 and nx > -0.57 then
					t1x, t1y, t1z = 0, nz, -ny
				else
					t1x, t1y, t1z = nz, 0, -nx
				end
				local l = 1 / sqrt(t1x * t1x + t1y * t1y + t1z * t1z)
				t1x, t1y, t1z = t1x * l, t1y * l, t1z * l
				local t2x, t2y, t2z = ny * t1z - nz * t1y, nz * t1x - nx * t1z, nx * t1y - ny * t1x
				r[K_T1X], r[K_T1Y], r[K_T1Z], r[K_T2X], r[K_T2Y], r[K_T2Z] = t1x, t1y, t1z, t2x, t2y, t2z
				-- A's angular terms for n, t1, t2
				local jx, jy, jz = ray * nz - raz * ny, raz * nx - rax * nz, rax * ny - ray * nx
				local wx = i11 * jx + i12 * jy + i13 * jz
				local wy = i12 * jx + i22 * jy + i23 * jz
				local wz = i13 * jx + i23 * jy + i33 * jz
				r[K_ANX], r[K_ANY], r[K_ANZ], r[K_WANX], r[K_WANY], r[K_WANZ] = jx, jy, jz, wx, wy, wz
				local kn = ima + (jx * wx + jy * wy + jz * wz)
				jx, jy, jz = ray * t1z - raz * t1y, raz * t1x - rax * t1z, rax * t1y - ray * t1x
				wx = i11 * jx + i12 * jy + i13 * jz
				wy = i12 * jx + i22 * jy + i23 * jz
				wz = i13 * jx + i23 * jy + i33 * jz
				r[K_A1X], r[K_A1Y], r[K_A1Z], r[K_WA1X], r[K_WA1Y], r[K_WA1Z] = jx, jy, jz, wx, wy, wz
				local k1 = ima + (jx * wx + jy * wy + jz * wz)
				jx, jy, jz = ray * t2z - raz * t2y, raz * t2x - rax * t2z, rax * t2y - ray * t2x
				wx = i11 * jx + i12 * jy + i13 * jz
				wy = i12 * jx + i22 * jy + i23 * jz
				wz = i13 * jx + i23 * jy + i33 * jz
				r[K_A2X], r[K_A2Y], r[K_A2Z], r[K_WA2X], r[K_WA2Y], r[K_WA2Z] = jx, jy, jz, wx, wy, wz
				local k2 = ima + (jx * wx + jy * wy + jz * wz)
				local v0 = avx * nx + avy * ny + avz * nz
					+ awx * r[K_ANX] + awy * r[K_ANY] + awz * r[K_ANZ]
				if b then
					r[K_KIND] = 2
					local imb = b.im
					local j11, j12, j13, j22, j23, j33 = b.i11, b.i12, b.i13, b.i22, b.i23, b.i33
					local rbx, rby, rbz = px - b.x, py - b.y, pz - b.z
					kn, k1, k2 = kn + imb, k1 + imb, k2 + imb
					jx, jy, jz = rby * nz - rbz * ny, rbz * nx - rbx * nz, rbx * ny - rby * nx
					wx = j11 * jx + j12 * jy + j13 * jz
					wy = j12 * jx + j22 * jy + j23 * jz
					wz = j13 * jx + j23 * jy + j33 * jz
					r[K_BNX], r[K_BNY], r[K_BNZ], r[K_WBNX], r[K_WBNY], r[K_WBNZ] = jx, jy, jz, wx, wy, wz
					kn = kn + (jx * wx + jy * wy + jz * wz)
					jx, jy, jz = rby * t1z - rbz * t1y, rbz * t1x - rbx * t1z, rbx * t1y - rby * t1x
					wx = j11 * jx + j12 * jy + j13 * jz
					wy = j12 * jx + j22 * jy + j23 * jz
					wz = j13 * jx + j23 * jy + j33 * jz
					r[K_B1X], r[K_B1Y], r[K_B1Z], r[K_WB1X], r[K_WB1Y], r[K_WB1Z] = jx, jy, jz, wx, wy, wz
					k1 = k1 + (jx * wx + jy * wy + jz * wz)
					jx, jy, jz = rby * t2z - rbz * t2y, rbz * t2x - rbx * t2z, rbx * t2y - rby * t2x
					wx = j11 * jx + j12 * jy + j13 * jz
					wy = j12 * jx + j22 * jy + j23 * jz
					wz = j13 * jx + j23 * jy + j33 * jz
					r[K_B2X], r[K_B2Y], r[K_B2Z], r[K_WB2X], r[K_WB2Y], r[K_WB2Z] = jx, jy, jz, wx, wy, wz
					k2 = k2 + (jx * wx + jy * wy + jz * wz)
					v0 = v0 - (b.vx * nx + b.vy * ny + b.vz * nz)
						- (b.wx * r[K_BNX] + b.wy * r[K_BNY] + b.wz * r[K_BNZ])
				else
					r[K_KIND] = 3
				end
				r[K_MN], r[K_MT1], r[K_MT2] = 1 / kn, 1 / k1, 1 / k2
				r[K_V0] = v0
				if cA[i].shape == 1 and cB[i].shape == 1 then
					r[K_MU], r[K_E] = boxMu, pairE
				else
					r[K_MU], r[K_E] = pairMu, pairE
				end
				r[K_LN] = 0
			end
		end
	end
	nRec = m

	if P then local now = pc(); P.prepare = P.prepare + now - pt; pt = now end
	-- 4. solve with the push bias
	for _ = 1, t.iterations do solve(K_BIAS) end

	if P then local now = pc(); P.solve = P.solve + now - pt; pt = now end
	-- 5. integrate positions (quaternion step, normalize, rotation matrix and
	-- world inverse inertia: quat.integrate and body.updateDerived written out)
	local h = 0.5 * dt
	for i = 1, nb do
		local b = bodies[i]
		if b.awake then
			b.x, b.y, b.z = b.x + b.vx * dt, b.y + b.vy * dt, b.z + b.vz * dt
			local qw, qx, qy, qz = b.qw, b.qx, b.qy, b.qz
			local wx, wy, wz = b.wx, b.wy, b.wz
			local dw = -(wx * qx + wy * qy + wz * qz)
			local dx = wx * qw + wy * qz - wz * qy
			local dy = wy * qw + wz * qx - wx * qz
			local dz = wz * qw + wx * qy - wy * qx
			qw, qx, qy, qz = qw + h * dw, qx + h * dx, qy + h * dy, qz + h * dz
			local qn = sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
			if qn < 1e-12 then
				qw, qx, qy, qz = 1, 0, 0, 0
			else
				qn = 1 / qn
				qw, qx, qy, qz = qw * qn, qx * qn, qy * qn, qz * qn
			end
			b.qw, b.qx, b.qy, b.qz = qw, qx, qy, qz
			local xx, yy, zz = qx * qx, qy * qy, qz * qz
			local xy, xz, yz = qx * qy, qx * qz, qy * qz
			local xw, yw, zw = qw * qx, qw * qy, qw * qz
			local r11, r12, r13 = 1 - 2 * (yy + zz), 2 * (xy - zw), 2 * (xz + yw)
			local r21, r22, r23 = 2 * (xy + zw), 1 - 2 * (xx + zz), 2 * (yz - xw)
			local r31, r32, r33 = 2 * (xz - yw), 2 * (yz + xw), 1 - 2 * (xx + yy)
			b.r11, b.r12, b.r13, b.r21, b.r22, b.r23, b.r31, b.r32, b.r33 = r11, r12, r13, r21, r22, r23, r31, r32, r33
			local ia, ic, ie = b.iIx, b.iIy, b.iIz
			b.i11 = r11 * r11 * ia + r12 * r12 * ic + r13 * r13 * ie
			b.i12 = r11 * r21 * ia + r12 * r22 * ic + r13 * r23 * ie
			b.i13 = r11 * r31 * ia + r12 * r32 * ic + r13 * r33 * ie
			b.i22 = r21 * r21 * ia + r22 * r22 * ic + r23 * r23 * ie
			b.i23 = r21 * r31 * ia + r22 * r32 * ic + r23 * r33 * ie
			b.i33 = r31 * r31 * ia + r32 * r32 * ic + r33 * r33 * ie
		end
	end

	if P then local now = pc(); P.integrate = P.integrate + now - pt; pt = now end
	-- 6. relax: remove the push-apart speed
	for _ = 1, t.relaxIterations do solve(K_RELAX) end

	if P then local now = pc(); P.relax = P.relax + now - pt; pt = now end
	-- 7. restitution
	-- (several passes: a box landing flat has four corners, and one pass
	-- in order over them tips it and overshoots the bounce)
	local rs = t.restitutionSpeed
	local any = false
	for i = 1, m do
		local r = REC[i]
		if r[K_V0] < -rs and r[K_LNMAX] > 0 and r[K_E] > 0 then any = true break end
	end
	if any then
		for _ = 1, t.restitutionIterations do
			for i = 1, m do
				local r = REC[i]
				local v0 = r[K_V0]
				if v0 < -rs and r[K_LNMAX] > 0 and r[K_E] > 0 then
					local a, kind = r[K_A], r[K_KIND]
					local vn
					if kind == 1 then
						vn = a.vz + a.wx * r[K_ANX] + a.wy * r[K_ANY]
					else
						vn = a.vx * r[K_NX] + a.vy * r[K_NY] + a.vz * r[K_NZ]
							+ a.wx * r[K_ANX] + a.wy * r[K_ANY] + a.wz * r[K_ANZ]
						if kind == 2 then
							local b = r[K_B]
							vn = vn - (b.vx * r[K_NX] + b.vy * r[K_NY] + b.vz * r[K_NZ])
								- (b.wx * r[K_BNX] + b.wy * r[K_BNY] + b.wz * r[K_BNZ])
						end
					end
					local old = r[K_LN]
					local lam = old - r[K_MN] * (vn + r[K_E] * v0)
					if lam < 0 then lam = 0 end
					r[K_LN] = lam
					if lam ~= old then
						local d = lam - old
						local ima = a.im
						if kind == 1 then
							a.vz = a.vz + ima * d
						else
							local nx, ny, nz = r[K_NX], r[K_NY], r[K_NZ]
							a.vx, a.vy, a.vz = a.vx + ima * d * nx, a.vy + ima * d * ny, a.vz + ima * d * nz
							if kind == 2 then
								local b = r[K_B]
								local imb = b.im
								b.vx, b.vy, b.vz = b.vx - imb * d * nx, b.vy - imb * d * ny, b.vz - imb * d * nz
								b.wx, b.wy, b.wz = b.wx - d * r[K_WBNX], b.wy - d * r[K_WBNY], b.wz - d * r[K_WBNZ]
							end
						end
						a.wx, a.wy, a.wz = a.wx + d * r[K_WANX], a.wy + d * r[K_WANY], a.wz + d * r[K_WANZ]
					end
				end
			end
		end
	end

	if P then local now = pc(); P.restitution = P.restitution + now - pt; pt = now end
	-- 8. store ground impulses; touches
	local proj = w.projectile
	for i = 1, m do
		local r = REC[i]
		local idx = r[K_IDX]
		if r[K_KIND] == 1 then
			local a = r[K_A]
			local k = cSlot[idx]
			local ln = r[K_LN]
			a.gStamp[k], a.gN[k], a.gT1[k], a.gT2[k] = stamp, ln, r[K_LT1], r[K_LT2]
			a.groundImpulse = a.groundImpulse + ln
			if r[K_LNMAX] > 0 and a == proj and not w.firstContact then
				noteContact(w, a, nil, cPx[idx], cPy[idx], cPz[idx])
			end
		elseif r[K_LNMAX] > 0 then
			local other = cB[idx]
			local first = cA[idx]
			first.touched, other.touched = true, true
			-- the first moment each body is struck (render/burst: the burst and
			-- knock come at the impact); one test a contact, no arithmetic
			if not first.touchT then first.touchT = w.time end
			if not other.touchT then other.touchT = w.time end
			-- a drilled kubb that strikes a piece (not a stake: a wall rolls against
			-- the stake) has done its drill: drillOver below makes it a plain kubb
			if first.slipDrag and not other.static then first.drillHit = true end
			if other.slipDrag and not first.static then other.drillHit = true end
			if proj and not w.firstHit and (first == proj or other == proj) then
				noteContact(w, proj, (first == proj) and other or first, cPx[idx], cPy[idx], cPz[idx])
			end
		end
	end

	if P then local now = pc(); P.store = P.store + now - pt; pt = now end
	-- rolling resistance and dig, then sleep and bookkeeping
	w.time = w.time + dt
	w.steps = stamp + 1
	local sinTopple = sin(rad(t.toppleDeg))
	local half, len, om = t.pitchHalfWidth, t.pitchLength, t.outMargin
	local sleepLin2, sleepAng2, sleepTime = t.sleepLin * t.sleepLin, t.sleepAng * t.sleepAng, t.sleepTime
	for i = 1, nb do
		local b = bodies[i]
		if b.awake then
			local gi = b.groundImpulse
			if gi <= 0 then b.plough = 0 end   -- off the ground: the ploughed snow is left behind
			-- a drilled kubb is a plain kubb once its drill is over: it has struck
			-- a piece, or it is on the ground and nearly still (drill.tune
			-- settleV, settleW). Without this it rolled on like a log after a hit
			-- and rocked on its rounded edges for seconds before sleeping
			-- (Tyler's play test, 2026-11-15). Every other body: one test.
			if b.slipDrag and gi > 0 then
				local over = b.drillHit
				if not over then
					local dt_ = tw.drill.tune
					local sv, sw = dt_.settleV, dt_.settleW
					over = b.vx * b.vx + b.vy * b.vy + b.vz * b.vz < sv * sv
						and b.wx * b.wx + b.wy * b.wy + b.wz * b.wz < sw * sw
				end
				if over then
					b.edgeRound, b.slipDrag, b.rollDrag, b.plugGain = 0, false, 0, 1
					b.digBySpin, b.bumpGain, b.digGain = true, 1, 1
				end
			end
			if gi > 0 then
				if b.slipDrag then
					-- a drilled kubb: the plug (dig) holds its tumble and its turn but
					-- not its roll about the long axis (the turf brushes that: the
					-- texture drag below)
					local ux, uy, uz = b.r13, b.r23, b.r33
					local wx, wy, wz = b.wx, b.wy, b.wz
					local wu = wx * ux + wy * uy + wz * uz
					local px, py, pz = wx - wu * ux, wy - wu * uy, wz - wu * uz
					local L = b.dig * b.plugGain * gi
					local p2 = px * px + py * py + pz * pz
					if L > 0 and p2 > 1e-12 then
						local pn = sqrt(p2)
						local ex, ey, ez = px / pn, py / pn, pz / pn
						local ix = b.i11 * ex + b.i12 * ey + b.i13 * ez
						local iy = b.i12 * ex + b.i22 * ey + b.i23 * ez
						local iz = b.i13 * ex + b.i23 * ey + b.i33 * ez
						local stop = pn / (ex * ix + ey * iy + ez * iz)
						if L >= stop then
							wx, wy, wz = wu * ux, wu * uy, wu * uz
						else
							wx, wy, wz = wx - L * ix, wy - L * iy, wz - L * iz
						end
					end
					b.wx, b.wy, b.wz = wx, wy, wz
				elseif b.shape == 2 then
					-- a baton: its spin taken in two parts, each held by an angular
					-- impulse (lever times the ground's impulse), never past stopping
					-- that part: its end-over-end turn by the plug (dig) and
					-- batonTurnHold of the rolling resistance (surf.roll), its roll
					-- about the long axis by the plug and all of it. As one vector
					-- (rollResist) a spin with any part along the long axis, where
					-- the baton turns most easily, read as nearly stopped, and a
					-- baton landing on an end lost all of its spin in that step and
					-- went on without turning (Tyler's play test, 2026-11-15:
					-- "gliding"; tools/batonprobe.lua)
					local ux, uy, uz = b.r13, b.r23, b.r33
					local wx, wy, wz = b.wx, b.wy, b.wz
					local wu = wx * ux + wy * uy + wz * uz
					local px, py, pz = wx - wu * ux, wy - wu * uy, wz - wu * uz
					local i11, i12, i13, i22, i23, i33 = b.i11, b.i12, b.i13, b.i22, b.i23, b.i33
					-- (rolling resistance is the turf giving under its weight: it takes
					-- the ground's impulse up to rollCap times the weight a step, so the
					-- one hard step of a landing does not stop a turn the plug lets go)
					local gr = t.rollCap * b.m * t.g * dt
					if gi < gr then gr = gi end
					local L = b.dig * gi + t.batonTurnHold * surf.roll * gr
					local p2 = px * px + py * py + pz * pz
					if L > 0 and p2 > 1e-12 then
						local pn = sqrt(p2)
						local ex, ey, ez = px / pn, py / pn, pz / pn
						local ix = i11 * ex + i12 * ey + i13 * ez
						local iy = i12 * ex + i22 * ey + i23 * ez
						local iz = i13 * ex + i23 * ey + i33 * ez
						local stop = pn / (ex * ix + ey * iy + ez * iz)
						if L > stop then L = stop end
						wx, wy, wz = wx - L * ix, wy - L * iy, wz - L * iz
					end
					L = b.dig * gi + surf.roll * gr
					if L > 0 and (wu > 1e-9 or wu < -1e-9) then
						local ix = i11 * ux + i12 * uy + i13 * uz
						local iy = i12 * ux + i22 * uy + i23 * uz
						local iz = i13 * ux + i23 * uy + i33 * uz
						local stop = wu / (ux * ix + uy * iy + uz * iz)
						if stop < 0 then stop = -stop end
						if L > stop then L = stop end
						if wu < 0 then L = -L end
						wx, wy, wz = wx - L * ix, wy - L * iy, wz - L * iz
					end
					b.wx, b.wy, b.wz = wx, wy, wz
				else
					rollResist(b, b.dig, gi)
				end
				local tex = surf.texture
				if tex then
					local r33 = b.r33
					if r33 < 0 then r33 = -r33 end
					local vx, vy = b.vx, b.vy
					local v2 = vx * vx + vy * vy
					if v2 > 1e-8 then
						if r33 > COS_END then
							-- upright on an end and sliding: a baton's foot catches and it
							-- tips toward the way it is going (axis z x v)
							if b.shape == 2 and v2 > tex.tripSpeed * tex.tripSpeed then
								local k = tex.trip * dt
								b.wx, b.wy = b.wx - k * vy, b.wy + k * vx
							elseif b.shape == 1 and not b.slipDrag then
								-- a kubb (or the king) standing and sliding: its foot catches
								-- too. The turf holds the slip of the point under its centre:
								-- that share of the slip is taken away there, which slows the
								-- piece and tips it the way it is going
								local ft = tex.foot
								if ft then
									local h = b.z
									local wx, wy = b.wx, b.wy
									local sx, sy = vx - h * wy, vy + h * wx
									local s2 = sx * sx + sy * sy
									if s2 > tex.footSpeed * tex.footSpeed then
										local pl = tex.plough
										if pl then
											local d = b.plough + sqrt(s2) * dt
											b.plough = d
											ft = ft + pl * d
										end
										ft = ft * dt
										if ft > 1 then ft = 1 end
										local im = b.im
										local jx = -ft * sx / (im + h * h * b.i22)
										local jy = -ft * sy / (im + h * h * b.i11)
										-- r = (0, 0, -h): r x J = (h jy, -h jx, 0)
										local tx, ty = h * jy, -h * jx
										b.vx, b.vy = vx + im * jx, vy + im * jy
										b.wx = wx + b.i11 * tx + b.i12 * ty
										b.wy = wy + b.i12 * tx + b.i22 * ty
										b.wz = b.wz + b.i13 * tx + b.i23 * ty
									end
								end
							end
						elseif b.slipDrag then
							-- a drilled kubb: the blades hold the slip of its lowest
							-- point (under the centre, at the ground), not its roll. The
							-- impulse that takes that share of the slip away, applied there
							local h = b.z
							local wx, wy = b.wx, b.wy
							local sx, sy = vx - h * wy, vy + h * wx
							local s2 = sx * sx + sy * sy
							local f = tex.drag
							if s2 < tex.gripSpeed * tex.gripSpeed then f = f + tex.grip end
							local pl = tex.plough
							if pl then
								local d = b.plough + sqrt(s2) * dt
								b.plough = d
								f = f + pl * d
							end
							f = f * dt
							if f > 1 then f = 1 end
							local im = b.im
							local jx = -f * sx / (im + h * h * b.i22)
							local jy = -f * sy / (im + h * h * b.i11)
							-- r = (0, 0, -h): r x J = (h jy, -h jx, 0)
							local tx, ty = h * jy, -h * jx
							b.vx, b.vy = vx + im * jx, vy + im * jy
							wx = wx + b.i11 * tx + b.i12 * ty
							wy = wy + b.i12 * tx + b.i22 * ty
							local wz = b.wz + b.i13 * tx + b.i23 * ty
							-- and the blades brush its roll about the long axis: rollDrag of
							-- the drag (viscous: a faster roll is held harder)
							local ux, uy, uz = b.r13, b.r23, b.r33
							local k = -b.rollDrag * tex.drag * dt * (wx * ux + wy * uy + wz * uz)
							b.wx, b.wy, b.wz = wx + k * ux, wy + k * uy, wz + k * uz
						elseif b.shape == 2 or r33 < 0.5 then
							-- a baton or a lying piece on grass: the blades hold it,
							-- harder once it is slow, so it stops instead of creeping
							-- (in snow, harder the farther it has ploughed)
							local f = tex.drag
							if v2 < tex.gripSpeed * tex.gripSpeed then f = f + tex.grip end
							local pl = tex.plough
							if pl then
								local d = b.plough + sqrt(v2) * dt
								b.plough = d
								f = f + pl * d
							end
							f = 1 - f * dt
							if f < 0 then f = 0 end
							b.vx, b.vy = vx * f, vy * f
							b.wx, b.wy, b.wz = b.wx * f, b.wy * f, b.wz * f
						end
					end
				end
			end
			if b.dig > 0 then
				b.dig = b.dig * exp(-dt / surf.digTime)
				if b.dig < 1e-5 then b.dig = 0 end
			end
			local r33 = b.r33
			if b.shape == 1 and not b.toppled and r33 <= sinTopple and r33 >= -sinTopple then b.toppled = true; b.toppleT = w.time end
			local x, y = b.x, b.y
			if x > half + om or x < -(half + om) or y < -om or y > len + om then b.leftPitch = true end
			local vx, vy, vz, wx, wy, wz = b.vx, b.vy, b.vz, b.wx, b.wy, b.wz
			if vx * vx + vy * vy + vz * vz < sleepLin2 and wx * wx + wy * wy + wz * wz < sleepAng2 and gi > 0 then
				b.sleepTime = b.sleepTime + dt
				if b.sleepTime >= sleepTime then
					epoch = epoch + 1
					b.awake = false
					b.vx, b.vy, b.vz, b.wx, b.wy, b.wz = 0, 0, 0, 0, 0, 0
					b.dig = 0
					-- the leaner rule: a piece that comes to rest propped on another is
					-- down if it would fall with the prop taken away
					if b.shape == 1 and not b.toppled and body.wouldFall(b) then b.toppled = true; b.toppleT = w.time end
				end
			else
				b.sleepTime = 0
			end
		end
	end
	if P then local now = pc(); P.tail = P.tail + now - pt end
	return w
end


-- Everything asleep (or the throw ran past tune.maxTime).
function world.isAtRest(w)
	if w.time >= world.tune.maxTime then return true end
	-- the body found awake last time is the likely one (the projectile is
	-- added last, so the plain scan would walk past every sleeper first)
	local bodies = w.bodies
	local h = w.awakeHint
	if h and bodies[h] and bodies[h].awake then return false end
	for i = 1, w.n do
		if bodies[i].awake then
			w.awakeHint = i
			return false
		end
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
		-- a piece still moving when the throw ran out of time gets the leaner rule here
		if b.shape == 1 and not b.static and not b.toppled and body.wouldFall(b) then b.toppled = true; b.toppleT = w.time end
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
