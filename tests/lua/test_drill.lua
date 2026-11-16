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
-- A clean drill does not stop where it lands (2026-11-16): it runs on, a
-- different way every throw, and is aimed short by how far it runs on on
-- average (drill.slideFor). So over several grounds it rests about on the
-- marker, never all of them there.
local GROUNDS = { 3, 7, 11, 19, 23, 29 }

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
		expect.truthy(short.land.y < clean.land.y - 0.7,
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

test("drill: regular (A) and goofy (B) cuts curve opposite ways", function()
	-- On the textured grass the cut is reliable but not certain, as on a real
	-- lawn: over twelve grounds at each marker, A ends right of B at least
	-- seven times in ten and they part by 8 cm or more on average (with the
	-- grass texture of 2026-11-14 and drills that stopped dead: 59 of 60,
	-- 17 cm; running on since 2026-11-16, the run's own scatter blurs it).
	-- Each cut also curls its own way on average.
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
		expect.truthy(right >= 0.7 * n, string.format("A right of B at %s: %d of %d", where, right, n))
		expect.truthy(sep / n > 0.08, string.format("A and B part by %.3f m at %s", sep / n, where))
		expect.truthy(sa / n > 0 and sb / n < 0, string.format("A %+.3f, B %+.3f m at %s", sa / n, sb / n, where))
	end
end)

test("drill: a clean drill runs on from where it lands, a different way each time; dead stops are rare", function()
	-- Jamie, 2026-11-16: "When thrown they just stop dead on the ground ...
	-- These would be rolling and wobbling a TON more." Over seeded grounds at
	-- every marker: it runs on 0.2 to 1.5 m on average, spread out, almost
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
	expect.truthy(mean > 0.2 and mean < 1.5, string.format("runs on %.2f m on average", mean))
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
		-- with no spin and no turn the long axis holds its attitude: forward
		-- and noseDownDeg down the line of flight
		local qw, qx, qy, qz = s[4], s[5], s[6], s[7]
		local az = 1 - 2 * (qx * qx + qy * qy)
		expect.near(math.deg(math.asin(-az)), drill.tune.noseDownDeg, 1e-6, "nose down")
		-- turning nose over in the air, it leaves the hand nose up
		local p = { world.drillLaunchState(sol.x, 0, L.swivel, L.loft, L.speed, L.noseDown, L.rollLand, L.spin,
			L.wobble, math.rad(drill.tune.pitchDps)) }
		local az2 = 1 - 2 * (p[5] * p[5] + p[6] * p[6])
		expect.truthy(math.deg(math.asin(-az2)) < -20, "nose up at release")
	end
	-- the marker area stays a little past the legal half
	local x, y = drill.clampMarker(10, 20)
	expect.truthy(x > 2.5 and y > 8, "the hard way stays possible")
	x, y = drill.clampMarker(-10, 0)
	expect.truthy(x < -2.5 and y < 4, "short of the middle line too")
end)

test("drill: the baton and lob launches are unchanged by the drill's ground flags; only a spun drill rolls", function()
	local w = world.new { surface = "grass", stakes = false }
	for _, b in ipairs { world.launchKubb(w, "p", 0, 0, 0, 40, 6.5, 3), world.launchBaton(w, 0, 0, 0, 30, 8, 5, 0) } do
		expect.eq(b.digGain, 1); expect.eq(b.edgeRound, 0); expect.eq(b.bumpGain, 1)
		expect.truthy(b.digBySpin and not b.slipDrag, "a plain body")
	end
	-- with planned spin the rolling body; without, a plain kubb on the ground
	local d = world.launchDrill(w, "d", 0, 0, 0, 47, 7, 15, -15, 22, 0, 1)
	expect.eq(d.edgeRound, drill.tune.edgeRound); expect.truthy(not d.digBySpin and d.slipDrag, "a spun drill")
	expect.eq(d.digGain, drill.tune.spinDigGain)
	local e = world.launchDrill(w, "e", 0, 0, 0, 47, 7, 15, -15, 0, 0, 1)
	expect.eq(e.edgeRound, 0); expect.eq(e.digGain, 1); expect.eq(e.bumpGain, 1)
	expect.truthy(e.digBySpin and not e.slipDrag, "an unspun drill is a plain kubb on the ground")
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
		L.spin, L.wobble, L.digGain)
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

test("drill: the kubb turns in the air: nose up at release, nose down at the touch", function()
	-- Jamie, 2026-11-16: "the Kubbs are still 'flying' flat ... They change
	-- angle in the air." Without spin it leaves the hand nose up along its
	-- flight and comes over; the touch is noseDownDeg on average and varies
	-- throw to throw. A fast spin holds the axis (a gyroscope): with three
	-- taps it leaves the hand about as it lands, and lands nearly the same
	-- every time.
	for _, loft in ipairs { 30, 47 } do
		for _, taps in ipairs { 0, 3 } do
			local rel, s, ss, n, first = 0, 0, 0, 0, 0
			for seed = 1, 12 do
				local t = planDrill(0.5, 6, loft, taps, "grass", seed)
				rel, s, ss, n = rel + t.release, s + t.noseDown, ss + t.noseDown * t.noseDown, n + 1
				if t.nose > 0.03 then first = first + 1 end
			end
			local m = s / n
			local sd = math.sqrt(math.max(0, ss / n - m * m))
			local where = string.format("loft %d, %d taps: release %.0f, touch %.1f (sd %.1f) degrees down, nose first %d of %d",
				loft, taps, rel / n, m, sd, first, n)
			-- (the touch is noseDownDeg for the swing's own turn; the scatter
			-- of the turn is not even about it)
			expect.truthy(abs(m - drill.tune.noseDownDeg) < 10, where)
			if taps == 0 then
				expect.truthy(rel / n < -25, "nose up at release: " .. where)
				expect.truthy(sd > 5, "the touch varies: " .. where)
				expect.truthy(first >= 0.5 * n, "mostly nose first: " .. where)
			else
				expect.truthy(abs(rel / n - m) < 5, "the spin holds the axis: " .. where)
				expect.truthy(sd < 3, "a spun drill lands the same: " .. where)
				expect.eq(first, n, "nose first: " .. where)
			end
		end
	end
end)

test("drill: planned spin rolls the kubb sideways, more with more taps, either way", function()
	-- Spun drills keep the rolling body (THE WALL). With the drill running on
	-- since 2026-11-16 the single tap is the least sure: on some grounds the
	-- bounce rolls it the wrong way. Two and three taps roll the spin's way.
	local sides = {}
	for taps = 0, 3 do
		local side, fwd, worstFwd, wrong = perTap(47, "grass", taps)
		local where = string.format("loft 47, %d taps: side %.2f m, forward %.2f m (worst %.2f), wrong %d of 9",
			taps, side, fwd, worstFwd, wrong)
		sides[taps] = side
		if taps == 0 then
			expect.truthy(abs(side) < 0.2, where)
		else
			expect.truthy(side > 0.1 and side < 1.3, where)
			expect.truthy(wrong <= (taps == 1 and 4 or 2), "rolls the spin's way: " .. where)
			local back = perTap(47, "grass", -taps)
			-- the other way too, though not as evenly as when drills stopped
			-- dead (the drill's roll on landing is one way)
			expect.truthy(back < -0.1 and abs(back + side) < 0.5,
				string.format("-%d taps rolls %.2f m, +%d %.2f m", taps, back, taps, side))
		end
	end
	expect.truthy(sides[3] > sides[1], string.format("3 taps %.2f m past 1 tap %.2f m", sides[3], sides[1]))
	-- a low arc (loft 30) too
	local l1, l3 = perTap(30, "grass", 1), perTap(30, "grass", 3)
	expect.truthy(l3 > l1 and l3 > 0.4 and l3 < 1.3, string.format("loft 30: 1 tap %.2f m, 3 taps %.2f m", l1, l3))
	-- sand holds it
	local g3, s3 = perTap(47, "grass", 3), perTap(47, "sand", 3)
	expect.truthy(s3 < 0.9 * g3, string.format("sand %.2f m against grass %.2f m", s3, g3))
end)

test("drill: a rolling kubb stops against the stake; a drill into a lying kubb stops by it", function()
	-- the stake at (2.5, 4): two taps from 0.45 m inward
	for _, seed in ipairs { 1, 2, 3 } do
		local t = planDrill(2.05, 4.03, 47, 2, "grass", seed)
		local b = t.rest
		expect.truthy(b.x < 2.5 - 0.025 and b.x > 2.2 and abs(b.y - 4) < 0.12,
			string.format("rests against the stake: (%.3f, %.3f)", b.x, b.y))
	end
	-- a kubb lying along the throw at (1, 5.5): two taps from 0.55 m to its
	-- left. Not every one reaches it now; none goes through it, and it barely
	-- moves.
	local h = math.sqrt(0.5)
	local reached = 0
	for seed = 1, 6 do
		local k = { id = "k", kind = "kubb", x = 1, y = 5.5, z = 0.035, qw = h, qx = -h, qy = 0, qz = 0, toppled = true }
		local t = planDrill(0.45, 5.5, 47, 2, "grass", seed, { k })
		local b, q = t.rest, t.w.byId.k
		if b.x > 0.85 then reached = reached + 1 end
		expect.truthy(b.x < 1 - 0.03, string.format("never past it: x %.3f", b.x))
		expect.truthy(dist(q.x, q.y, 1, 5.5) < 0.06, "the lying kubb barely moves")
	end
	expect.truthy(reached >= 2, string.format("reaches it %d of 6", reached))
	-- a clean unspun drill landing just short of a lying kubb runs into it and
	-- stops by it: the backstop the computer builds on
	for seed = 1, 6 do
		local k = { id = "k", kind = "kubb", x = 0, y = 6.4, z = 0.035, qw = 1, qx = 0, qy = 0, qz = 0, toppled = true }
		local sol = drill.solveAt(0, 6.4, 0, 47, {}, nil, "grass", 0)
		local L = drill.body(1, 1, 0, {})
		local w = world.new { surface = "grass", groundSeed = seed, pieces = { k } }
		local b = world.launchDrill(w, "d", sol.x, 0, sol.swivel, sol.loft, sol.speed, L.noseDown, L.rollLand,
			L.spin, L.wobble, L.digGain)
		world.run(w)
		local q = w.byId.k
		expect.truthy(b.y < q.y + 0.35, string.format("stops by it, not past: y %.2f against %.2f", b.y, q.y))
		expect.truthy(dist(q.x, q.y, 0, 6.4) < 0.5, "the struck kubb moves a little")
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
