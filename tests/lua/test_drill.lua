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
		tilt = r.tilt or 90 * (1 - (r.smoothness or 1)), how = r.how or "passed" }
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
			for _, how in ipairs { "passed", "slowed" } do
				local j = throwAt(m[1], m[2], { smoothness = 0.35, how = how })
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

test("drill: the baton and lob launches are unchanged by digGain", function()
	local w = world.new { surface = "grass", stakes = false }
	local b = world.launchKubb(w, "p", 0, 0, 0, 40, 6.5, 3)
	expect.eq(b.digGain, 1)
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

test("drill: the stop on the notch sets the launch, as a baton's", function()
	-- Jamie, 2026-11-14: one throw to learn. The solved loft is the notch.
	local sol = drill.solve(0, 6, 0)
	local base = { power = sol.band, smoothness = 1, tilt = 0, how = "stopped" }
	local function at(angle)
		local r = {}
		for k, v in pairs(base) do r[k] = v end
		r.releaseAngle = angle
		return drill.launch(sol, r, 0)
	end
	expect.near(at(sol.loft).loft, sol.loft, 1e-9)
	expect.near(at(sol.loft + 8).loft, sol.loft, 1e-9)             -- within the forgiving 10
	expect.near(at(sol.loft - 40).loft, tw.swing.releaseLoft(sol.loft, sol.loft - 40), 1e-9)
	expect.truthy(at(sol.loft - 40).loft < sol.loft, "early is lower")
	expect.truthy(at(sol.loft + 40).loft > sol.loft, "late is higher")
	-- the old release keeps the solved loft
	local old = drill.launch(sol, { power = sol.band, smoothness = 1, tilt = 0, how = "passed", releaseAngle = 50 }, 0)
	expect.near(old.loft, sol.loft, 1e-9)
end)

-- The cut by tilting the console (the accelerometer's roll).

-- The accelerometer's x, y, z for a console rolled `roll` degrees with its
-- screen tipped `pitch` up from lying on its back (as source/input.lua's
-- input.gravity, which needs the device to load).
local function gravity(roll, pitch)
	local r, e = math.rad(roll), math.rad(pitch)
	return math.sin(r), math.cos(r) * math.sin(e), math.cos(r) * math.cos(e)
end

test("drill: the roll is read the same at any pitch, right side down positive", function()
	for _, pitch in ipairs { 0, 30, 45, 70, 90 } do
		for _, roll in ipairs { -40, -12, 0, 5, 25 } do
			expect.near(drill.rollDeg(gravity(roll, pitch)), roll, 1e-6)
		end
	end
	-- the SDK's own examples: upright 0, 1, 0 and flat on its back 0, 0, 1
	expect.near(drill.rollDeg(0, 1, 0), 0, 1e-9)
	expect.near(drill.rollDeg(0, 0, 1), 0, 1e-9)
	expect.truthy(drill.rollDeg(0.5, 0.7, 0.5) > 0, "x to the right is the right side down")
end)

test("drill: the tilt cut has a dead zone, grows with the roll and stops at the full cut", function()
	local t = drill.tune
	expect.eq(drill.tiltCut(0), 0)
	expect.eq(drill.tiltCut(t.tiltDeadDeg), 0)
	expect.eq(drill.tiltCut(-t.tiltDeadDeg * 0.9), 0)
	-- continuous at the dead zone's edge
	expect.truthy(drill.tiltCut(t.tiltDeadDeg + 0.01) < 0.01, "no jump at the dead zone")
	local prev = 0
	for roll = t.tiltDeadDeg + 1, t.tiltFullDeg, 1 do
		local c = drill.tiltCut(roll)
		expect.truthy(c > prev, string.format("more tilt cuts more at %d", roll))
		expect.near(drill.tiltCut(-roll), -c, 1e-12)
		prev = c
	end
	expect.near(drill.tiltCut(t.tiltFullDeg), t.tiltCutMax, 1e-9)
	expect.near(drill.tiltCut(80), t.tiltCutMax, 1e-9)
	expect.near(drill.tiltCut(-80), -t.tiltCutMax, 1e-9)
	-- right side down curls right, as A does
	expect.truthy(drill.tiltCut(20) > 0 and drill.CUT_A > 0, "right is A's way")
	local sign = t.tiltSign
	t.tiltSign = -1
	local flipped = drill.tiltCut(20)
	t.tiltSign = sign
	expect.near(flipped, -drill.tiltCut(20), 1e-12)
end)

test("drill: the roll is smoothed: the first reading at once, then over tiltSmooth", function()
	local t = drill.tune
	expect.eq(drill.smoothRoll(nil, 17, 0.02), 17)
	local r = 0
	for _ = 1, math.floor(t.tiltSmooth / 0.02 + 0.5) do r = drill.smoothRoll(r, 20, 0.02) end
	expect.truthy(r > 10 and r < 20, string.format("after tiltSmooth it is %.1f of the way to 20", r))
	-- one frame's jolt moves it only a little
	local j = drill.smoothRoll(0, 40, 0.02)
	expect.truthy(j < 0.2 * 40, string.format("a one-frame jolt of 40 moves it %.1f", j))
	-- a long frame never overshoots
	expect.eq(drill.smoothRoll(0, 20, 1), 20)
end)

test("drill: tilted right curls right, left curls left, and more tilt curls more", function()
	-- over a dozen grounds at each marker, as for A and B above: the full
	-- tilt each way parts the rest points, and a full tilt curls farther from
	-- the straight drill than a light one on average
	local t = drill.tune
	local light = (t.tiltDeadDeg + t.tiltFullDeg) / 2   -- half the full cut
	for _, m in ipairs { { 0, 5 }, { 0.5, 6.5 }, { -1, 8 } } do
		local right, n, sr, sl, sLight = 0, 0, 0, 0, 0
		for seed = 1, 12 do
			local straight = throwAt(m[1], m[2], nil, nil, nil, seed)
			local r = throwAt(m[1], m[2], nil, drill.tiltCut(t.tiltFullDeg), nil, seed)
			local l = throwAt(m[1], m[2], nil, drill.tiltCut(-t.tiltFullDeg), nil, seed)
			local h = throwAt(m[1], m[2], nil, drill.tiltCut(light), nil, seed)
			local dr, dl = r.rest.x - straight.rest.x, l.rest.x - straight.rest.x
			if dr > dl then right = right + 1 end
			sr, sl, sLight, n = sr + dr, sl + dl, sLight + (h.rest.x - straight.rest.x), n + 1
		end
		local where = string.format("(%.1f, %.1f)", m[1], m[2])
		expect.truthy(right >= 0.9 * n, string.format("tilted right ends right of left at %s: %d of %d", where, right, n))
		expect.truthy(sr / n > 0 and sl / n < 0, string.format("right %+.3f, left %+.3f m at %s", sr / n, sl / n, where))
		expect.truthy(sr / n > sLight / n, string.format("full tilt %+.3f, light %+.3f m at %s", sr / n, sLight / n, where))
	end
end)
