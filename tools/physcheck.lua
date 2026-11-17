-- The physics invariants that tools/physfuzz.lua checks after every step of a
-- throw, and tests/lua/test_physcases.lua checks on its pinned cases. Desktop
-- only: it reads the world after each world.step and adds nothing to the step
-- (the game never loads it). It calls core/collide's narrow phase with no
-- margin between steps; world.step clears that buffer before it uses it, so a
-- throw runs bit for bit the same with or without the checks (physfuzz
-- --selftest).
--
--   local physcheck = dofile("tools/physcheck.lua")   -- after core/world is imported
--   local mon = physcheck.monitor(w, { launchSpeed = v })
--   while not world.isAtRest(w) do world.step(w); mon:step() end
--   local findings = mon:finish()   -- { { check, sub, value, t, detail }, ... }
--
-- Checks (thresholds in physcheck.tune, each measured: docs/notes/physics-fuzz.md "Physics fuzz"):
--   energy       kinetic + potential never rises from one step to the next by
--                more than energyStep after the projectile's first contact
--                (in flight only gravity and the air act: flightStep), nor
--                climbs energyCum above its lowest since that contact
--   penetration  no piece stays deeper than penStep inside another piece or
--                the ground (penGround) for penHold, or ends any step deeper
--                than penDeep, and none is at rest deeper than
--                penRest / penRestGround
--   rest         everything sleeps before world.tune.maxTime; no piece creeps
--                (moves creepDist while slower than creepSpeed for creepTime)
--                or falls asleep and is woken again more than wakeCycles times
--   finite       no NaN or inf; no piece faster than the launch could make it,
--                spinning faster than spinMax, or far off the pitch
import "core/world"
import "core/throwplan"
local world, body, collide, plan, quat = tw.world, tw.body, tw.collide, tw.plan, tw.quat
local sqrt, abs, huge = math.sqrt, math.abs, math.huge

local physcheck = {}

physcheck.tune = {
	flightStep = 1e-6,   -- J a step the projectile may gain in free flight (rounding)
	energyStep = 0.005,  -- J a step after the first contact. The push apart (world.tune.pushRate)
	                     -- is a velocity, so it adds energy: an overlap at the 5 mm bar below
	                     -- pushes a baton off a kubb at 0.22 m/s, about 4 mJ. Below that a rise
	                     -- is the overlap's, and penetration counts it.
	energyCum = 0.020,   -- J above the lowest energy since the first contact
	penStep = 0.005,     -- m inside another piece ...
	penHold = 0.02,      -- s ... for this long (a frame at 50 fps: long enough to be seen) ...
	penDeep = 0.020,     -- m ... or this deep at the end of any one step
	penGround = 0.005,   -- m below the ground, held for penHold, or penDeep in one step
	penRest = 0.002,     -- m inside another piece at rest
	penRestGround = 0.002, -- m below the ground at rest
	creepSpeed = 0.1,    -- m/s: slower than this ...
	creepSpin = 1.0,     -- rad/s: ... and turning slower than this ...
	creepTime = 1.0,     -- s: ... for this long ...
	creepDist = 0.02,    -- m: ... and moved this far: it creeps
	wakeCycles = 3,      -- asleep and woken again more often than this: it jitters
	spinMax = 200,       -- rad/s
	speedGain = 1.25,    -- no piece faster than this times the fastest the launch could get ...
	speedExtra = 3,      -- ... plus this (m/s)
	farX = 12, farY0 = -6, farY1 = 20, farZ = 12, -- m: a centre past these has escaped
}

local C = collide.C

-- The deepest overlap (m, > 0 inside) of bodies a and b, or nil when they do
-- not touch. Uses core/collide with no margin.
local function pairDepth(a, b)
	C.n = 0
	if a.shape == 1 then
		if b.shape == 1 then collide.boxBox(a, b, 0) else collide.capsuleBox(b, a, 0) end
	else
		if b.shape == 1 then collide.capsuleBox(a, b, 0) else collide.capsuleCapsule(a, b, 0) end
	end
	local deep
	for i = 1, C.n do
		local d = -C.sep[i]
		if not deep or d > deep then deep = d end
	end
	C.n = 0
	return deep
end
physcheck.pairDepth = pairDepth

-- How far below the ground the body's lowest point is (m, > 0 below).
local function groundDepth(b)
	if b.shape == 1 then return -body.lowestZ(b) end
	return -(b.z - b.hl * abs(b.r33) - b.r)
end
physcheck.groundDepth = groundDepth

local function finite(v) return v == v and v ~= huge and v ~= -huge end

-- The deepest pair and ground overlaps in the world now. awakeOnly: only
-- pairs with an awake body (a step moves nothing else). over (optional):
-- every pair deeper than pairBar goes in over.pairs[i][j] = depth (i < j, or
-- j the static body), every body deeper than groundBar in over.ground[i].
local function deepest(w, awakeOnly, over, pairBar, groundBar)
	local bodies, n = w.bodies, w.n
	local pd, pa, pb, gd, gb = 0, nil, nil, 0, nil
	for i = 1, n do
		local a = bodies[i]
		if not a.static then
			if not awakeOnly or a.awake then
				local g = groundDepth(a)
				if g > gd then gd, gb = g, a end
				if over and g > groundBar then over.ground[i] = g end
			end
			for j = 1, n do
				local b = bodies[j]
				if j ~= i and (b.static or j > i) and (not awakeOnly or a.awake or b.awake) then
					local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
					local reach = a.radius + b.radius
					if dx * dx + dy * dy + dz * dz < reach * reach then
						local d = pairDepth(a, b)
						if d and d > pd then pd, pa, pb = d, a, b end
						if over and d and d > pairBar then
							local row = over.pairs[i]
							if not row then row = {}; over.pairs[i] = row end
							row[j] = d
						end
					end
				end
			end
		end
	end
	return pd, pa, pb, gd, gb
end
physcheck.deepest = deepest

local function pairName(a, b)
	local x, y = a.kind, b.kind
	if x > y then x, y = y, x end
	return x .. "-" .. y
end

-- The fastest the launch can make anything go: the launch speed, plus what
-- falling from the hand to the ground adds.
local function speedLimit(v0)
	local t = physcheck.tune
	local h = tw.flight.tune.handHeight + 1
	return t.speedGain * sqrt(v0 * v0 + 2 * world.tune.g * h) + t.speedExtra
end

-- A monitor for world w (opts.launchSpeed: the projectile's launch speed).
function physcheck.monitor(w, opts)
	opts = opts or {}
	local t = physcheck.tune
	local m = {
		w = w, worst = {}, order = {},
		e = world.energy(w), eMin = nil, pairRuns = {}, groundRuns = {}, over = {}, seenAwake = {},
		vMax = speedLimit(opts.launchSpeed or 10),
		slow = {}, asleep = {}, cycles = {},
	}
	local function note(check, sub, value, detail)
		local key = check .. "|" .. sub
		local f = m.worst[key]
		if not f then
			f = { check = check, sub = sub, value = value, t = w.time, detail = detail }
			m.worst[key] = f
			m.order[#m.order + 1] = key
		elseif value > f.value then
			f.value, f.t, f.detail = value, w.time, detail
		end
	end
	m.note = note
	for i = 1, w.n do m.asleep[i] = not w.bodies[i].awake end

	function m.step()
		-- finite, speed, spin, far
		local bodies = w.bodies
		for i = 1, w.n do
			local b = bodies[i]
			if b.awake then
				local ok = finite(b.x) and finite(b.y) and finite(b.z) and finite(b.vx) and finite(b.vy)
					and finite(b.vz) and finite(b.wx) and finite(b.wy) and finite(b.wz) and finite(b.qw)
				if not ok then
					note("finite", "nan " .. b.kind, 1, b.id .. " has a NaN or inf")
				else
					local v = sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
					if v > m.vMax then note("finite", "speed " .. b.kind, v - m.vMax,
						string.format("%s at %.1f m/s (limit %.1f)", b.id, v, m.vMax)) end
					local s = sqrt(b.wx * b.wx + b.wy * b.wy + b.wz * b.wz)
					if s > t.spinMax then note("finite", "spin " .. b.kind, s - t.spinMax,
						string.format("%s at %.0f rad/s", b.id, s)) end
					if b.x > t.farX or b.x < -t.farX or b.y < t.farY0 or b.y > t.farY1 or b.z > t.farZ then
						note("finite", "escape " .. b.kind, 1, string.format("%s at (%.1f, %.1f, %.1f)", b.id, b.x, b.y, b.z))
					end
				end
			end
		end
		-- energy
		local e = world.energy(w)
		local de = e - m.e
		if not w.firstContact then
			if de > t.flightStep then note("energy", "in flight", de,
				string.format("rose %.4f J in a step in flight", de)) end
		else
			if de > t.energyStep then note("energy", "a step", de,
				string.format("rose %.4f J in a step (%.4f -> %.4f)", de, m.e, e)) end
			if not m.eMin or e < m.eMin then m.eMin = e end
			local up = e - m.eMin
			if up > t.energyCum then note("energy", "climb", up,
				string.format("climbed %.4f J above its lowest since the first contact", up)) end
		end
		m.e = e
		-- penetration, pairs and ground that this step could move
		-- (an overlap over the bar counts once it has lasted penHold, or at once
		-- past penDeep: a one-step dip the next step pushes out is not seen)
		-- (per pair and per body: each overlap's own run, so overlaps of
		-- different pieces in successive steps are not added together)
		local over = m.over
		over.pairs, over.ground = {}, {}
		deepest(w, true, over, t.penStep, t.penGround)
		local hold, dt0 = t.penHold - 1e-9, world.tune.dt
		local runs = {}
		for i, row in pairs(over.pairs) do
			for j, d in pairs(row) do
				local key = i * 1024 + j
				local r = m.pairRuns[key]
				r = r and { t = r.t + dt0, max = r.max > d and r.max or d } or { t = dt0, max = d }
				runs[key] = r
				if r.t >= hold or d > t.penDeep then
					local a, b = bodies[i], bodies[j]
					note("penetration", "in a step " .. pairName(a, b), r.max,
						string.format("%s and %s %.1f mm deep, over %.0f mm for %.3f s", a.id, b.id, r.max * 1000,
							t.penStep * 1000, r.t))
				end
			end
		end
		m.pairRuns = runs
		local gruns = {}
		for i, d in pairs(over.ground) do
			local r = m.groundRuns[i]
			r = r and { t = r.t + dt0, max = r.max > d and r.max or d } or { t = dt0, max = d }
			gruns[i] = r
			if r.t >= hold or d > t.penDeep then
				local b = bodies[i]
				note("penetration", "in a step ground " .. b.kind, r.max,
					string.format("%s %.1f mm below the ground, over %.0f mm for %.3f s", b.id, r.max * 1000,
						t.penGround * 1000, r.t))
			end
		end
		m.groundRuns = gruns
		-- rest: creep and wake cycles
		local dt = world.tune.dt
		for i = 1, w.n do
			local b = bodies[i]
			if not b.static then
				-- (a reawakening: the monitor saw it awake in an earlier step; the
				-- first time a resting layout piece is struck is not a cycle)
				if b.awake and m.asleep[i] and m.seenAwake[i] then
					m.cycles[i] = (m.cycles[i] or 0) + 1
					if m.cycles[i] > t.wakeCycles then note("rest", "wake cycles " .. b.kind, m.cycles[i],
						string.format("%s fell asleep and woke %d times", b.id, m.cycles[i])) end
				end
				m.asleep[i] = not b.awake
				if b.awake then m.seenAwake[i] = true end
				local s = m.slow[i]
				if b.awake then
					local v2 = b.vx * b.vx + b.vy * b.vy + b.vz * b.vz
					local w2 = b.wx * b.wx + b.wy * b.wy + b.wz * b.wz
					if v2 < t.creepSpeed * t.creepSpeed and w2 < t.creepSpin * t.creepSpin then
						if not s then
							m.slow[i] = { x = b.x, y = b.y, z = b.z, t = 0 }
						else
							s.t = s.t + dt
							if s.t >= t.creepTime then
								local d = sqrt((b.x - s.x) ^ 2 + (b.y - s.y) ^ 2 + (b.z - s.z) ^ 2)
								if d > t.creepDist then note("rest", "creep " .. b.kind, d,
									string.format("%s moved %.1f cm in %.1f s while slow", b.id, d * 100, s.t)) end
							end
						end
					else
						m.slow[i] = nil
					end
				else
					m.slow[i] = nil
				end
			end
		end
	end

	-- After the run: at rest, the deepest overlaps of everything; and the time.
	function m.finish()
		if not world.isAtRest(w) or w.time >= world.tune.maxTime - 1e-9 then
			local awake = {}
			for i = 1, w.n do
				local b = w.bodies[i]
				if b.awake then
					awake[#awake + 1] = string.format("%s %.2f m/s", b.id, sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz))
				end
			end
			note("rest", "no rest", 1, "still moving at " .. world.tune.maxTime .. " s: " .. table.concat(awake, ", "))
		else
			local pd, pa, pb, gd, gb = deepest(w, false)
			if pd > t.penRest then note("penetration", "at rest " .. pairName(pa, pb), pd,
				string.format("%s rests %.1f mm inside %s", pa.id, pd * 1000, pb.id)) end
			if gd > t.penRestGround then note("penetration", "at rest ground " .. gb.kind, gd,
				string.format("%s rests %.1f mm below the ground", gb.id, gd * 1000)) end
		end
		local out = {}
		for _, k in ipairs(m.order) do out[#out + 1] = m.worst[k] end
		return out
	end
	return m
end

-- ---------- worlds and throws from plain data (physfuzz, pinned cases) ----------

-- A piece reflected in the plane x = 0 (the pitch's middle line along the
-- throw): x -> -x, the pose turned the mirror's way (q -> qw, qx, -qy, -qz).
function physcheck.mirrorPiece(p)
	local m = {}
	for k, v in pairs(p) do m[k] = v end
	m.x = -(p.x or 0)
	if p.qw then m.qy, m.qz = -p.qy, -p.qz else m.yaw = -(p.yaw or 0) end
	return m
end

-- A world for `pieces` (each { id, kind, x, y, z?, qw..qz? | yaw, toppled? }).
-- opts: groundSeed (fixed), texture (false: flat), stakes (false: none),
-- mirror (true: every piece and stake reflected in x = 0, in the same order).
-- Without mirror the same world as world.new{ surface, pieces, ... }.
function physcheck.newWorld(surface, pieces, opts)
	opts = opts or {}
	local w = world.new { surface = surface, groundSeed = opts.groundSeed, texture = opts.texture, stakes = false }
	if opts.stakes ~= false then
		if opts.mirror then
			local h, r = world.tune.stakeHeight, tw.pitch.stakeRadius
			for i, s in ipairs(tw.pitch.stakes) do
				local b = world.addBody(w, "stake", "stake" .. i)
				b.r, b.hl, b.radius = r, h / 2 - r, h / 2
				body.setPose(b, -s.x, s.y, h / 2, 1, 0, 0, 0)
				b.awake = false
			end
		else
			world.addStakes(w)
		end
	end
	for _, p in ipairs(pieces) do world.addPiece(w, opts.mirror and physcheck.mirrorPiece(p) or p) end
	return w
end

-- The projectile's launch as plain data: kind, id, the 13 numbers of
-- world.launch, aeroK (a drill's) and the world's ground seed.
function physcheck.capture(w)
	local b = w.projectile
	return { kind = b.kind, id = b.id, aeroK = b.aeroK, groundSeed = w.groundSeed, exact = true,
		b.x, b.y, b.z, b.qw, b.qx, b.qy, b.qz, b.vx, b.vy, b.vz, b.wx, b.wy, b.wz }
end

-- Launch state st (physcheck.capture) into w. opts.mirror reflects it in
-- x = 0 (st.exact: the pose as captured, bit for bit); opts.scale multiplies its velocity and spin (the chaos probe).
function physcheck.launch(w, st, opts)
	opts = opts or {}
	local x, y, z, qw, qx, qy, qz, vx, vy, vz, wx, wy, wz = table.unpack(st, 1, 13)
	if opts.mirror then x, qy, qz, vx, wy, wz = -x, -qy, -qz, -vx, -wy, -wz end
	local k = opts.scale or 1
	if k ~= 1 then vx, vy, vz, wx, wy, wz = vx * k, vy * k, vz * k, wx * k, wy * k, wz * k end
	local b = world.launch(w, st.kind, st.id, x, y, z, qw, qx, qy, qz, vx, vy, vz, wx, wy, wz)
	b.aeroK = st.aeroK
	if st.exact then
		-- a captured pose is already the normalized one: normalizing it again
		-- can move the last bit, so put it back as it was
		b.qw, b.qx, b.qy, b.qz = qw, qx, qy, qz
		body.updateDerived(b)
	end
	return b
end

-- A clean planned baton as a launch state: p = plan.solve's query
-- (projectile, px, py, tx, ty, release, level, aimZ), tumble times the plan's.
function physcheck.planState(p, tumble, id)
	local sol = plan.solve({ projectile = p.projectile or "baton", px = p.px, py = p.py, tx = p.tx, ty = p.ty,
		release = p.release, level = p.level or "club", aimZ = p.aimZ, surface = p.surface }, {})
	local st = { kind = "baton", id = id or "baton",
		world.batonLaunchState(p.px, p.py, sol.swivel, sol.loft, sol.speed, sol.tumble * (tumble or 1), p.tilt or 0) }
	return st, sol
end

-- Run a pinned case (tests/lua/physcases/*.lua): each throw in a fresh world
-- of the case's pieces. Returns { { result, findings, state }, ... }.
function physcheck.runCase(case)
	local out = {}
	for i, th in ipairs(case.throws) do
		local st = th.state or physcheck.planState(th.plan, th.tumble)
		local w = physcheck.newWorld(case.surface or "grass", case.pieces,
			{ groundSeed = th.groundSeed, stakes = case.stakes, texture = case.texture })
		local b = physcheck.launch(w, st)
		local v = math.sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
		local r, f = physcheck.run(w, { launchSpeed = v })
		out[i] = { result = r, findings = f, state = st }
	end
	return out
end

-- Run w to rest with a monitor; each(w) after every step if given.
-- Returns world.result and the findings.
function physcheck.run(w, opts, each)
	local mon = physcheck.monitor(w, opts)
	-- world.run's stop: at rest, or within 1e-9 s of maxTime
	local stop = world.tune.maxTime - 1e-9
	while not world.isAtRest(w) and w.time < stop do
		world.step(w)
		mon.step()
		if each then each(w) end
	end
	return world.result(w), mon.finish()
end

return physcheck
