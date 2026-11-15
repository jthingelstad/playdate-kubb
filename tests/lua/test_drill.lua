-- Drilling a kubb (core/drill, world.launchDrill): the solved launch lands on
-- the marker, the swing's power, smoothness and cut move it the right ways,
-- and a drilled kubb that ends short or out goes through the toss rules.
-- Real physics on grass; tolerances, not exact numbers (the device runs
-- 32-bit floats).
import "core/drill"
import "core/world"
import "core/match"
import "core/outcome"
local drill, world, match = tw.drill, tw.world, tw.match

local sqrt, abs = math.sqrt, math.abs

-- One drill at the marker (mx, my) from the baseline at y = 0 on an empty
-- pitch. `r` is a swing result (power defaults to the band center).
-- groundSeed: the ground texture's seed (nil: the throw's own, as in play)
local function throwAt(mx, my, r, cut, pieces, groundSeed)
	local sol = drill.solve(mx, my, 0)
	r = r or {}
	local sr = { power = r.power or sol.band, smoothness = r.smoothness or 1,
		tilt = r.tilt or 90 * (1 - (r.smoothness or 1)), pull = r.pull }
	local L = drill.launch(sol, sr, cut or drill.CUT_NONE)
	local w = world.new { surface = "grass", stakes = false, pieces = pieces, groundSeed = groundSeed }
	local b = world.launchDrill(w, "p", sol.x, 0, L.swivel, L.loft, L.speed, L.noseDown, L.rollLand,
		L.spin, L.wobble, L.digGain)
	world.run(w)
	local fc = w.firstContact
	return { sol = sol, land = fc, rest = b, b = b, L = L, w = w }
end

local function dist(ax, ay, bx, by) return sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

local MARKERS = {
	near = { { 0, 4.2 }, { 1.2, 4.5 }, { -1.5, 4.8 } },
	middle = { { 0, 6 }, { 1.5, 5.5 }, { -2, 6.5 } },
	far = { { 0, 8 }, { -2, 7.5 }, { 1, 8.4 } },
}
local CLEAN_TOL = 0.35 -- m: a clean in-band drill rests this close to the marker

test("drill: a clean in-band swing rests near the marker, near, middle and far", function()
	for name, list in pairs(MARKERS) do
		for _, m in ipairs(list) do
			local t = throwAt(m[1], m[2])
			local e = dist(t.rest.x, t.rest.y, m[1], m[2])
			expect.truthy(e < CLEAN_TOL, string.format("%s marker (%.1f, %.1f): rests %.2f m off", name, m[1], m[2], e))
		end
	end
end)

test("drill: the band edges stay close; under-power lands short and over-power long", function()
	for _, m in ipairs { { 0, 4.5 }, { 1, 6 }, { -1, 7.5 } } do
		local sol = drill.solve(m[1], m[2], 0)
		local edge = throwAt(m[1], m[2], { power = sol.band + drill.tune.bandHalf })
		expect.truthy(dist(edge.rest.x, edge.rest.y, m[1], m[2]) < 0.6, "the top of the band still lands near")
		local short = throwAt(m[1], m[2], { power = sol.band - 0.2 })
		local long = throwAt(m[1], m[2], { power = math.min(1, sol.band + 0.15) })
		expect.truthy(short.land.y < m[2] - 0.7, string.format("short lands %.2f before %.1f", short.land.y, m[2]))
		expect.truthy(long.land.y > m[2] + 0.4, string.format("long lands %.2f past %.1f", long.land.y, m[2]))
		expect.eq(drill.judge(sol.band - 0.2, sol.band), "short")
		expect.eq(drill.judge(sol.band + 0.15, sol.band), "long")
		expect.eq(drill.judge(sol.band + 0.03, sol.band), "on")
	end
end)

test("drill: a farther marker needs more power and the band leaves room to throw long", function()
	local a = drill.solve(0, 4, 0)
	local b = drill.solve(0, 6, 0)
	local c = drill.solve(0, 8.6, 0)
	expect.truthy(a.band < b.band and b.band < c.band, "band grows with distance")
	expect.truthy(c.band + drill.tune.bandHalf < 1, "full power is past the farthest band")
	expect.truthy(a.speed < b.speed and b.speed < c.speed, "speed grows with distance")
end)

test("drill: regular (A) and goofy (B) cuts curve opposite ways", function()
	-- On the textured grass the cut is reliable but not certain, as on a real
	-- lawn: over twelve grounds at each marker, A ends right of B at least
	-- nine times in ten and they part by 8 cm or more on average (with the
	-- grass texture of 2026-11-14: 59 of 60, 17 cm). Each cut also curls its
	-- own way on average.
	for _, m in ipairs { { 0, 5 }, { 0.5, 6.5 }, { -1, 8 } } do
		local right, sep, sa, sb, n = 0, 0, 0, 0, 0
		for seed = 1, 12 do
			local straight = throwAt(m[1], m[2], nil, nil, nil, seed)
			local a = throwAt(m[1], m[2], nil, drill.CUT_A, nil, seed)
			local b = throwAt(m[1], m[2], nil, drill.CUT_B, nil, seed)
			local da, db = a.rest.x - straight.rest.x, b.rest.x - straight.rest.x
			if da > db then right = right + 1 end
			sep, sa, sb, n = sep + (da - db), sa + da, sb + db, n + 1
		end
		local where = string.format("(%.1f, %.1f)", m[1], m[2])
		expect.truthy(right >= 0.9 * n, string.format("A right of B at %s: %d of %d", where, right, n))
		expect.truthy(sep / n > 0.08, string.format("A and B part by %.3f m at %s", sep / n, where))
		expect.truthy(sa / n > 0 and sb / n < 0, string.format("A %+.3f, B %+.3f m at %s", sa / n, sb / n, where))
	end
end)

test("drill: a clean drill dies near its landing; a jerky one runs on farther", function()
	local clean, jerky, n = 0, 0, 0
	for _, list in pairs(MARKERS) do
		for _, m in ipairs(list) do
			local c = throwAt(m[1], m[2])
			local sc = dist(c.rest.x, c.rest.y, c.land.x, c.land.y)
			expect.truthy(sc < 0.45, string.format("clean drill at (%.1f, %.1f) slides %.2f m", m[1], m[2], sc))
			clean = clean + sc
			for _, pull in ipairs { 1, -1 } do
				local j = throwAt(m[1], m[2], { smoothness = 0.35, pull = pull })
				jerky = jerky + dist(j.rest.x, j.rest.y, j.land.x, j.land.y)
			end
			n = n + 1
		end
	end
	clean, jerky = clean / n, jerky / (2 * n)
	expect.truthy(jerky > 3 * clean and jerky > 0.5,
		string.format("jerky drills run on farther on average (clean %.2f m, jerky %.2f m)", clean, jerky))
end)

test("drill: the launch is from the baseline, the thrower behind the marker within the stakes", function()
	for _, m in ipairs { { 0, 5 }, { 2.9, 8 }, { -3, 4 } } do
		local mx, my = drill.clampMarker(m[1], m[2])
		local sol = drill.solve(mx, my, 0)
		expect.truthy(abs(sol.x) <= 2.5, "thrower inside the baseline")
		if abs(mx) <= drill.tune.throwerXMax then expect.near(sol.x, mx, 1e-9) end
		local L = drill.launch(sol, { power = sol.band, smoothness = 1, tilt = 0 }, 0)
		local s = { world.drillLaunchState(sol.x, 0, L.swivel, L.loft, L.speed, L.noseDown, L.rollLand, L.spin, L.wobble) }
		expect.near(s[2], 0, 1e-9, "released over the baseline")
		expect.truthy(s[9] > 0, "moving downfield")
		-- the long axis points forward and down the line of flight
		local qw, qx, qy, qz = s[4], s[5], s[6], s[7]
		local az = 1 - 2 * (qx * qx + qy * qy)
		expect.near(math.deg(math.asin(-az)), drill.tune.noseDownDeg, 1e-6, "nose down")
	end
	-- the marker area stays a little past the legal half
	local x, y = drill.clampMarker(10, 20)
	expect.truthy(x > 2.5 and y > 8, "the hard way stays possible")
	x, y = drill.clampMarker(-10, 0)
	expect.truthy(x < -2.5 and y < 4, "short of the middle line too")
end)

test("drill: the baton and lob launches are unchanged by the drill's ground flags", function()
	local w = world.new { surface = "grass", stakes = false }
	for _, b in ipairs { world.launchKubb(w, "p", 0, 0, 0, 40, 6.5, 3), world.launchBaton(w, 0, 0, 0, 30, 8, 5, 0) } do
		expect.eq(b.digGain, 1); expect.eq(b.edgeRound, 0); expect.eq(b.bumpGain, 1)
		expect.truthy(b.digBySpin and not b.slipDrag, "a plain body")
	end
	local d = world.launchDrill(w, "d", 0, 0, 0, 47, 7, 15, -15, 22, 0, 25)
	expect.eq(d.edgeRound, drill.tune.edgeRound); expect.truthy(not d.digBySpin and d.slipDrag, "a drilled kubb")
end)

-- ---------- the attitude and the planned spin (core/throwplan's drill) ----------

import "core/throwplan"
local plan = tw.plan

-- The plan's clean drill onto (mx, my) at a loft with `taps` of spin: the
-- centre at the first touch, the rest, and whether the nose touched first.
local function planDrill(mx, my, loft, taps, surface, seed, pieces)
	local sol = drill.solveAt(mx, my, 0, loft, {})
	local L = drill.body(1, 1, taps * plan.tune.spinPerStep, {})
	local w = world.new { surface = surface or "grass", groundSeed = seed, pieces = pieces }
	local b = world.launchDrill(w, "d", sol.x, 0, sol.swivel, sol.loft, sol.speed, L.noseDown, L.rollLand,
		L.spin, L.wobble, L.digGain)
	local land, noseDown, nose
	while not world.isAtRest(w) do
		local ax, ay, az = b.r13, b.r23, b.r33
		world.step(w)
		local fc = w.firstContact
		if fc and not land then
			land = { x = b.x, y = b.y }
			noseDown = math.deg(math.asin(-az))   -- the attitude in the step before the touch
			nose = (fc.x - b.x) * ax + (fc.y - b.y) * ay + (fc.z - b.z) * az
		end
	end
	return { land = land, rest = b, noseDown = noseDown, nose = nose, w = w }
end

local SPIN_MARKERS = { { -1, 4.8 }, { 0, 6 }, { 1, 7.2 } }
local SPIN_SEEDS = { 3, 7, 11 }

-- Mean sideways roll (rest x - landing x) and forward slide per tap.
local function perTap(loft, surface, taps)
	local side, fwd, n, worstFwd, wrong = 0, 0, 0, 0, 0
	for _, m in ipairs(SPIN_MARKERS) do
		for _, seed in ipairs(SPIN_SEEDS) do
			local t = planDrill(m[1], m[2], loft, taps, surface, seed)
			local dx, dy = t.rest.x - t.land.x, t.rest.y - t.land.y
			side, fwd, n = side + dx, fwd + dy, n + 1
			if abs(dy) > worstFwd then worstFwd = abs(dy) end
			if taps ~= 0 and dx * taps <= 0.03 then wrong = wrong + 1 end
			expect.truthy(abs(t.rest.r33) < 0.17, string.format("%d taps at (%.1f, %.1f) ends lying (axis %.2f)",
				taps, m[1], m[2], t.rest.r33))
		end
	end
	return side / n, fwd / n, worstFwd, wrong
end

test("drill: the kubb flies nose down and lands nose first, at every planned arc and spin", function()
	for _, loft in ipairs { 30, 47, 57 } do
		for _, taps in ipairs { 0, 3 } do
			local t = planDrill(0.5, 6, loft, taps, "grass", 5)
			expect.near(t.noseDown, drill.tune.noseDownDeg, 0.5,
				string.format("loft %d, %d taps: nose %.1f degrees down at the touch", loft, taps, t.noseDown))
			expect.truthy(t.nose > 0.03, string.format("loft %d, %d taps: first touch %.3f m ahead of the centre",
				loft, taps, t.nose))
		end
	end
end)

test("drill: planned spin rolls the kubb sideways, more with every tap, either way", function()
	-- measured on grass at loft 47 (tools/spinwall.lua, 2026-11-15): 0.27, 0.61, 0.90 m
	local lo = { [0] = -0.1, 0.15, 0.4, 0.7 }
	local hi = { [0] = 0.1, 0.4, 0.8, 1.15 }
	local last = -1
	for taps = 0, 3 do
		local side, fwd, worstFwd, wrong = perTap(47, "grass", taps)
		local where = string.format("loft 47, %d taps: side %.2f m, forward %.2f m (worst %.2f)", taps, side, fwd, worstFwd)
		expect.truthy(side >= lo[taps] and side <= hi[taps], where)
		expect.truthy(side > last, "more with every tap: " .. where)
		expect.truthy(worstFwd < (taps == 0 and 0.1 or 0.35), "the forward slide stays small: " .. where)
		expect.eq(wrong, 0, "every drill rolls the spin's way: " .. where)
		if taps > 0 then
			local back = perTap(47, "grass", -taps)
			expect.truthy(abs(back + side) < 0.15, string.format("-%d taps rolls %.2f m, +%d %.2f m", taps, back, taps, side))
		end
		last = side
	end
	-- a low arc (loft 30) too: monotone, about as far
	last = -1
	for taps = 1, 3 do
		local side = perTap(30, "grass", taps)
		expect.truthy(side > last + 0.1, string.format("loft 30, %d taps: %.2f m", taps, side))
		last = side
	end
	expect.truthy(last > 0.6 and last < 1.1, string.format("loft 30, 3 taps: %.2f m", last))
	-- sand holds it: about half as far
	local g3, s3 = perTap(47, "grass", 3), perTap(47, "sand", 3)
	expect.truthy(s3 > 0.3 * g3 and s3 < 0.7 * g3, string.format("sand %.2f m against grass %.2f m", s3, g3))
end)

test("drill: a rolling kubb stops against the stake and against a lying kubb", function()
	-- the stake at (2.5, 4): two taps from 0.45 m inward
	for _, seed in ipairs { 1, 2, 3 } do
		local t = planDrill(2.05, 4.03, 47, 2, "grass", seed)
		local b = t.rest
		expect.truthy(b.x < 2.5 - 0.03 and b.x > 2.5 - 0.08 and abs(b.y - 4) < 0.05,
			string.format("rests against the stake: (%.3f, %.3f)", b.x, b.y))
	end
	-- a kubb lying along the throw at (1, 5.5): two taps from 0.55 m to its left
	local h = math.sqrt(0.5)
	for _, seed in ipairs { 1, 2, 3 } do
		local k = { id = "k", kind = "kubb", x = 1, y = 5.5, z = 0.035, qw = h, qx = -h, qy = 0, qz = 0, toppled = true }
		local t = planDrill(0.45, 5.5, 47, 2, "grass", seed, { k })
		local b, q = t.rest, t.w.byId.k
		expect.truthy(b.x > 1 - 0.1 and b.x < 1 - 0.065, string.format("rests beside it: x %.3f", b.x))
		expect.truthy(dist(q.x, q.y, 1, 5.5) < 0.03, "the lying kubb stays put")
	end
end)

-- ---------- the rules path ----------

local function still(pieces)
	local r = { touched = {}, toppled = {}, kingToppled = false, bodies = {} }
	for _, p in ipairs(pieces) do
		r.bodies[p.id] = { kind = p.kind, x = p.x, y = p.y, z = p.toppled and 0.035 or 0.075,
			qw = p.qw, qx = p.qx, qy = p.qy, qz = p.qz, toppled = p.toppled }
	end
	return r
end

-- A drill from a match setup's own view frame: the real world, the setup's
-- pieces, the kubb launched as the throw scene launches it.
local function drillSetup(s, mx, my, power)
	local sol = drill.solve(mx, my, s.lineY)
	local L = drill.launch(sol, { power = power or sol.band, smoothness = 1, tilt = 0 }, 0)
	local w = world.new { surface = "grass", pieces = s.pieces }
	world.launchDrill(w, s.kubb, sol.x, s.lineY, L.swivel, L.loft, L.speed, L.noseDown, L.rollLand,
		L.spin, L.wobble, L.digGain)
	world.run(w)
	return world.result(w)
end

test("drill: drilled kubbs that end short or out are rethrown, then punished", function()
	local m = match.new {}
	local s = match.setup(m)
	local r = still(s.pieces)
	r.toppled[1] = "b1"; r.toppled[2] = "b2"
	for _, id in ipairs { "b1", "b2" } do
		local b = r.bodies[id]
		b.toppled, b.z, b.qw, b.qx, b.qy, b.qz = true, 0.035, math.cos(math.pi / 4), math.sin(math.pi / 4), 0, 0
		r.touched[#r.touched + 1] = id
	end
	match.resolve(m, r, false)
	-- the rest of the batons miss until the other team tosses
	s = match.setup(m)
	while s.kind == "baton" do
		match.resolve(m, still(s.pieces), false)
		s = match.setup(m)
	end
	expect.eq(s.kind, "toss")
	expect.eq(s.projectile, "kubb")
	-- under-powered at a marker just past the middle line: short of it
	local res = drillSetup(s, 0, s.lineY + 4.3, 0.1)
	local b = res.bodies[s.kubb]
	expect.truthy(b.y < 4, string.format("ends short of the middle line (%.2f)", b.y))
	match.resolve(m, res, false)
	expect.eq(m.text, "kubb out for now")
	-- clean onto a marker in the far half: in; the round is judged
	s = match.setup(m)
	res = drillSetup(s, 0.5, s.lineY + 6)
	match.resolve(m, res, false)
	expect.eq(m.text, "kubb out: rethrown")
	-- the rethrow, over-powered at the far baseline: out again
	s = match.setup(m)
	expect.truthy(s.rethrow, "the rethrow")
	res = drillSetup(s, -1, s.lineY + 8.3, 1)
	b = res.bodies[s.kubb]
	expect.truthy(b.y > 8, string.format("ends past the baseline (%.2f)", b.y))
	match.resolve(m, res, false)
	expect.eq(m.text, "out twice: punishment kubb")
end)
