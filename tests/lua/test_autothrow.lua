-- core/autothrow: the computer throws the player's way (target, stance, the
-- default arc, tw.plan.solve, a synthetic swing, tw.plan.launch): the basket
-- drill, the baton's nearest stance, the seeded swing.
import "core/tw"
import "core/autothrow"
import "core/throwplan"
import "core/world"

local autothrow, plan, world = tw.autothrow, tw.plan, tw.world

local function toss(pieces)
	return { kind = "toss", side = "A", pieces = pieces or {}, lineY = 0, forwardY = 0, kubb = "a1" }
end

local function baton(role, x, y, forwardY, kingShot)
	local id = role == "king" and "king" or "t1"
	return { kind = "baton", side = "A", lineY = 0, forwardY = forwardY or 0, kingShot = kingShot,
		targets = { id }, batonId = "baton1",
		pieces = { { id = id, kind = role == "king" and "king" or "kubb", role = role, half = "B", x = x, y = y } } }
end

test("tosses go to the basket with more field kubbs near it, drilled from behind it", function()
	local t = autothrow.tune
	local s = toss {
		{ id = "f1", kind = "kubb", role = "field", half = "B", x = 1.8, y = 4.9 },
		{ id = "f2", kind = "kubb", role = "field", half = "B", x = 2.1, y = 5.3 },
		{ id = "f3", kind = "kubb", role = "field", half = "B", x = -1.9, y = 4.8 },
		-- the thrower's own half does not count
		{ id = "f4", kind = "kubb", role = "field", half = "A", x = -1.9, y = 4.6 },
		{ id = "f5", kind = "kubb", role = "field", half = "A", x = -1.7, y = 4.5 },
	}
	expect.eq(autothrow.basket(s, autothrow.rng(1)), 1)
	local a = autothrow.choose(s, autothrow.rng(1), 0)
	expect.near(a.plan.tx, t.basketX, 1e-9)
	expect.near(a.plan.ty, t.basketY, 1e-9)
	-- straight behind it on the baseline, at the drill arc
	expect.near(a.x, t.basketX, 1e-9)
	expect.near(a.y, 0, 1e-9)
	expect.near(a.swivel, 0, 1e-9)
	expect.near(a.loftDeg, plan.loftFor(plan.arcFor("drill")), 1e-9)
	expect.truthy(a.drill and a.legal and a.tumbleRate == 0, "a drilled kubb")
	expect.near(a.drill.markerX, t.basketX, 1e-9)
	expect.near(a.drill.markerY, t.basketY, 1e-9)
end)

test("an empty far half: either basket, about half each", function()
	local r, right = autothrow.rng(7), 0
	for _ = 1, 200 do
		if autothrow.basket(toss(), r) == 1 then right = right + 1 end
	end
	expect.truthy(right > 70 and right < 130, "right " .. right)
end)

test("a clean drill (scale 0) is the plan's solve; it rests in the basket", function()
	local t = autothrow.tune
	local r = autothrow.rng(3)
	for i = 1, 20 do
		local a = autothrow.choose(toss(), r, 0)
		expect.near(math.abs(a.plan.tx), t.basketX, 1e-9)
		expect.near(a.speed, a.plan.speed, 1e-9)
		expect.near(a.loftDeg, a.plan.loft, 1e-9)
		expect.near(a.swivel, a.plan.swivel, 1e-12)
		expect.eq(a.drill.wobble, 0)
		if i == 1 then
			-- a drill runs on from where it lands a different way on every
			-- ground, so over forty grounds: about in the basket on average,
			-- and in it (0.4 m) on about half of them. (One ground until
			-- 2026-11-16: the tilted patches moved that one drill just past
			-- 0.4 m. Twelve grounds until the run on was measured again with
			-- the air's drag: 7 of 12 in, then 5, the same drill at 50 to 54%
			-- over 200 grounds. Measured: mean 0.41 m, 20 of 40 in.)
			local G = 40
			local sum, inside = 0, 0
			for g = 1, G do
				local w = world.new { surface = "grass", pieces = {}, groundSeed = 7919 * g }
				local b = autothrow.launch(w, toss(), a)
				world.run(w)
				local d = math.sqrt((b.x - a.plan.tx) ^ 2 + (b.y - a.plan.ty) ^ 2)
				sum = sum + d
				if d < 0.4 then inside = inside + 1 end
			end
			local where = string.format("rests %.2f m from the basket on average, %d of %d in it", sum / G, inside, G)
			expect.truthy(sum / G < 0.5 and inside >= 0.4 * G, where)
		end
	end
end)

test("a baton never stands nearer its target than minRange", function()
	local t = autothrow.tune
	local s = baton("field", 1.9, 4.6, 3.6)
	local a = autothrow.choose(s, autothrow.rng(2), 0)
	expect.near(a.y, 4.6 - t.minRange, 1e-9)
	s.forwardY, s.pieces[1].y = 1.0, 6.0
	a = autothrow.choose(s, autothrow.rng(2), 0)
	expect.near(a.y, 1.0, 1e-9)
	-- a king shot is from the baseline, whatever the advantage line
	a = autothrow.choose(baton("king", 0, 4, 2.0, true), autothrow.rng(2), 0)
	expect.near(a.y, 0, 1e-9)
end)

test("choose returns the launch fields; the arc follows the target", function()
	local cases = { { "base", 0.5, 8, "base" }, { "field", -1, 5.5, "field" }, { "king", 0, 4, "king" } }
	for _, c in ipairs(cases) do
		local a = autothrow.choose(baton(c[1], c[2], c[3], 0, c[1] == "king"), autothrow.rng(5), 0)
		for _, k in ipairs { "x", "y", "swivel", "loftDeg", "speed", "tumbleRate", "tilt" } do
			expect.truthy(type(a[k]) == "number", c[1] .. " " .. k)
		end
		expect.eq(a.legal, true)
		expect.eq(a.drill, nil)
		expect.near(a.loftDeg, plan.loftFor(plan.arcFor(c[4])), 1e-9, c[1] .. " arc")
		-- the plan and the swing for the gauge: the arm goes back to swing.back
		-- and forward to swing.releaseAngle
		expect.near(a.plan.tx, c[2], 1e-9)
		expect.near(a.swing.back, a.plan.back, 1e-9)
		expect.near(a.swing.releaseAngle, a.plan.release, 1e-9)
		expect.eq(a.swing.how, "stopped")
		expect.eq(a.swing.flickFrac, 1)
		expect.eq(a.swing.shake, 0)
		expect.near(a.speed, a.plan.speed, 1e-6, "a clean swing gives the solved speed")
		expect.near(a.swivel, a.plan.swivel, 1e-12)
	end
end)

test("a clean baton at a base kubb 8 m away topples it", function()
	local s = baton("base", 0.3, 8)
	local a = autothrow.choose(s, autothrow.rng(1), 0)
	local w = world.new { surface = "grass", pieces = { { id = "t1", kind = "kubb", x = 0.3, y = 8, yaw = 0 } } }
	autothrow.launch(w, s, a)
	world.run(w)
	local down = false
	for _, id in ipairs(world.result(w).toppled) do if id == "t1" then down = true end end
	expect.truthy(down, "toppled")
end)

test("the synthetic swing is seeded: the same seed gives the same throw", function()
	local s = baton("base", 0.5, 8)
	local r1, r2, r3 = autothrow.rng(42), autothrow.rng(42), autothrow.rng(43)
	local differ = false
	for _ = 1, 20 do
		local a, b, c = autothrow.choose(s, r1), autothrow.choose(s, r2), autothrow.choose(s, r3)
		for _, k in ipairs { "back", "releaseAngle", "flickDps", "flickFrac", "smoothness", "shake", "pull" } do
			expect.eq(a.swing[k], b.swing[k], k)
		end
		for _, k in ipairs { "swivel", "loftDeg", "speed", "tumbleRate", "tilt", "legal" } do
			expect.eq(a[k], b[k], k)
		end
		if a.swing.back ~= c.swing.back then differ = true end
	end
	expect.truthy(differ, "another seed throws differently")
end)

test("the synthetic swing's mistakes: their sizes, scaled by scale", function()
	local t = autothrow.tune
	local sol = plan.solve({ projectile = "baton", px = 0, py = 0, tx = 0, ty = 8, release = 90 }, {})
	local function stats(scale)
		local r = autothrow.rng(11)
		local n, sb, sbb, soft, shaky, heli, maxShake = 4000, 0, 0, 0, 0, 0, 0
		for _ = 1, n do
			local sw = autothrow.swing(sol, r, scale, {})
			local e = sw.back - sol.back
			sb, sbb = sb + e, sbb + e * e
			if sw.flickFrac < 1 then soft = soft + 1 end
			if sw.shake > t.shakeMax * scale + 1e-9 then shaky = shaky + 1 end
			if sw.shake > maxShake then maxShake = sw.shake end
			expect.truthy(sw.pull == 1 or sw.pull == -1, "pull")
			expect.near(sw.smoothness, 1 - sw.shake, 1e-12)
			if not plan.launch(sol, sw, { tilt = 0 }, {}).legal then heli = heli + 1 end
		end
		return sb / n, math.sqrt(sbb / n), soft / n, shaky / n, heli / n, maxShake
	end
	local mean, sd, soft, shaky, heli = stats(1)
	expect.truthy(math.abs(mean) < 0.5, string.format("back mean error %.2f", mean))
	expect.near(sd, t.backSd, 0.4, "back sd")
	expect.near(soft, t.softChance, 0.015, "soft flicks")
	expect.truthy(shaky > 0 and shaky < 2 * t.shakyChance, string.format("shaky swings %.3f", shaky))
	expect.truthy(heli < 0.025, string.format("helicopters %.3f", heli))
	local _, sd2, soft2, _, heli2, max2 = stats(0.5)
	expect.near(sd2, t.backSd / 2, 0.3, "half the scale, half the spread")
	expect.truthy(soft2 < soft and heli2 <= heli, "fewer mistakes")
	expect.truthy(max2 <= t.shaky[2] + 1e-9)
end)

test("a toss goes beside a kubb lying at the basket, never onto it or over it", function()
	local t = autothrow.tune
	-- the clear spots alone (into the group off)
	local into = t.into
	t.into = 0
	local lying = { id = "f1", kind = "kubb", role = "field", half = "B", x = t.basketX, y = t.basketY, toppled = true }
	local s = toss { lying }
	local x, y = autothrow.spot(s, 1)
	-- clear of the kubb: outside its ellipse
	local dx, dy = (x - lying.x) / t.spotClearX, (y - lying.y) / t.spotClearY
	expect.truthy(dx * dx + dy * dy >= 1)
	-- and close: within two steps
	expect.truthy(math.abs(x - lying.x) <= 2 * t.spotStepX and math.abs(y - lying.y) <= 2 * t.spotStepY)
	-- not in the lane just behind it, where the drill would come down on it
	expect.truthy(not (math.abs(x - lying.x) < t.spotLane and y > lying.y and y - lying.y < t.spotShortLying))
	local a = autothrow.choose(s, autothrow.rng(1), 0)
	expect.near(a.plan.tx, x, 1e-9)
	expect.near(a.plan.ty, y, 1e-9)
	expect.near(a.drill.markerX, x, 1e-9)
	-- an empty far half: the basket itself
	local bx, by = autothrow.spot(toss(), -1)
	expect.near(bx, -t.basketX, 1e-9)
	expect.near(by, t.basketY, 1e-9)
	t.into = into
end)

test("a later kubb is aimed to run into the group: just short of a lying kubb's near face", function()
	local t = autothrow.tune
	expect.truthy(t.into ~= 0, "into the group is on")
	local function lie(id, x, y, angle)
		return { id = id, kind = "kubb", role = "field", half = "B", x = x, y = y, toppled = true,
			pose = { x = x, y = y, standing = false, angle = angle } }
	end
	-- one kubb lying across the throw at the basket: in its lane, short of its near face
	local k = lie("f1", t.basketX + 0.04, t.basketY + 0.1, 0)
	local s = toss { k }
	s.of = 2
	local x, y = autothrow.spot(s, 1)
	expect.near(x, k.x, 1e-9)
	expect.near(y, k.y - 0.035 - t.intoShort, 1e-9)
	-- lying along the throw its near face is half a kubb's length short of its centre
	k.pose.angle = math.pi / 2
	x, y = autothrow.spot(s, 1)
	expect.near(y, k.y - 0.075 - t.intoShort, 1e-9)
	-- a line (fewer than clusterFrom kubbs): in front of the front kubb, so the line grows
	local back, front = lie("f1", 1.9, 4.9, math.pi / 2), lie("f2", 1.92, 4.74, math.pi / 2)
	s = toss { back, front }
	s.of = 3
	x, y = autothrow.spot(s, 1)
	expect.near(x, front.x, 1e-9)
	expect.near(y, front.y - 0.075 - t.intoShort, 1e-9)
	-- a cluster: in front of the kubb whose aim is nearest the group's middle
	local a1, a2, a3 = lie("f1", 1.70, 4.95, 0), lie("f2", 1.85, 4.80, 0), lie("f3", 2.0, 4.95, 0)
	s = toss { a1, a2, a3 }
	s.of = 5
	x, y = autothrow.spot(s, 1)
	expect.truthy(x == a1.x or x == a3.x, "beside the front kubb, into the cluster's middle")
	expect.near(y, 4.95 - 0.035 - t.intoShort, 1e-9)
	-- never aimed where it would come down on another kubb: a kubb lying in the
	-- lane short of the aim blocks it (the clear spots take over)
	local blocker = lie("f2", k.x, k.y - 0.3, 0)
	k.pose.angle = 0
	s = toss { k, blocker }
	s.of = 2
	x, y = autothrow.spot(s, 1)
	expect.truthy(not (math.abs(x - k.x) < 1e-9 and math.abs(y - (k.y - 0.035 - t.intoShort)) < 1e-9),
		"not in front of the kubb behind the blocker")
	-- a standing field kubb is never aimed into, and never thrown over
	local standing = { id = "f1", kind = "kubb", role = "field", half = "B", x = t.basketX, y = t.basketY - 0.3,
		toppled = false, pose = { x = t.basketX, y = t.basketY - 0.3, standing = true, angle = 0 } }
	s = toss { standing }
	s.of = 2
	x, y = autothrow.spot(s, 1)
	expect.truthy(math.abs(x - standing.x) >= t.spotLane or y < standing.y or y - standing.y >= t.spotShortStanding,
		"not in the lane just past a standing kubb")
end)

test("a baton aims down the lane with the most field kubbs, not at the nearest", function()
	local function f(id, x, y) return { id = id, kind = "kubb", role = "field", half = "B", x = x, y = y } end
	local s = { kind = "baton", side = "A", lineY = 0, forwardY = 0, batonId = "baton1",
		targets = { "n", "c1", "c2", "c3" },
		pieces = { f("n", -1.0, 4.9), f("c1", 1.90, 5.2), f("c2", 1.94, 5.4), f("c3", 1.88, 5.65) } }
	local a = autothrow.choose(s, autothrow.rng(1), 0)
	-- the front kubb of the three in line, across the middle of the lane
	expect.near(a.plan.ty, 5.2, 1e-9)
	expect.near(a.plan.tx, (1.88 + 1.94) / 2, 1e-9)
	-- alone or tied, the nearest
	s.targets = { "n", "c3" }
	a = autothrow.choose(s, autothrow.rng(1), 0)
	expect.near(a.plan.tx, -1.0, 1e-9)
	expect.near(a.plan.ty, 4.9, 1e-9)
end)

test("the computer's swing mistakes do not grow with range; its nerves do", function()
	local t = autothrow.tune
	local function off(s, seed)
		local clean = autothrow.choose(s, autothrow.rng(seed), 0)
		local a = autothrow.choose(s, autothrow.rng(seed), 1)
		return math.abs(a.swing.back - clean.swing.back), a.launch
	end
	-- same seed, same draw: the swing's error no longer scales with the range
	local far, Lf = off(baton("base", 0, 8), 5)
	local near, Ln = off(baton("field", 0, 3.5, 0), 5)
	expect.truthy(far > 0)
	expect.near(near, far, 1e-6)
	-- the shared nerves are wider for the longer throw
	expect.truthy(Lf.sdSide > Ln.sdSide)
	expect.truthy(t.drillScale < 1)
	-- the clean throw has no nerves either
	local clean = autothrow.choose(baton("base", 0, 8), autothrow.rng(5), 0)
	expect.near(clean.launch.sideDeg, 0, 1e-12)
	expect.near(clean.launch.lenShare, 0, 1e-12)
end)
