-- The throw plan (core/throwplan, tw.plan): the power and loft scales, the
-- gauge's targets from a target, a stance and a plan, and the launch from a
-- measured swing. Swing results are written out here (the fields core/swing
-- reports), so nothing depends on core/swing. Real physics where it says so;
-- tolerances, not exact numbers.
import "core/throwplan"
import "core/flight"
import "core/drill"
import "core/world"
local plan, flight, drill, world = tw.plan, tw.flight, tw.drill, tw.world

local sqrt, abs, rad = math.sqrt, math.abs, math.rad

local function dist(ax, ay, bx, by) return sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- A clean swing that hits the solution's targets dead center.
local function cleanSwing(sol, over)
	local r = { back = sol.back, releaseAngle = sol.release, flickFrac = 1, smoothness = 1, shake = 0,
		pull = 1, how = "stopped" }
	for k, v in pairs(over or {}) do r[k] = v end
	if over and over.smoothness and not over.shake then r.shake = 1 - over.smoothness end
	return r
end

local function solve(projectile, px, py, tx, ty, release, level)
	return plan.solve({ projectile = projectile, px = px, py = py, tx = tx, ty = ty, release = release,
		level = level }, {})
end

-- ---------- the scales ----------

test("plan: the power scale hits its anchors, rises and inverts", function()
	expect.near(plan.reach(30), 0, 1e-9, "7 o'clock")
	expect.near(plan.reach(10), 0, 1e-9, "the dead zone")
	expect.near(plan.reach(90), 4, 1e-9, "9 o'clock")
	expect.near(plan.reach(120), 8, 1e-9, "10 o'clock")
	-- corner to corner, 9.4 m, about 10:20
	local corner = plan.backFor(sqrt(5 * 5 + 8 * 8))
	expect.truthy(corner > 125 and corner < 132, string.format("corner to corner at %.1f degrees", corner))
	expect.truthy(plan.reach(150) > 12, "11 o'clock is past any throw from the baseline")
	local last = -1
	for b = 30, 180, 2 do
		local R = plan.reach(b)
		expect.truthy(R > last or b == 30, "monotonic at " .. b)
		expect.near(plan.backFor(R), b, 1e-6, "inverse at " .. b)
		last = R
	end
	-- the speed carries the reach at the reference arc
	for _, b in ipairs { 60, 90, 120, 150 } do
		local _, ly = flight.predict(0, 0, 0, plan.tune.refLoftDeg, plan.speedFor(b))
		expect.near(ly, plan.reach(b), 1e-6, "speedFor carries reach at " .. b)
		expect.near(plan.backForSpeed(plan.speedFor(b)), b, 1e-6)
	end
	expect.eq(plan.speedFor(20), 0)
end)

test("plan: the loft scale is the line through 5 and 3 o'clock, and inverts", function()
	expect.near(plan.loftFor(30), 12, 1e-9)
	expect.near(plan.loftFor(90), 32, 1e-9)
	expect.near(plan.loftFor(135), 47, 1e-9)
	expect.near(plan.loftFor(150), 52, 1e-9)
	expect.near(plan.loftFor(180), 62, 1e-9)
	expect.near(plan.tune.refLoftDeg, plan.loftFor(90), 1e-9, "the reference arc is 3 o'clock")
	for rel = 15, 165, 15 do expect.near(plan.releaseFor(plan.loftFor(rel)), rel, 1e-9) end
	expect.eq(plan.loftFor(-100), plan.tune.loftMinDeg)
	expect.eq(plan.loftFor(400), plan.tune.loftMaxDeg)
	expect.eq(plan.clampRelease(0), 15)
	expect.eq(plan.clampRelease(200), 165)
	expect.eq(plan.arcFor("king"), 75)
	expect.eq(plan.arcFor("drill"), 135)
end)

-- ---------- stance, snap, solve ----------

test("plan: the default stance is straight behind the target, as far forward as allowed", function()
	local o = {}
	plan.stance(1.2, 7, 0, 2.5, 2.4, o)
	expect.eq(o.x, 1.2); expect.eq(o.y, 2.5)
	plan.stance(-2.9, 7, 0, nil, 2.4, o)
	expect.eq(o.x, -2.4); expect.eq(o.y, 0)
end)

test("plan: snap finds the nearest standing target within the radius", function()
	local ts = { { x = -1, y = 8 }, { x = 0, y = 8 }, { x = 0.1, y = 7.9 }, { x = 0, y = 4 } }
	local p, i = plan.snap(0.05, 7.95, ts, #ts, 0.25)
	expect.eq(i, 3); expect.eq(p, ts[3])
	expect.eq(plan.snap(0, 6, ts, #ts, 0.25), nil)
	expect.eq(plan.snap(0, 8, ts, 1, 0.25), nil, "only the first n")
end)

test("plan: a 3 o'clock baton at the plan's backswing lands on a base kubb 8 m out", function()
	local sol = solve("baton", 0, 0, 1, 8, plan.arcFor("base"))
	expect.near(sol.loft, 32, 1e-9)
	expect.near(sol.back, 120 + 0.6, 1.5, "about 10 o'clock") -- 8.06 m out
	local L = plan.launch(sol, cleanSwing(sol), { projectile = "baton", tilt = 0 }, {})
	expect.near(L.speed, sol.speed, 1e-6)
	expect.near(L.loft, sol.loft, 1e-9)
	expect.truthy(L.legal and L.steady and L.over == 0)
	local lx, ly = flight.predict(0, 0, L.swivel, L.loft, L.speed)
	expect.truthy(dist(lx, ly, 1, 8) < 0.03, string.format("predicted landing %.3f m off", dist(lx, ly, 1, 8)))
	-- the same throw in core/world: it hits b and topples it; on an empty pitch it
	-- first touches the ground just short of the kubb (the baton's ends reach down
	-- before its center does)
	local w = world.new { surface = "grass", stakes = false, groundSeed = 1,
		pieces = { { id = "b", kind = "kubb", x = 1, y = 8, yaw = 0 } } }
	world.launchBaton(w, 0, 0, L.swivel, L.loft, L.speed, L.tumble, L.tilt)
	world.run(w)
	local res = world.result(w)
	expect.eq(res.firstHit and res.firstHit.with, "b", "first body hit")
	expect.eq(res.toppled[1], "b", "toppled")
	local e = world.new { surface = "grass", stakes = false, groundSeed = 1 }
	world.launchBaton(e, 0, 0, L.swivel, L.loft, L.speed, L.tumble, L.tilt)
	world.run(e, 2)
	local fc = e.firstContact
	local off = dist(fc.x, fc.y, 1, 8)
	expect.truthy(off < 0.35, string.format("first touches the ground %.2f m from the kubb", off))
end)

test("plan: a lower arc needs more backswing for the same target; farther needs more", function()
	local prev
	for _, rel in ipairs { 135, 90, 75, 60, 30 } do
		local s = solve("baton", 0, 0, 0, 7, rel)
		if prev then expect.truthy(s.back > prev, string.format("release %d needs more than the arc above", rel)) end
		prev = s.back
	end
	local a, b = solve("baton", 0, 0, 0, 5, 90), solve("baton", 0, 0, 0, 8, 90)
	expect.truthy(b.back > a.back)
	-- 4 m at 3 o'clock is 9 o'clock on the dial
	expect.near(solve("baton", 0, 4, 0, 8, 90).back, 90, 1e-6)
	-- swivel: a target to the right is a positive swivel, as core/flight takes it
	expect.truthy(solve("baton", 0, 0, 1, 8, 90).swivel > 0)
	expect.truthy(solve("baton", 0, 0, -1, 8, 90).swivel < 0)
end)

test("plan: the levels' targets narrow from beginner to pro", function()
	expect.eq(#plan.LEVELS, 3)
	local wP, wR = math.huge, math.huge
	for _, name in ipairs(plan.LEVELS) do
		local s = solve("baton", 0, 0, 0, 8, 90, name)
		local lv = plan.levels[name]
		expect.near(s.powerHi - s.powerLo, 2 * lv.powerHalf, 1e-9)
		expect.near(s.releaseHi - s.releaseLo, 2 * lv.releaseHalf, 1e-9)
		expect.near((s.powerLo + s.powerHi) / 2, s.back, 1e-9)
		expect.truthy(s.powerHi - s.powerLo < wP and s.releaseHi - s.releaseLo < wR, name .. " narrower")
		wP, wR = s.powerHi - s.powerLo, s.releaseHi - s.releaseLo
	end
	local b = solve("baton", 0, 0, 0, 8, 90, "beginner")
	expect.eq(b.powerHi - b.powerLo, 30); expect.eq(b.releaseHi - b.releaseLo, 60)
	expect.eq(solve("baton", 0, 0, 0, 8, 90).level, plan.levels.club, "club by default")
end)

-- ---------- the launch ----------

test("plan: errors are forgiven inside a target and count in full past it, continuously", function()
	for _, name in ipairs(plan.LEVELS) do
		local lv = plan.levels[name]
		local sol = solve("baton", 0, 0, 0, 8, 90, name)
		local function at(over) return plan.launch(sol, cleanSwing(sol, over), nil, {}) end
		-- power: speed is continuous across both edges and steeper outside
		for _, sgn in ipairs { -1, 1 } do
			local edge = sol.back + sgn * lv.powerHalf
			local a, b = at { back = edge - sgn * 1e-6 }, at { back = edge + sgn * 1e-6 }
			expect.near(a.speed, b.speed, 1e-4, name .. " power edge")
			expect.eq(a.powerV, 0); expect.eq(b.powerV, sgn)
			local inside = abs(at { back = edge - sgn * 1 }.speed - a.speed)
			local outside = abs(at { back = edge + sgn * 1 }.speed - b.speed)
			expect.truthy(outside > inside * 1.2, name .. " steeper past the edge")
		end
		expect.truthy(at { back = sol.powerLo - 10 }.speed < sol.speed, "short")
		expect.truthy(at { back = sol.powerHi + 10 }.speed > sol.speed, "long")
		-- release: loft is continuous at the edges
		for _, sgn in ipairs { -1, 1 } do
			local edge = sol.release + sgn * lv.releaseHalf
			local a, b = at { releaseAngle = edge - sgn * 1e-6 }, at { releaseAngle = edge + sgn * 1e-6 }
			expect.near(a.loft, b.loft, 1e-4, name .. " release edge")
			expect.eq(a.releaseV, 0); expect.eq(b.releaseV, sgn)
		end
		-- inside the target the loft moves inGain of the release's error
		local d = lv.releaseHalf / 2
		expect.near(at { releaseAngle = sol.release + d }.loft - sol.loft,
			lv.inGain * d * (plan.loftFor(90) - plan.loftFor(30)) / 60, 1e-9)
	end
	expect.near(plan.shrink(0.5, 1, 0.3), 0.15, 1e-12)
	expect.near(plan.shrink(-3, 1, 0.3), -2.3, 1e-12)
end)

test("plan: the flick scales the speed; a sky ball leaves high", function()
	local sol = solve("baton", 0, 0, 0, 8, 90)
	local half = plan.launch(sol, cleanSwing(sol, { flickFrac = 0.5 }), nil, {})
	expect.near(half.speed, sol.speed * 0.5, 1e-9)
	local sky = plan.launch(sol, cleanSwing(sol, { releaseAngle = 185, how = "sky" }), nil, {})
	expect.eq(sky.releaseV, 1)
	expect.truthy(sky.loft > 65, string.format("sky ball at %.0f degrees", sky.loft))
	local _, ly = flight.predict(0, 0, 0, sky.loft, sky.speed)
	expect.truthy(ly < 6, string.format("and lands short (%.1f m)", ly))
	expect.eq(select(2, plan.verdictText(sky)), "HIGH")
end)

test("plan: shake tilts and pulls; overpower raises its costs; tilt and shake add to a helicopter", function()
	local sol = solve("baton", 0, 0, 0, 8, 90, "pro")
	local shaky = plan.launch(sol, cleanSwing(sol, { smoothness = 0.7, pull = 1 }), { tilt = 0 }, {})
	expect.near(shaky.tilt, 90 * 0.3, 1e-9)
	expect.truthy(shaky.swivel > sol.swivel and shaky.legal and not shaky.steady)
	local left = plan.launch(sol, cleanSwing(sol, { smoothness = 0.7, pull = -1 }), { tilt = 0 }, {})
	expect.truthy(left.tilt < 0 and left.swivel < sol.swivel)
	-- 30 degrees past the power target at pro doubles the costs
	local over = plan.launch(sol, cleanSwing(sol, { smoothness = 0.7, back = sol.powerHi + 30 }), { tilt = 0 }, {})
	expect.near(over.over, 1, 1e-9)
	expect.near(over.tilt, 2 * shaky.tilt, 1e-9)
	expect.truthy(over.swivel - sol.swivel > 1.9 * (shaky.swivel - sol.swivel))
	expect.truthy(not over.legal, "2 x 27 = 54 degrees: a helicopter")
	expect.eq(select(3, plan.verdictText(over)), "SHAKY")
	expect.eq(over.powerV, 1)
	-- under the power target nothing is overpowered
	expect.eq(plan.launch(sol, cleanSwing(sol, { back = sol.powerLo - 20 }), nil, {}).over, 0)
	-- a planned tilt and the shake add toward the limit, or take away
	local csol = solve("baton", 0, 0, 0, 8, 90, "club")
	local r = cleanSwing(csol, { smoothness = 0.6, pull = 1 }) -- 90 x 0.4 x 0.75 = 27
	expect.truthy(plan.launch(csol, r, { tilt = 0 }, {}).legal)
	expect.truthy(not plan.launch(csol, r, { tilt = 10 }, {}).legal)
	expect.truthy(plan.launch(csol, r, { tilt = -10 }, {}).legal)
	-- the same shake costs a beginner less than a pro
	local bsol = solve("baton", 0, 0, 0, 8, 90, "beginner")
	expect.truthy(plan.launch(bsol, cleanSwing(bsol, { smoothness = 0.8 }), nil, {}).tilt < shaky.tilt)
	-- the tumble follows the speed
	expect.near(plan.tumbleFor(4.0), 4.5, 1e-9)
	expect.near(plan.tumbleFor(9.2), 7.0, 1e-9)
	expect.truthy(shaky.tumble > 6 and shaky.tumble < 7)
	local p, rl, st = plan.verdictText(plan.launch(sol, cleanSwing(sol), nil, {}))
	expect.eq(p .. " " .. rl .. " " .. st, "ON ON STEADY")
end)

-- ---------- kubbs ----------

-- A drill launched on an empty grass pitch from the baseline (y = 0); returns
-- the kubb's body at rest.
local function drillRest(px, L, seed)
	local w = world.new { surface = "grass", stakes = false, groundSeed = seed }
	local b = world.launchDrill(w, "p", px, 0, L.swivel, L.loft, L.speed, L.noseDown, L.rollLand, L.spin,
		L.wobble, L.digGain)
	world.run(w)
	return b, w
end

test("plan: drill.solveAt at half past 1 (47 degrees) rests near the target in real physics", function()
	-- measured 2026-11-15 on grass: 0.04 m off on average, 0.05 m worst (nine
	-- targets near to far, two grounds each)
	local sum, worst, n = 0, 0, 0
	for _, m in ipairs { { 0, 4.2 }, { 1.2, 4.5 }, { -1.5, 4.8 }, { 0, 6 }, { 1.5, 5.5 }, { -2, 6.5 },
			{ 0, 8 }, { -2, 7.5 }, { 1, 8.4 } } do
		for seed = 1, 2 do
			local sol = drill.solveAt(m[1], m[2], 0, 47)
			expect.near(sol.loft, 47, 1e-9)
			local t = drill.tune
			local b = drillRest(sol.x, { swivel = sol.swivel, loft = sol.loft, speed = sol.speed,
				noseDown = t.noseDownDeg, rollLand = t.rollLandDeg, spin = 0, wobble = 0, digGain = t.digGain }, seed)
			local e = dist(b.x, b.y, m[1], m[2])
			sum, n = sum + e, n + 1
			if e > worst then worst = e end
		end
	end
	expect.truthy(worst < 0.4, string.format("worst %.2f m off", worst))
	expect.truthy(sum / n < 0.2, string.format("mean %.2f m off", sum / n))
	-- drill.solve is drill.solveAt at the distance's loft
	local a, b = drill.solve(0.5, 6, 0), {}
	drill.solveAt(0.5, 6, 0, a.loft, b)
	expect.near(a.speed, b.speed, 1e-12); expect.near(a.swivel, b.swivel, 1e-12)
	-- a stance away from straight behind turns the swivel
	expect.truthy(drill.solveAt(0, 6, 0, 47, {}, -1).swivel > 0)
end)

test("plan: a planned drill from a stance rests on the target; spin and shake reach the body", function()
	local sol = solve("kubb", 0.5, 0, 0, 6, plan.arcFor("drill"))
	expect.near(sol.loft, 47, 1e-9)
	expect.truthy(sol.back > 95 and sol.back < 115, string.format("a 6 m drill at %.0f degrees back", sol.back))
	local L = plan.launch(sol, cleanSwing(sol), { projectile = "kubb", spin = 0 }, {})
	expect.near(L.speed, sol.speed, 1e-6)
	expect.truthy(L.legal and L.tumble == 0 and L.spin == 0 and L.wobble == 0)
	expect.eq(L.noseDown, drill.tune.noseDownDeg); expect.eq(L.digGain, drill.tune.digGain)
	local b = drillRest(0.5, L, 3)
	expect.truthy(dist(b.x, b.y, 0, 6) < 0.4, string.format("rests %.2f m off", dist(b.x, b.y, 0, 6)))
	-- spin: + taps roll it right (negative spin about the forward axis, as drill's CUT_A)
	local R = plan.launch(sol, cleanSwing(sol), { projectile = "kubb", spin = 4 }, {})
	expect.near(R.spin, -4 * plan.tune.spinPerStep, 1e-9)
	expect.near(R.spin, -drill.tune.cutSpin, 1e-9, "four taps are the old cut")
	-- a shaky drill wobbles, worse overpowered
	local s1 = plan.launch(sol, cleanSwing(sol, { smoothness = 0.5 }), { projectile = "kubb" }, {})
	local s2 = plan.launch(sol, cleanSwing(sol, { smoothness = 0.5, back = sol.powerHi + 20 }), { projectile = "kubb" }, {})
	expect.truthy(s1.wobble > 0 and s2.wobble > s1.wobble, string.format("wobble %.1f then %.1f", s1.wobble, s2.wobble))
	expect.truthy(s2.legal, "a kubb has no helicopter rule")
end)
