-- core/drills: the practice drills' set-ups, scoring and records.
import "core/drills"
import "core/world"
import "core/drill"
import "core/throwplan"
local drills, world = tw.drills, tw.world

test("drills: seven drills, each with a setup for its first throw", function()
	expect.eq(#drills.list, 7)
	for _, d in ipairs(drills.list) do
		local run = drills.newRun(d)
		local s = drills.setup(d, run)
		expect.truthy(s, d.id .. " setup")
		expect.eq(s.n, 1)
		expect.eq(s.of, d.throws)
		if d.kind == "blast" or d.kind == "wall" then
			expect.eq(s.projectile, "kubb")
		else
			expect.eq(s.projectile, "baton")
			expect.truthy(#s.targets >= 1, d.id .. " targets")
		end
	end
end)

test("drills: 8 meters counts each kubb once, keeps it down, ends when all five are down", function()
	local d = drills.byId("8m")
	local run = drills.newRun(d)
	expect.eq(drills.tally(d, run, { toppled = { "b2" } }), false)
	expect.eq(run.score, 1)
	local s = drills.setup(d, run)
	for _, p in ipairs(s.pieces) do expect.truthy(p.id ~= "b2", "b2 stays down") end
	drills.tally(d, run, { toppled = { "b2", "king" } })   -- b2 again, and the king: no points
	expect.eq(run.score, 1)
	drills.tally(d, run, { toppled = { "b1", "b3" } })
	expect.eq(drills.tally(d, run, { toppled = { "b4", "b5" } }), true, "all down ends the run")
	expect.eq(run.score, 5)
	expect.eq(drills.setup(d, run), nil)
end)

test("drills: king shots score the king each time it falls; blast scores near the marker", function()
	local k = drills.byId("king")
	local run = drills.newRun(k)
	for i = 1, 6 do drills.tally(k, run, { toppled = (i % 2 == 0) and { "king" } or {} }) end
	expect.eq(run.score, 3)
	expect.truthy(run.done)
	local b = drills.byId("blast")
	run = drills.newRun(b)
	for _, cm in ipairs { 20, 50, 51, 120, 5, 999 } do drills.tally(b, run, { restCm = cm }) end
	expect.eq(run.score, 3)
	expect.truthy(run.done)
end)

test("drills: around the pitch throws from in front of each kubb in turn", function()
	local d = drills.byId("around")
	local run = drills.newRun(d)
	expect.eq(drills.setup(d, run).playerX, -2)
	drills.tally(d, run, {})
	expect.eq(drills.setup(d, run).playerX, -1)
end)

test("drills: records keep the best, the rate and the last ten", function()
	local rec = {}
	local d = drills.byId("8m")
	for i = 1, 12 do
		local run = drills.newRun(d)
		run.score, run.done = (i == 4) and 5 or (i % 4), true
		local r, best = drills.record(rec, d, run)
		if i == 4 then expect.truthy(best, "a new best") end
	end
	local r = rec["8m"]
	expect.eq(r.best, 5)
	expect.eq(r.runs, 12)
	expect.eq(#r.last, 10)
	expect.eq(drills.rate(r), math.floor(100 * r.points / (12 * 5) + 0.5))
end)

test("drills: BLAST's marker is fixed at blastMarkerY, as the menu map draws it", function()
	local d = drills.byId("blast")
	local s = drills.setup(d, drills.newRun(d))
	expect.eq(s.markerX, 0)
	expect.eq(s.markerY, drills.tune.blastMarkerY)
end)

-- ---------- DOUBLES ----------

test("drills: DOUBLES has six groups (pairs and triples, side by side and in line, 3/7/15 cm) and of = kubbs + bonuses", function()
	local d = drills.byId("doubles")
	local groups = drills.tune.doubles
	expect.eq(#groups, d.throws)
	local kubbs, kinds, gaps = 0, {}, {}
	for i, g in ipairs(groups) do
		local ps = drills.group(g, i)
		kubbs = kubbs + #ps
		kinds[g.kind], gaps[g.gap] = true, true
		expect.truthy(g.y >= 4.5 and g.y <= 6.0, "group " .. i .. " at field-kubb distance")
	end
	expect.eq(d.of, kubbs + d.throws * drills.tune.doublesBonus)
	for _, k in ipairs { "pair", "triple", "inline2", "inline3" } do expect.truthy(kinds[k], k) end
	for _, gap in ipairs { 0.03, 0.07, 0.15 } do expect.truthy(gaps[gap], gap .. " m gap") end
end)

test("drills: DOUBLES group geometry: side by side across, in line along, a side plus the gap apart", function()
	local pair = drills.group({ kind = "pair", gap = 0.03, x = 0.5, y = 5 }, 1)
	expect.eq(#pair, 2)
	expect.near(pair[2].x - pair[1].x, 0.10, 1e-9)
	expect.near(pair[1].y, 5, 1e-9)
	expect.near((pair[1].x + pair[2].x) / 2, 0.5, 1e-9)
	local line = drills.group({ kind = "inline3", gap = 0.07, x = -1, y = 5.5 }, 3)
	expect.eq(#line, 3)
	expect.eq(line[1].id, "g3k1")
	expect.near(line[3].y - line[1].y, 2 * 0.14, 1e-9)
	expect.near(line[2].y, 5.5, 1e-9)
	expect.near(line[1].x, -1, 1e-9)
end)

test("drills: DOUBLES stands each baton's own group fresh, the same every run", function()
	local d = drills.byId("doubles")
	local run = drills.newRun(d)
	for i = 1, 6 do
		local s = drills.setup(d, run)
		local g = drills.tune.doubles[i]
		local n = (g.kind == "triple" or g.kind == "inline3") and 3 or 2
		expect.eq(#s.pieces, n, "only group " .. i)
		expect.eq(#s.targets, n)
		for _, p in ipairs(s.pieces) do
			expect.eq(p.id:sub(1, 3), "g" .. i .. "k")
			expect.eq(p.toppled, false)
		end
		expect.eq(s.lineY, 0)
		expect.eq(s.forwardY, 0)
		drills.tally(d, run, { toppled = { s.pieces[1].id } })   -- one down each: the next group still stands whole
	end
	expect.truthy(run.done)
	expect.eq(run.score, 6)
	-- a second run starts on the same first group
	local s = drills.setup(d, drills.newRun(d))
	expect.eq(s.pieces[1].id, "g1k1")
end)

test("drills: DOUBLES scores a point a kubb down and a bonus when one baton takes two or more", function()
	local d = drills.byId("doubles")
	local run = drills.newRun(d)
	drills.tally(d, run, { toppled = { "g1k1" } })                      -- 1
	expect.eq(run.score, 1)
	drills.tally(d, run, { toppled = { "g2k1", "g2k2" } })              -- 2 + bonus
	expect.eq(run.score, 4)
	expect.eq(run.multi, 1)
	drills.tally(d, run, { toppled = { "g3k1", "g3k2", "g3k3", "king" } }) -- 3 + one bonus, the king nothing
	expect.eq(run.score, 8)
	expect.eq(run.multi, 2)
	drills.tally(d, run, { toppled = { "g1k2", "g4k1" } })              -- g1k2 is not this baton's group
	expect.eq(run.score, 9)
	expect.eq(run.multi, 2)
	drills.tally(d, run, {})
	expect.eq(drills.tally(d, run, { toppled = { "g6k1", "g6k2" } }), true)
	expect.eq(run.score, 12)
	expect.eq(run.multi, 3)
	-- every kubb with every baton is the drill's whole
	run = drills.newRun(d)
	for i, g in ipairs(drills.tune.doubles) do
		local ids = {}
		for _, p in ipairs(drills.group(g, i)) do ids[#ids + 1] = p.id end
		drills.tally(d, run, { toppled = ids })
	end
	expect.eq(run.score, d.of)
end)

test("drills: DOUBLES groups stand still in the physics (no overlaps)", function()
	for i, g in ipairs(drills.tune.doubles) do
		local w = world.new { texture = false, pieces = drills.group(g, i) }
		world.run(w, 1)
		local res = world.result(w)
		expect.eq(#res.toppled, 0, "group " .. i .. " toppled nothing")
		for _, p in ipairs(drills.group(g, i)) do
			local b = res.bodies[p.id]
			expect.near(b.x, p.x, 0.002, p.id .. " x")
			expect.near(b.y, p.y, 0.002, p.id .. " y")
		end
	end
end)

-- ---------- THE WALL ----------

local C45 = math.sqrt(0.5)
-- a lying kubb's rest pose: long axis along x (along = "x") or y
local function lying(id, x, y, along)
	if along == "y" then return { id = id, x = x, y = y, z = 0.035, qw = C45, qx = -C45, qy = 0, qz = 0, toppled = true } end
	return { id = id, x = x, y = y, z = 0.035, qw = C45, qx = 0, qy = C45, qz = 0, toppled = true }
end
local function upright(id, x, y)
	return { id = id, x = x, y = y, z = 0.075, qw = 1, qx = 0, qy = 0, qz = 0, toppled = false }
end
local SX, SY = 2.5, 4
local R = 0.0095   -- pitch.stakeRadius
-- center x of a kubb along x whose near end is `gap` from the stake's circle
local function fromStake(gap) return SX - R - gap - 0.075 end

test("drills: the wall chains from the stake, kubb to kubb within wallGap", function()
	local out = {}
	local ax = fromStake(0.05)
	local bx = ax - 0.15 - 0.10          -- 10 cm past A: in
	local cx = bx - 0.15 - 0.14          -- 14 cm past B: out (over wallGap)
	local ks = { lying("a", ax, 4.0), lying("b", bx, 4.05), lying("c", cx, 4.0) }
	expect.eq(drills.wall(ks, 3, SX, SY, out), 2)
	expect.eq(out[1], true); expect.eq(out[2], true); expect.eq(out[3], false)
	-- order does not matter: a chain found through a later kubb
	local ks2 = { ks[3], ks[2], ks[1] }
	expect.eq(drills.wall(ks2, 3, SX, SY, out), 2)
	expect.eq(out[1], false)
	-- nothing near the stake: no wall, however tidy the line
	local far = { lying("a", fromStake(0.2), 4), lying("b", fromStake(0.2) - 0.16, 4) }
	expect.eq(drills.wall(far, 2, SX, SY, out), 0)
	-- the gap is edge to edge: exactly wallGap is in, a centimetre more is out
	expect.eq(drills.wall({ lying("a", fromStake(drills.tune.wallGap - 1e-6), 4) }, 1, SX, SY, out), 1)
	expect.eq(drills.wall({ lying("a", fromStake(drills.tune.wallGap + 0.01), 4) }, 1, SX, SY, out), 0)
	-- side by side counts as well as end to end
	local side = { lying("a", fromStake(0.02), 4.0), lying("b", fromStake(0.02), 4.0 + 0.07 + 0.05) }
	expect.eq(drills.wall(side, 2, SX, SY, out), 2)
end)

test("drills: a wall kubb lies on the pitch, on the centerline band, touching the far half", function()
	local out = {}
	local x = fromStake(0.02)
	expect.eq(drills.wall({ upright("a", x, 4.0) }, 1, SX, SY, out), 0, "standing")
	expect.eq(drills.wall({ lying("a", x, 4.0 + drills.tune.wallBand + 0.01) }, 1, SX, SY, out), 0, "past the band")
	expect.eq(drills.wall({ lying("a", x, 4.0 + drills.tune.wallBand - 0.01) }, 1, SX, SY, out), 1, "in the band, far side")
	-- short of the line: in only if the footprint reaches y = 4
	expect.eq(drills.wall({ lying("a", x, 3.97) }, 1, SX, SY, out), 1, "along x, half a cm over the line")
	expect.eq(drills.wall({ lying("a", x, 3.96) }, 1, SX, SY, out), 0, "along x, short of the line")
	expect.eq(drills.wall({ lying("a", 2.44, 3.94, "y") }, 1, SX, SY, out), 1, "along y, over the line")
	expect.eq(drills.wall({ lying("a", 2.44, 3.92, "y") }, 1, SX, SY, out), 0, "along y, short of it")
	-- past the sideline is off the pitch, however near the stake
	expect.eq(drills.wall({ lying("a", 2.56, 4.0, "y") }, 1, SX, SY, out), 0, "outside the sideline")
	-- a kubb that is out (standing, off the band) breaks the chain
	local ks = { lying("a", fromStake(0.02), 4.0), upright("b", fromStake(0.02) - 0.15, 4.0),
		lying("c", fromStake(0.02) - 0.30, 4.0) }
	expect.eq(drills.wall(ks, 3, SX, SY, out), 1)
	ks[2] = lying("b", fromStake(0.02) - 0.15, 4.0, "y")   -- the same kubb lying bridges it
	expect.eq(drills.wall(ks, 3, SX, SY, out), 3)
end)

test("drills: THE WALL keeps each drilled kubb on the pitch and scores the wall as it stands", function()
	local d = drills.byId("wall")
	local run = drills.newRun(d)
	local s = drills.setup(d, run)
	expect.eq(s.projectile, "kubb")
	expect.eq(s.kubb, "w1")
	expect.eq(s.markerY, nil, "the marker is free")
	expect.eq(#s.pieces, 0)
	local st = tw.pitch.stakes[drills.tune.wallStake]
	expect.eq(st.x, 2.5); expect.eq(st.y, 4)
	-- w1 rests against the stake: 1
	local w1 = lying("w1", fromStake(0.03), 4.0)
	drills.tally(d, run, { bodies = { w1 = w1 } })
	expect.eq(run.score, 1)
	s = drills.setup(d, run)
	expect.eq(s.kubb, "w2")
	expect.eq(#s.pieces, 1)
	local p = s.pieces[1]
	expect.eq(p.id, "w1"); expect.near(p.x, w1.x, 1e-9); expect.eq(p.z, 0.035); expect.eq(p.qy, C45)
	-- w2 behind it: 2
	local w2 = lying("w2", w1.x - 0.15 - 0.05, 4.02)
	drills.tally(d, run, { bodies = { w1 = w1, w2 = w2 } })
	expect.eq(run.score, 2)
	-- w3 knocks w1 away from the stake: w2 is cut off, w3 does not reach either
	local w1moved = lying("w1", 1.0, 4.6)
	local w3 = lying("w3", 2.0, 3.5)
	drills.tally(d, run, { bodies = { w1 = w1moved, w2 = w2, w3 = w3 } })
	expect.eq(run.score, 0, "a wall knocked apart stops counting")
	expect.eq(#run.kubbs, 3)
	expect.near(run.kubbs[1].x, 1.0, 1e-9)
	-- w4 fills the gap at the stake: w2 counts again
	local w4 = lying("w4", fromStake(0.02), 4.0)
	drills.tally(d, run, { bodies = { w1 = w1moved, w2 = w2, w3 = w3, w4 = w4 } })
	expect.eq(run.score, 2)
	expect.eq(run.inWall[2], true); expect.eq(run.inWall[4], true); expect.eq(run.inWall[1], false)
	drills.tally(d, run, { bodies = {} })   -- a body list without the new kubb changes nothing
	expect.eq(run.score, 2)
	expect.eq(drills.tally(d, run, { bodies = { w1 = w1moved, w2 = w2, w3 = w3, w4 = w4 } }), true)
	expect.eq(drills.setup(d, run), nil)
end)

test("drills: THE WALL's kept kubbs load into the physics lying where they rested", function()
	local d = drills.byId("wall")
	local run = drills.newRun(d)
	drills.tally(d, run, { bodies = { w1 = lying("w1", fromStake(0.03), 4.0) } })
	local s = drills.setup(d, run)
	local w = world.new { texture = false, pieces = s.pieces }
	world.run(w, 1)
	local res = world.result(w)
	local b = res.bodies.w1
	expect.truthy(b.toppled, "down")
	expect.near(b.x, fromStake(0.03), 0.002)
	expect.near(b.z, 0.035, 0.002)
	-- the stake is a body of the world, at the wall's end
	expect.truthy(res.bodies.stake4, "stake4 present")
	expect.near(res.bodies.stake4.x, 2.5, 1e-9)
end)

test("drills: THE WALL with real physics: spun drills rolling in toward the stake build a wall", function()
	-- Since 2026-11-16 a clean drill runs on from where it lands, so stepping
	-- clean ones in from the stake no longer builds a wall (1.3 on average over
	-- 20 grounds). Rolling them in with spin does: two taps aimed 0.5 m inward
	-- of it built 2.8 on average over 20 grounds, 5 or 6 on eight of them and
	-- none on six. Eight grounds here: a wall of a few on average, a long one
	-- on some, and the clean way builds less.
	local drill, plan = tw.drill, tw.plan
	local function wall(seed, taps)
		local d = drills.byId("wall")
		local run = drills.newRun(d)
		for i = 1, 6 do
			local s = drills.setup(d, run)
			expect.eq(#s.pieces, i - 1, "every earlier kubb is a piece")
			local w = world.new { surface = "grass", pieces = s.pieces, groundSeed = seed * 100 + i }
			local sol, L
			if taps == 0 then
				sol = drill.solve(2.42 - (i - 1) * 0.09, 4.1, 0)
				L = drill.launch(sol, { power = sol.band, smoothness = 1, tilt = 0 }, 0)
				sol = { x = sol.x, swivel = L.swivel, loft = L.loft, speed = L.speed }
			else
				sol = drill.solveAt(2.0, 4.05, 0, 47, {}, nil, "grass", taps * plan.tune.spinPerStep)
				L = drill.body(1, 1, taps * plan.tune.spinPerStep, {})
			end
			world.launchDrill(w, s.kubb, sol.x, 0, sol.swivel, sol.loft, sol.speed, L.noseDown, L.rollLand,
				L.spin, L.wobble, L.digGain)
			world.run(w)
			drills.tally(d, run, { bodies = world.result(w).bodies })
		end
		expect.truthy(run.done)
		return run.score
	end
	local spun, clean, long = 0, 0, 0
	for seed = 1, 8 do
		local v = wall(seed, 2)
		spun = spun + v
		if v >= 4 then long = long + 1 end
		clean = clean + wall(seed, 0)
	end
	expect.truthy(spun / 8 >= 1.5, string.format("two taps build %.2f on average", spun / 8))
	expect.truthy(long >= 1, string.format("a wall of 4 or more on %d of 8 grounds", long))
	expect.truthy(clean < spun, string.format("clean drills build %.2f, spun %.2f", clean / 8, spun / 8))
end)

test("drills: records keep DOUBLES and THE WALL like the others", function()
	local rec = {}
	for _, id in ipairs { "doubles", "wall" } do
		local d = drills.byId(id)
		local run = drills.newRun(d)
		run.score, run.done = 3, true
		local r, best = drills.record(rec, d, run)
		expect.truthy(best)
		expect.eq(r.possible, d.of)
		expect.eq(drills.rate(r), math.floor(100 * 3 / d.of + 0.5))
	end
end)

test("drills: THE HOUSE's kubbs are field kubbs, so the aim takes the field-kubb arc", function()
	local d = drills.byId("house")
	local s = drills.setup(d, drills.newRun(d))
	local n = 0
	for _, p in ipairs(s.pieces) do
		if p.kind == "kubb" then n = n + 1; expect.eq(p.role, "field", p.id) end
	end
	expect.eq(n, 5)
end)
