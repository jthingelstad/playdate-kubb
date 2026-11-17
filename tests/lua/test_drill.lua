-- Drilling a kubb (core/drill, world.launchDrill): the solved launch lands on
-- the marker, the swing's power, smoothness and cut move it the right ways,
-- and a drilled kubb that ends short or out goes through the toss rules.
-- Real physics on grass; tolerances, not exact numbers (the device runs
-- 32-bit floats). Since 2026-11-16 a drill turns in the air and runs on from
-- where it lands, a different way every throw, so most checks are averages
-- over several seeded grounds.
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
		L.spin, L.wobble)
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
-- A clean drill does not stop where it lands (2026-11-16): it runs on, a
-- different way every throw, and is aimed short by how far it runs on on
-- average (drill.slideFor). So over several grounds it rests about on the
-- marker, never all of them there.
local GROUNDS = {}
for g = 1, 30 do GROUNDS[g] = 7 * g + 3 end

test("drill: a clean in-band swing rests about on the marker on average, near, middle and far", function()
	for name, list in pairs(MARKERS) do
		for _, m in ipairs(list) do
			local along, far, n = 0, 0, 0
			for _, g in ipairs(GROUNDS) do
				local t = throwAt(m[1], m[2], nil, nil, nil, g)
				local ux, uy = math.sin(t.sol.swivel), math.cos(t.sol.swivel)
				along = along + (t.rest.x - m[1]) * ux + (t.rest.y - m[2]) * uy
				far = far + dist(t.rest.x, t.rest.y, m[1], m[2])
				n = n + 1
			end
			local where = string.format("%s marker (%.1f, %.1f)", name, m[1], m[2])
			-- (0.7 for an evening of 2026-11-16, while drill.tune.slide was measured with
			-- no air drag: far marks rested up to 0.53 m short. Measured again with it:
			-- -0.33 to +0.13 m along, 0.42 to 0.62 m off)
			expect.truthy(math.abs(along / n) < 0.45, string.format("%s: rests %+.2f m along on average", where, along / n))
			expect.truthy(far / n < 0.9, string.format("%s: rests %.2f m off on average", where, far / n))
		end
	end
end)

test("drill: the band edges stay close; under-power lands short and over-power long", function()
	for _, m in ipairs { { 0, 4.5 }, { 1, 6 }, { -1, 7.5 } } do
		local sol = drill.solve(m[1], m[2], 0)
		-- where they land, against the clean throw (the run on after is the
		-- ground's, not the swing's)
		local clean = throwAt(m[1], m[2])
		local edge = throwAt(m[1], m[2], { power = sol.band + drill.tune.bandHalf })
		expect.truthy(dist(edge.land.x, edge.land.y, clean.land.x, clean.land.y) < 0.3,
			"the top of the band still lands near")
		local short = throwAt(m[1], m[2], { power = sol.band - 0.2 })
		local long = throwAt(m[1], m[2], { power = math.min(1, sol.band + 0.15) })
		expect.truthy(short.land.y < clean.land.y - 0.5,
			string.format("short lands %.2f before %.2f", short.land.y, clean.land.y))
		expect.truthy(long.land.y > clean.land.y + 0.4,
			string.format("long lands %.2f past %.2f", long.land.y, clean.land.y))
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

test("drill: regular (A) and goofy (B) cuts spin the drill opposite ways", function()
	-- A cut is a spin about the long axis at release (cutSpin, + clockwise
	-- from behind), on top of the wrist's natural spiral. Since the drill is
	-- a plain body (2026-11-16) it does not curve the flight (a block spun
	-- about the way it flies gets almost no sideways push from the air) or
	-- roll the kubb a steady way on landing; it steadies the landing, as
	-- spin does (the spin tests below).
	local sol = drill.solve(0, 6, 0)
	local r = { power = sol.band, smoothness = 1, tilt = 0 }
	local a, b, n = drill.launch(sol, r, drill.CUT_A), drill.launch(sol, r, drill.CUT_B), drill.launch(sol, r, drill.CUT_NONE)
	expect.near(a.spin - n.spin, drill.tune.cutSpin, 1e-9)
	expect.near(n.spin - b.spin, drill.tune.cutSpin, 1e-9)
	expect.near(n.spin, drill.tune.spiral, 1e-9)
end)

test("drill: a clean drill runs on from where it lands, a different way each time; dead stops are rare", function()
	-- Jamie, 2026-11-16: "When thrown they just stop dead on the ground ...
	-- These would be rolling and wobbling a TON more." Over seeded grounds at
	-- every marker: it runs on 0.2 to 2.5 m on average (a low drill, loft 26
	-- to 30, lands fast: about 1.9 m with the plain body), spread out, almost
	-- never stops within 5 cm of where its centre was at the first touch, and
	-- often ends turned off the line of the throw. A jerky swing runs on too.
	local dead, n, s, ss, turned = 0, 0, 0, 0, 0
	local jerky, nj = 0, 0
	for _, list in pairs(MARKERS) do
		for _, m in ipairs(list) do
			for _, g in ipairs(GROUNDS) do
				local c = throwAt(m[1], m[2], nil, nil, nil, g)
				local d = dist(c.rest.x, c.rest.y, c.land.x, c.land.y)
				n, s, ss = n + 1, s + d, ss + d * d
				if d < 0.05 then dead = dead + 1 end
				-- the long axis more than 20 degrees off the line of the throw
				local ax, ay = abs(c.rest.r13), abs(c.rest.r23)
				if abs(c.rest.r33) < 0.866 and math.deg(math.atan(ax, ay)) > 20 then turned = turned + 1 end
			end
			local j = throwAt(m[1], m[2], { smoothness = 0.35, pull = 1 })
			jerky, nj = jerky + dist(j.rest.x, j.rest.y, j.land.x, j.land.y), nj + 1
		end
	end
	local mean = s / n
	local sd = math.sqrt(math.max(0, ss / n - mean * mean))
	expect.truthy(mean > 0.2 and mean < 2.5, string.format("runs on %.2f m on average", mean))
	expect.truthy(sd > 0.15, string.format("the run on spreads (sd %.2f m)", sd))
	expect.truthy(dead <= 0.1 * n, string.format("dead stops %d of %d", dead, n))
	expect.truthy(turned >= 0.25 * n, string.format("ends turned off the line %d of %d", turned, n))
	expect.truthy(jerky / nj > 0.2, string.format("a jerky drill runs on %.2f m", jerky / nj))
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
		-- it leaves the hand nose forward and noseDownDeg down, pointing
		-- along the throw
		local qw, qx, qy, qz = s[4], s[5], s[6], s[7]
		local az = 1 - 2 * (qx * qx + qy * qy)
		expect.near(math.deg(math.asin(-az)), drill.tune.noseDownDeg, 1e-6, "nose down")
		local ax, ay = 2 * (qx * qz + qw * qy), 2 * (qy * qz - qw * qx)
		expect.near(math.atan(ax, ay), L.swivel, 1e-6, "pointing along the throw")
	end
	-- the marker area stays a little past the legal half
	local x, y = drill.clampMarker(10, 20)
	expect.truthy(x > 2.5 and y > 8, "the hard way stays possible")
	x, y = drill.clampMarker(-10, 0)
	expect.truthy(x < -2.5 and y < 4, "short of the middle line too")
end)

test("drill: a drilled kubb is a plain body, like a baton or a lob, spun or not", function()
	-- Jamie, 2026-11-16: "we didn't treat Kubb throws with the same physics as
	-- baton throws". No ground flags of its own; the air's turn in flight only.
	local w = world.new { surface = "grass", stakes = false }
	local bodies = { world.launchKubb(w, "p", 0, 0, 0, 40, 6.5, 3), world.launchBaton(w, 0, 0, 0, 30, 8, 5, 0),
		world.launchDrill(w, "d", 0, 0, 0, 47, 7, 45, 0, 69, 0), world.launchDrill(w, "e", 0, 0, 0, 47, 7, 45, 0, 3, 0) }
	for _, b in ipairs(bodies) do
		expect.truthy(b.digGain == nil and b.edgeRound == nil and b.slipDrag == nil, "no ground flags of its own")
	end
	expect.eq(bodies[3].aeroK, world.tune.aeroK); expect.eq(bodies[4].aeroK, world.tune.aeroK)
end)

-- ---------- the attitude and the planned spin (core/throwplan's drill) ----------

import "core/throwplan"
local plan = tw.plan

-- The plan's clean drill onto (mx, my) at a loft with `taps` of spin: the
-- centre at the first touch, the rest, whether the nose touched first, and
-- the nose's angle below the horizontal at release and at the touch.
local function planDrill(mx, my, loft, taps, surface, seed, pieces)
	local sol = drill.solveAt(mx, my, 0, loft, {}, nil, surface or "grass", taps * plan.tune.spinPerStep)
	local L = drill.body(1, 1, taps * plan.tune.spinPerStep, {})
	local w = world.new { surface = surface or "grass", groundSeed = seed, pieces = pieces }
	local b = world.launchDrill(w, "d", sol.x, 0, sol.swivel, sol.loft, sol.speed, L.noseDown, L.rollLand,
		L.spin, L.wobble)
	local release = math.deg(math.asin(-b.r33))
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
	return { land = land, rest = b, noseDown = noseDown, nose = nose, w = w, release = release }
end

local SPIN_MARKERS = { { -1, 4.8 }, { 0, 6 }, { 1, 7.2 } }
local SPIN_SEEDS = { 3, 7, 11 }

test("drill: spin holds the drill's attitude to the touch; with little spin the air turns it", function()
	-- A spun drill is a gyroscope: with three taps it lands about as it left
	-- the hand (noseDownDeg) and nearly the same every time. With only the
	-- wrist's small natural spiral the air turns the long axis toward
	-- broadside to its fall, so it lands steeper and less the same, still
	-- nose first (Jamie: "Good drillers would never let a Kubb flip in the
	-- air"). Measured 2026-11-16: 3 taps 44 to 46 (sd about 5), none 60 to
	-- 69 (sd 10 to 15). With the air's drag and the later ground changes the
	-- unspun turn at half past 1 is small: 46 to 51 on average over 200
	-- grounds, sd about 20, so twelve grounds cannot tell it from the release
	-- there; it checks that it does not flatten, and the spread (below). At
	-- loft 30 it is still 61 to 64.
	for _, loft in ipairs { 30, 47 } do
		local sds = {}
		for _, taps in ipairs { 0, 3 } do
			local rel, s, ss, n, first = 0, 0, 0, 0, 0
			for seed = 1, 12 do
				local t = planDrill(0.5, 6, loft, taps, "grass", seed)
				rel, s, ss, n = rel + t.release, s + t.noseDown, ss + t.noseDown * t.noseDown, n + 1
				if t.nose > 0.03 then first = first + 1 end
			end
			local m = s / n
			local sd = math.sqrt(math.max(0, ss / n - m * m))
			sds[taps] = sd
			local where = string.format("loft %d, %d taps: release %.0f, touch %.1f (sd %.1f) degrees down, nose first %d of %d",
				loft, taps, rel / n, m, sd, first, n)
			expect.truthy(abs(rel / n - drill.tune.noseDownDeg) < 3, "released at noseDownDeg: " .. where)
			expect.truthy(first >= 0.9 * n, "nose first: " .. where)
			if taps == 0 then
				local steeper = loft < 40 and 5 or -3
				expect.truthy(m > drill.tune.noseDownDeg + steeper and m < 80, "the air turns it steeper: " .. where)
			else
				expect.truthy(abs(m - rel / n) < 5, "the spin holds the axis: " .. where)
				expect.truthy(sd < 7, "a spun drill lands about the same: " .. where)
			end
		end
		expect.truthy(sds[3] < sds[0], string.format("loft %d: spin steadies the touch (sd %.1f against %.1f)", loft, sds[3], sds[0]))
	end
end)

test("drill: spin moves a landed drill a little, either way; sand and snow hold it", function()
	-- Jamie, 2026-11-16: "in the real world spin does move the Kubb when it
	-- lands ... but at most it will move it one to three rotations". A square
	-- kubb that catches an edge keeps only a quarter of its spin as roll (its
	-- turn about the edge), and which corner strikes first decides the way,
	-- so spin moves it across a little and in no steady direction. Over
	-- three markers and twelve grounds with three taps either way: across
	-- under a turn of the kubb (28 cm) on average and never more than three.
	-- Sand holds it more than grass. (Three grounds until 2026-11-16: the
	-- mean of nine drills moved by 2 cm with any change to the ground and
	-- sat on the 28 cm line.)
	local ACROSS_SEEDS = {}
	for i = 1, 12 do ACROSS_SEEDS[i] = 4 * i - 1 end
	local function across(surface, taps)
		local side, worst, turns, n = 0, 0, 0, 0
		for _, m in ipairs(SPIN_MARKERS) do
			for _, seed in ipairs(ACROSS_SEEDS) do
				local t = planDrill(m[1], m[2], 47, taps, surface, seed)
				local dx = abs(t.rest.x - t.land.x)
				side, n = side + dx, n + 1
				if dx > worst then worst = dx end
			end
		end
		return side / n, worst
	end
	for _, taps in ipairs { 3, -3 } do
		local side, worst = across("grass", taps)
		local where = string.format("%d taps: across %.2f m on average, worst %.2f", taps, side, worst)
		expect.truthy(side < 0.28, where)
		expect.truthy(worst < 0.84, where)
	end
	local g3, s3 = across("grass", 3), across("sand", 3)
	expect.truthy(s3 < g3, string.format("sand %.2f m against grass %.2f m", s3, g3))
end)

test("drill: a drill into a lying kubb stops by it", function()
	-- a clean unspun drill landing just short of a lying kubb runs into it and
	-- mostly stops by it: the backstop the computer builds on. Not every ground:
	-- the run on is a different one every throw (before 2026-11-16 grounds 7 and 8
	-- of 10 went past it; with the air's drag and the run on measured again, only
	-- ground 1, 0.42 m past its centre; 87 of 100 grounds stop by it)
	local by = 0
	for seed = 1, 10 do
		local k = { id = "k", kind = "kubb", x = 0, y = 6.4, z = 0.035, qw = 1, qx = 0, qy = 0, qz = 0, toppled = true }
		local sol = drill.solveAt(0, 6.4, 0, 47, {}, nil, "grass", 0)
		local L = drill.body(1, 1, 0, {})
		local w = world.new { surface = "grass", groundSeed = seed, pieces = { k } }
		local b = world.launchDrill(w, "d", sol.x, 0, sol.swivel, sol.loft, sol.speed, L.noseDown, L.rollLand,
			L.spin, L.wobble)
		world.run(w)
		local q = w.byId.k
		if b.y < q.y + 0.35 then by = by + 1 end
		expect.truthy(dist(q.x, q.y, 0, 6.4) < 0.5, "the struck kubb moves a little")
	end
	expect.truthy(by >= 8, string.format("stops by it, not past, on %d of 10 grounds", by))
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
		L.spin, L.wobble)
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
