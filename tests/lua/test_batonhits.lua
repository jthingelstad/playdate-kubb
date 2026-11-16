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

test("baton hits: a fast baton that clips a kubb's top edge tips it over", function()
	-- loft 23 carried to 7.6 to 7.8 m: it skips off the grass and catches the
	-- kubb's top; with square edges a fast one slid over and left it standing.
	-- Every touch faster than 6 m/s tips it. (One throw, 7.7 m on ground 1,
	-- until 2026-11-16: the landing bump's tilted patches decide how fast
	-- each skip arrives. Measured: 9 of 20 fast, all down.)
	local fast = 0
	for _, d in ipairs { 7.60, 7.65, 7.70, 7.75, 7.80 } do
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

test("baton hits: struck kubbs seldom bounce back up or fly", function()
	-- 48 throws at one kubb across lofts and carries: few tilt past 25
	-- degrees and come back up, and few leave the ground for 0.2 s or more
	-- (the full sweep, tools/batonprobe.lua: 3 bounce-backs and 140 of 747
	-- off the ground that long, against 8 and 168 before). Since the pair
	-- bounce is solved with the kubb's footing (2026-11-16) a kubb kicked at
	-- the foot keeps more of the kick: 9 of these 42 fly against 3, 277 of 764
	-- in the sweep against 162 (AGENTS.md, "The pair bounce with its footing")
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
	expect.truthy(flew <= 0.3 * touched, string.format("flew %d of %d", flew, touched))
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
