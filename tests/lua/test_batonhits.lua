-- core/world and core/collide: how a baton meets a kubb and the ground
-- (Tyler's play test, 2026-11-15; tools/batonprobe.lua has the sweeps).
import "core/world"
import "core/collide"
import "core/throwplan"
import "core/quat"
local world, collide, plan, quat = tw.world, tw.collide, tw.plan, tw.quat
local sqrt, abs, deg, acos = math.sqrt, math.abs, math.deg, math.acos

-- a baton at a kubb 8 m out, planned for the carry `d` at `loft` (the probe's
-- throw), run to rest; returns the world, the baton, the kubb and the most
-- the kubb tilted
local function shot(loft, d, seed)
	local sol = plan.solve({ projectile = "baton", px = 0, py = 0, tx = 0, ty = d,
		release = plan.releaseFor(loft), level = "club" }, {})
	local w = world.new { surface = "grass", pieces = { { id = "k", kind = "kubb", x = 0, y = 8 } },
		groundSeed = seed or 1, stakes = false }
	local b = world.launchBaton(w, 0, 0, 0, loft, sol.speed, plan.tumbleFor(sol.speed, sol.loft), 0)
	local k = w.byId.k
	local maxTilt, air, touchV = 0, 0, nil
	while not world.isAtRest(w) and w.time < world.tune.maxTime do
		local v = sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
		world.step(w)
		if k.touchT and not touchV then touchV = v end
		local t = deg(acos(abs(k.r33) > 1 and 1 or abs(k.r33)))
		if t > maxTilt then maxTilt = t end
		local low = k.z - (k.hz * abs(k.r33) + k.hx * abs(k.r31) + k.hy * abs(k.r32))
		if touchV and low > 0.01 then air = air + world.tune.dt end
	end
	return w, b, k, maxTilt, air, touchV
end

test("baton hits: a baton meets a kubb's edges rounded (collide.tune.batonRound)", function()
	-- a baton lying across, its axis 3 mm inside the kubb's front face and
	-- just over the top: a square box gives the top face's normal, straight
	-- up; rounded, the normal leans out toward the baton
	local qw, qx, qy, qz = quat.fromAxisAngle(0, 1, 0, math.pi / 2)
	local w = world.new { texture = false, stakes = false, pieces = {
		{ id = "k", kind = "kubb", x = 0, y = 0 },
		{ id = "b", kind = "baton", x = 0, y = -0.032, z = 0.15 + 0.022 + 0.001, qw = qw, qx = qx, qy = qy, qz = qz },
	} }
	local k, b = w.byId.k, w.byId.b
	local C = collide.C
	local function normal()
		collide.reset()
		collide.capsuleBox(b, k, 0.01)
		expect.truthy(C.n >= 1, "a contact")
		return C.nx[1], C.ny[1], C.nz[1]
	end
	local _, ny, nz = normal()
	expect.truthy(ny < -0.1 and nz > 0.5, string.format("leans toward the baton: (%.2f, %.2f)", ny, nz))
	local keep = collide.tune.batonRound
	collide.tune.batonRound = 0
	local _, ny0, nz0 = normal()
	collide.tune.batonRound = keep
	expect.near(ny0, 0, 1e-9, "square: no lean")
	expect.near(nz0, 1, 1e-9, "square: straight up")
end)

-- Codex on PR #139: for a baton nearly parallel to the king's rounded edge
-- the projection that finds the closest point creeps, and stopped 5.9 mm
-- clear while an end was 2.3 mm in. The nearer end must be the contact.
test("baton hits: an end touching a rounded edge is a contact when the closest point is not", function()
	local sx, sy, sz, dx, dy, dz = -0.045, 0.063, -0.128, 0, 0.02, 0.2552175543
	local L = sqrt(dx * dx + dy * dy + dz * dz)
	local A = { hl = L / 2, r = 0.022, x = sx + dx / 2, y = sy + dy / 2, z = sz + dz / 2,
		r13 = dx / L, r23 = dy / L, r33 = dz / L, static = false }
	local B = { x = 0, y = 0, z = 0, r11 = 1, r12 = 0, r13 = 0, r21 = 0, r22 = 1, r23 = 0,
		r31 = 0, r32 = 0, r33 = 1, hx = 0.045, hy = 0.045, hz = 0.15 }
	local C = collide.C
	C.n = 0
	expect.truthy(collide.capsuleBox(A, B, 0.004), "found")
	local n = C.n
	C.n = 0
	expect.eq(n, 1, "one contact, at the end")
end)

test("baton hits: a fast baton that clips a kubb's top edge tips it over", function()
	-- loft 23 carried to 7.85 to 8.05 m: it lands just short and its tumbling
	-- end catches the kubb high; with square edges a fast one slid over and
	-- left it standing. Every touch faster than 6 m/s tips it. (Carried to
	-- 7.6 to 7.8 m until an impact's friction was solved in the bounce,
	-- 2026-11-16: the baton skipped off the grass into the kubb's top at 4 to
	-- 8 m/s; a skip keeps about half its speed now, 2 to 4 m/s. Measured: 20
	-- of 20 fast, all down.)
	local fast = 0
	for _, d in ipairs { 7.85, 7.90, 7.95, 8.00, 8.05 } do
		for seed = 1, 4 do
			local _, _, k, _, _, v = shot(23, d, seed)
			if v and v > 6 then
				fast = fast + 1
				expect.truthy(k.toppled, string.format("%.2f m, ground %d: a %.1f m/s touch, down", d, seed, v))
			end
		end
	end
	expect.truthy(fast >= 5, "fast touches: " .. fast)
end)

test("baton hits: struck kubbs seldom bounce back up, and some fly", function()
	-- 48 throws at one kubb across lofts and carries: few tilt past 25
	-- degrees and come back up. A struck kubb often leaves the ground: it
	-- pivots on its front edge and the blow throws it on over. Given the same
	-- baton states at a lone kubb on bare grass (no dig, no bite), MuJoCo
	-- keeps it off the ground 0.2 s or more in 47 of 60 hits, this engine in
	-- 43 (30 until the bounce reached the row, 2026-11-17: B's arm was taken
	-- at the baton's side of the gap, and the drag down the face held the
	-- kubb back; AGENTS.md, "The bounce reaches the row"). On the turf the
	-- dig and bite hold it down more: 16 of these 43 fly, and in the sweep
	-- (tools/batonprobe.lua) 4 bounce back and 260 of 725 fly (221 before).
	local touched, back, flew = 0, 0, 0
	for loft = 20, 47, 9 do
		for dd = -0.45, 0.31, 0.065 do
			local _, _, k, tilt, air, v = shot(loft, 8 + dd, 1)
			if v then
				touched = touched + 1
				if not k.toppled and tilt > 25 then back = back + 1 end
				if air >= 0.2 then flew = flew + 1 end
			end
		end
	end
	expect.truthy(touched >= 30, "touched " .. touched)
	expect.truthy(back <= 1, "bounced back " .. back)
	expect.truthy(flew <= 0.5 * touched, string.format("flew %d of %d", flew, touched))
end)

test("baton hits: a baton landing on an end keeps turning", function()
	-- loft 17 carried to 7.4 m lands on its leading end at 7.4 rad/s: before
	-- 2026-11-15 the whole spin was read as one and held to nothing in that
	-- one step; now the turn the landing gives it is kept
	local sol = plan.solve({ projectile = "baton", px = 0, py = 0, tx = 0, ty = 7.4,
		release = plan.releaseFor(17), level = "club" }, {})
	local w = world.new { surface = "grass", pieces = {}, groundSeed = 1, stakes = false }
	local b = world.launchBaton(w, 0, 0, 0, 17, sol.speed, plan.tumbleFor(sol.speed, sol.loft), 0)
	local before
	while not w.firstContact do
		before = sqrt(b.wx * b.wx + b.wy * b.wy + b.wz * b.wz)
		world.step(w)
	end
	expect.truthy(abs(b.r33) > 0.7, "on an end")
	local after = sqrt(b.wx * b.wx + b.wy * b.wy + b.wz * b.wz)
	expect.truthy(after > 0.3 * before, string.format("spin %.1f -> %.1f rad/s", before, after))
end)
