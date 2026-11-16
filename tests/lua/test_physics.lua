-- Stage 2 physics (DESIGN 5). Outcomes are checked with tolerances: the
-- device runs 32-bit floats, the desktop doubles.
import "core/world"
import "core/playback"
import "core/quat"
local world, body, quat, playback = tw.world, tw.body, tw.quat, tw.playback
local collide = tw.collide

local G = 9.81
local function tiltDeg(b) return math.deg(math.acos(math.min(1, math.abs(b.r33)))) end

-- A standing kubb (or king) at the origin, woken with a horizontal impulse J
-- (N s, toward +y) at the middle of its top face.
local function topImpulse(kind, J, surface)
	local w = world.new{ texture = false, surface = surface, pieces = { { id = "k", kind = kind, x = 0, y = 0 } } }
	local b = w.byId.k
	world.wake(b)
	b.vy = J / b.m
	b.wx, b.wy, b.wz = body.invInertiaMul(b, -b.hz * J, 0, 0)
	world.run(w)
	return b, w
end

-- A kubb at rest with its long axis along the velocity, arriving at the ground
-- at `land` degrees below horizontal and speed v, with spin about its long axis.
local function kubbLanding(surface, land, v, spin)
	local e = math.rad(land)
	local zx, zy, zz = 0, math.cos(e), -math.sin(e)
	local qw, qx, qy, qz = quat.fromAxes(1, 0, 0, 0, -zz, zy, zx, zy, zz)
	local w = world.new{ texture = false, surface = surface }
	local b = world.launch(w, "kubb", "p", 0, 0, 0.25, qw, qx, qy, qz,
		0, v * math.cos(e), -v * math.sin(e), spin * zx, spin * zy, spin * zz)
	local before, after
	local last = world.energy(w)
	while not world.isAtRest(w) do
		world.step(w)
		if w.firstContact and not before then before = last end
		if before and not after and w.time >= w.firstContact.t + 0.1 then after = world.energy(w) end
		last = world.energy(w)
	end
	local fc = w.firstContact
	return b, w, math.sqrt((b.x - fc.x) ^ 2 + (b.y - fc.y) ^ 2), before, after
end

test("a kubb dropped flat lands, stands, sleeps and stays put for 10 s", function()
	for _, kind in ipairs { "kubb", "king" } do
		local w = world.new{ texture = false,}
		local k = body.kinds[kind]
		world.launch(w, kind, "k", 0.3, 2, k.hz + 0.10, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0)
		local b = w.byId.k
		local slept
		for _ = 1, 10 * 240 do
			world.step(w)
			if not b.awake then slept = slept or w.time end
			expect.truthy(b.z > k.hz - 0.002, kind .. " sank to " .. b.z)
		end
		expect.truthy(slept and slept < 2, kind .. " never slept")
		expect.near(b.z, k.hz, 0.002, kind .. " rest height")
		expect.near(b.x, 0.3, 0.005, kind .. " x")
		expect.near(b.y, 2, 0.005, kind .. " y")
		expect.truthy(not b.toppled and tiltDeg(b) < 1, kind .. " stands")
	end
end)

test("energy never grows: free flight, a tumbling landing, and at rest", function()
	-- a kubb tumbling about all three axes, high in the air for 0.3 s
	local w = world.new{ texture = false,}
	world.launch(w, "kubb", "k", 0, 0, 3, quat.normalize(0.9, 0.2, 0.3, 0.1), 1, 2, 3, 5, -7, 9)
	local e0 = world.energy(w)
	for _ = 1, 72 do
		world.step(w)
		expect.truthy(world.energy(w) <= e0 + 1e-6 * e0, "free flight energy " .. world.energy(w) .. " > " .. e0)
	end
	-- then onto the ground: never above where it started, and it comes to rest
	local peak = 0
	for _ = 1, 10 * 240 do
		world.step(w)
		local e = world.energy(w)
		if e > peak then peak = e end
	end
	expect.truthy(peak <= e0 + 1e-3, "energy rose to " .. peak .. " from " .. e0)
	local b = w.byId.k
	expect.truthy(not b.awake, "came to rest")
	expect.truthy(body.lowestZ(b) > -0.002, "not sunk: lowest " .. body.lowestZ(b))
	-- a baton lying on the ground keeps exactly its rest energy
	local w2 = world.new{ texture = false, pieces = { { id = "b", kind = "baton", x = 0, y = 3, yaw = 0.4 } } }
	world.wake(w2.byId.b)
	local rest = world.energy(w2)
	for _ = 1, 240 do
		world.step(w2)
		expect.truthy(world.energy(w2) <= rest + 1e-4, "lying baton gained energy")
	end
end)

-- Tipping a standing kubb over its bottom edge lifts its center of mass from
-- hz to d = sqrt(hy^2 + hz^2): E = m g (d - hz).
--   kubb: 0.40 * 9.81 * (0.08276 - 0.075) = 0.0305 J
--   king: 1.2 * 9.81 * (0.15653 - 0.15) = 0.0777 J
-- A short horizontal impulse J at the top edge height (2 hz) about the
-- pivoting bottom edge gives angular speed J 2hz / I_edge, so the analytic
-- threshold is J = sqrt(2 E I_edge) / (2 hz):
--   kubb: I_edge = 0.003653 kg m^2, J = 0.0995 N s
--   king: I_edge = 0.03564 kg m^2,  J = 0.2604 N s
-- Measured with this solver (bisection, grass and sand alike): kubb 0.1015,
-- king 0.2648 N s, 2 % above (the impulse here acts at the center of the top
-- face of a free box, so a little goes into sliding the base).
local function threshold(kind)
	local lo, hi = 0.02, 0.6
	for _ = 1, 16 do
		local mid = (lo + hi) / 2
		if topImpulse(kind, mid).toppled then hi = mid else lo = mid end
	end
	return (lo + hi) / 2
end

local function analytic(kind)
	local k = body.kinds[kind]
	local d = math.sqrt(k.hy ^ 2 + k.hz ^ 2)
	local E = k.mass * G * (d - k.hz)
	local Iedge = k.mass * ((2 * k.hy) ^ 2 + (2 * k.hz) ^ 2) / 12 + k.mass * d * d
	return math.sqrt(2 * E * Iedge) / (2 * k.hz), E
end

test("a small top impulse rocks a kubb and it stands; a larger one topples it", function()
	local soft = topImpulse("kubb", 0.08)
	expect.truthy(not soft.toppled, "0.08 N s toppled it")
	expect.truthy(tiltDeg(soft) < 1, "stood back up, tilt " .. tiltDeg(soft))
	expect.truthy(soft.everAwake and not soft.awake, "rocked and went back to sleep")
	local hard = topImpulse("kubb", 0.13)
	expect.truthy(hard.toppled, "0.13 N s did not topple it")
	local Ja, E = analytic("kubb")
	expect.near(Ja, 0.0995, 0.0005, "analytic kubb threshold")
	expect.near(E, 0.0305, 0.0005, "analytic kubb tipping energy")
	local Jm = threshold("kubb")
	expect.truthy(Jm >= Ja * 0.97 and Jm <= Ja * 1.06, string.format("measured %.4f vs analytic %.4f", Jm, Ja))
end)

test("the king is harder to topple than a kubb", function()
	expect.truthy(topImpulse("kubb", 0.2).toppled, "kubb at 0.2 N s")
	expect.truthy(not topImpulse("king", 0.2).toppled, "king at 0.2 N s")
	local Ja = analytic("king")
	expect.near(Ja, 0.2604, 0.0005, "analytic king threshold")
	local Jm = threshold("king")
	expect.truthy(Jm >= Ja * 0.97 and Jm <= Ja * 1.06, string.format("measured %.4f vs analytic %.4f", Jm, Ja))
end)

-- Three kubbs in a line with 10 cm gaps (0.17 m center to center). The
-- first is set turning about its front bottom edge at 12 rad/s. Each passes
-- its tipping angle (25 degrees) after the one before, and all end down.
-- With 3 cm gaps (0.10 m centers) nothing falls in this solver: the first
-- kubb reaches the second at 11 degrees, before its own tipping point, and
-- rebounds (see the stage 2 report).
test("a three-kubb domino line falls in order", function()
	local sp = 0.17
	local pieces = {}
	for i = 1, 3 do pieces[i] = { id = "k" .. i, kind = "kubb", x = 0, y = (i - 1) * sp } end
	local w = world.new{ texture = false, pieces = pieces }
	local a = w.byId.k1
	world.wake(a)
	local om = 12
	a.wx, a.vy, a.vz = -om, om * a.hz, om * a.hy
	local past = {}
	while not world.isAtRest(w) do
		world.step(w)
		for i = 1, 3 do
			if not past[i] and tiltDeg(w.byId["k" .. i]) > 30 then past[i] = w.time end
		end
	end
	expect.truthy(past[1] and past[2] and past[3], "not all passed 30 degrees")
	expect.truthy(past[1] < past[2] and past[2] < past[3], string.format("order %s %s %s", past[1], past[2], past[3]))
	for i = 1, 3 do expect.truthy(w.byId["k" .. i].toppled, "k" .. i .. " toppled") end
	local r = world.result(w)
	expect.eq(#r.toppled, 3, "result counts three")
end)

-- Four kubbs standing face to face in a row along y (Jamie, 2026-11-15: a
-- baton bounced off a tight row of field kubbs). `order` lists which kubb of
-- the row each body index holds, so the front kubb can be first or last.
local function tightRow(order)
	local pieces = {}
	for i, k in ipairs(order) do pieces[i] = { id = "k" .. k, kind = "kubb", x = 0, y = 4 + (k - 1) * 0.07 } end
	local w = world.new{ texture = false, pieces = pieces }
	return w
end
-- A blow of J N s toward +y at height h on a standing kubb's near face.
local function blow(a, J, h)
	world.wake(a)
	local tx = -(h - a.hz) * J
	a.vy = J * a.im
	a.wx, a.wy, a.wz = a.i11 * tx, a.i12 * tx, a.i13 * tx
end

test("a blow on the front kubb of a touching row wakes the whole row in that step", function()
	for _, order in ipairs{ { 1, 2, 3, 4 }, { 4, 3, 2, 1 }, { 3, 1, 4, 2 } } do
		local w = tightRow(order)
		blow(w.byId.k1, 1.0, 0.13)
		world.step(w)
		local p = 0
		for k = 1, 4 do
			local b = w.byId["k" .. k]
			expect.truthy(b.awake, "k" .. k .. " awake after one step, order " .. table.concat(order))
			p = p + b.m * b.vy
		end
		-- a sleeper is a wall to the solver: with the row asleep the blow went
		-- into it and under a tenth of it was left after this step
		expect.truthy(p > 0.5, string.format("the row keeps the blow: %.2f of 1.0 N s", p))
		expect.truthy(w.byId.k4.vy > 0.1, "the last kubb is moving")
	end
end)

-- With one wood-on-wood friction for every pair (0.4, 2026-11-16; kubb on
-- kubb was 0.2 before), a hard blow fells two or three of the four: the
-- kubbs lean on each other face to face and the rub holds some of them.
test("a hard blow on the front kubb of a touching row fells most of the row; a tap none", function()
	for _, order in ipairs{ { 1, 2, 3, 4 }, { 4, 3, 2, 1 } } do
		local w = tightRow(order)
		blow(w.byId.k1, 2.0, 0.13)
		world.run(w)
		local r = world.result(w)
		expect.truthy(#r.toppled >= 3, "three or more down, order " .. table.concat(order) .. ": " .. #r.toppled)
		local far = false
		for _, id in ipairs(r.toppled) do if id == "k4" then far = true end end
		expect.truthy(far, "the far kubb falls, order " .. table.concat(order))
	end
	local w = tightRow{ 1, 2, 3, 4 }
	blow(w.byId.k1, 0.2, 0.13)
	world.run(w)
	expect.eq(#world.result(w).toppled, 0, "a tap leaves the row standing")
end)

-- Edge on edge (collide.boxBox): two boxes touching where their edges cross,
-- with no corner of either inside the other.
test("a kubb lying across a lying kubb rests on it at any angle", function()
	for _, deg in ipairs{ 30, 60, 90 } do
		local a1, b1, c1, d1 = quat.fromAxisAngle(0, 1, 0, math.pi / 2)
		local yw, yx, yy, yz = quat.fromAxisAngle(0, 0, 1, math.rad(deg))
		local e, f, g, h = quat.mul(yw, yx, yy, yz, a1, b1, c1, d1)
		local w = world.new{ texture = false, stakes = false, pieces = {
			{ id = "lo", kind = "kubb", x = 0, y = 0, qw = a1, qx = b1, qy = c1, qz = d1, z = 0.035 },
			{ id = "hi", kind = "kubb", x = 0, y = 0, qw = e, qx = f, qy = g, qz = h, z = 0.115 },
		} }
		local hi = w.byId.hi
		world.wake(hi)
		for _ = 1, 240 do world.step(w) end
		-- it fell straight through to the ground before (z 0.035)
		expect.near(hi.z, 0.105, 0.002, "rests on the lower kubb at " .. deg .. " degrees")
	end
end)

test("a kubb tipped into a neighbour turned on the ground does not sink into it", function()
	local function deepest(P, Q)
		local SX, SY, SZ = collide.SX, collide.SY, collide.SZ
		local worst = 0
		for k = 1, 8 do
			for m = k + 1, 8 do
				if (SX[k] ~= SX[m] and 1 or 0) + (SY[k] ~= SY[m] and 1 or 0) + (SZ[k] ~= SZ[m] and 1 or 0) == 1 then
					for s = 0, 20 do
						local t = s / 20
						local lx = (SX[k] + (SX[m] - SX[k]) * t) * P.hx
						local ly = (SY[k] + (SY[m] - SY[k]) * t) * P.hy
						local lz = (SZ[k] + (SZ[m] - SZ[k]) * t) * P.hz
						local d = collide.pointBox(Q, P.x + P.r11 * lx + P.r12 * ly + P.r13 * lz,
							P.y + P.r21 * lx + P.r22 * ly + P.r23 * lz, P.z + P.r31 * lx + P.r32 * ly + P.r33 * lz)
						if -d > worst then worst = -d end
					end
				end
			end
		end
		return worst
	end
	for _, yaw in ipairs{ 30, 45, 60 } do
		local qw, qx, qy, qz = quat.fromAxisAngle(0, 0, 1, math.rad(yaw))
		local w = world.new{ texture = false, stakes = false, pieces = {
			{ id = "a", kind = "kubb", x = 0, y = 0 },
			{ id = "b", kind = "kubb", x = 0.02, y = 0.114, qw = qw, qx = qx, qy = qy, qz = qz },
		} }
		local a, b = w.byId.a, w.byId.b
		world.wake(a)
		a.wx, a.vy, a.vz = -6, 6 * a.hz, 6 * a.hy
		local worst = 0
		for _ = 1, 480 do
			world.step(w)
			worst = math.max(worst, deepest(a, b), deepest(b, a))
		end
		-- an edge sank up to 18 mm into the other kubb before
		expect.truthy(worst < 0.003, string.format("deepest %.1f mm at yaw %d", worst * 1000, yaw))
	end
end)

test("a kubb woken far from the others wakes nobody", function()
	local w = world.new{ texture = false, pieces = {
		{ id = "k1", kind = "kubb", x = 0, y = 4 }, { id = "k2", kind = "kubb", x = 0, y = 4.3 } } }
	blow(w.byId.k1, 0.05, 0.13)
	world.step(w)
	expect.truthy(not w.byId.k2.awake, "k2 sleeps on")
end)

-- Codex on the web game's sync of the group wake: two sleepers that touch each
-- other, both woken in one step by a third body, are a pair the loop passed
-- while both slept; their contact must still be made in that step, once.
test("two touching sleepers woken in one step get their own contact in that step", function()
	local collide = tw.collide
	local function between(order)
		local at = { s = { 0, 3.93 }, a = { -0.035, 4 }, b = { 0.035, 4 }, c = { -0.035, 4.07 }, d = { 0.035, 4.07 } }
		local pieces = {}
		for i, id in ipairs(order) do pieces[i] = { id = id, kind = "kubb", x = at[id][1], y = at[id][2] } end
		local w = world.new{ texture = false, stakes = false, pieces = pieces }
		blow(w.byId.s, 1.0, 0.13)
		world.step(w)
		local C, n = collide.C, {}
		for i = 1, C.n do
			local A, B = C.A[i], C.B[i]
			if A and B and A.id and B.id then
				local key = A.id < B.id and (A.id .. B.id) or (B.id .. A.id)
				n[key] = (n[key] or 0) + 1
			end
		end
		for _, id in ipairs(order) do expect.truthy(w.byId[id].awake, id .. " awake, order " .. table.concat(order)) end
		return n
	end
	-- with the striker first the pair loop comes to every pair with one awake
	local ref = between{ "s", "a", "b", "c", "d" }
	expect.truthy((ref.ab or 0) > 0 and (ref.cd or 0) > 0, "the reference has the pairs' contacts")
	for _, order in ipairs{ { "a", "b", "s", "c", "d" }, { "a", "b", "c", "d", "s" }, { "d", "c", "b", "a", "s" }, { "c", "a", "s", "d", "b" } } do
		local n = between(order)
		-- the count of points can differ (a kubb woken earlier in the loop has a
		-- wider margin); two boxes face to face never have more than 8
		for key in pairs(ref) do
			local got = n[key] or 0
			expect.truthy(got > 0 and got <= 8, "contacts of " .. key .. ": " .. got .. ", order " .. table.concat(order))
		end
		for key in pairs(n) do expect.truthy(ref[key], "no extra pair " .. key) end
	end
end)

-- The tests' launch speeds were written for a flight with no drag (before
-- 2026-11-16, audit 8): the speed that carries a baton as far at this loft
-- through still air with its drag, so they land where they were written to.
local function aimed(v, loft)
	local flight = tw.flight
	local ft, e = flight.tune, math.rad(loft)
	return flight.speedForCarry(flight.carry(v, e, ft.handHeight, 0), e, ft.handHeight, ft.dragK.baton)
end

local function batonThrow(surface, x, speed, pieces, rate)
	local w = world.new{ texture = false, surface = surface, pieces = pieces }
	local b = world.launchBaton(w, x, 0, 0, 35, aimed(speed, 35), rate or 7, 0)
	local w0 = math.sqrt(b.wx ^ 2 + b.wy ^ 2 + b.wz ^ 2)
	local wc
	while not world.isAtRest(w) do
		world.step(w)
		if w.firstContact and not wc then
			-- spin on the step before first contact is the one we want; the
			-- contact step changes it, so read the stored pre-contact value
			wc = w.preContactSpin
		end
		if not w.firstContact then w.preContactSpin = math.sqrt(b.wx ^ 2 + b.wy ^ 2 + b.wz ^ 2) end
	end
	return w, b, w0, wc
end

test("a baton thrown end over end from 8 m on target topples a base kubb", function()
	local kubb = { { id = "k", kind = "kubb", x = 0, y = 8 } }
	local w, b, w0, wc = batonThrow("grass", 0, 8.5, kubb)
	local r = world.result(w)
	expect.truthy(w.firstHit and w.firstHit.with == "k", "baton hit the kubb first")
	expect.truthy(r.bodies.k.toppled, "kubb toppled")
	expect.eq(r.toppled[1], "k", "result lists it")
	-- the tumble rate over the flight matches the launch (torque-free)
	expect.near(wc, w0, 0.02 * w0, "spin at first contact vs launch")
	-- 30 cm wide it misses, and the kubb never wakes
	local w2 = batonThrow("grass", 0.30, 8.5, { { id = "k", kind = "kubb", x = 0, y = 8 } })
	local k2 = w2.byId.k
	expect.truthy(not k2.everAwake and not k2.touched and not k2.toppled, "a miss leaves it asleep")
end)

test("a baton landing short slides on grass and stops much sooner on sand", function()
	local function travel(surface)
		local w, b = batonThrow(surface, 0, 6.5)
		local fc = w.firstContact
		return b.y - fc.y, b
	end
	local g, gb = travel("grass")
	local s, sb = travel("sand")
	expect.truthy(g > 0.5, "grass travel " .. g)
	expect.truthy(s < g - 0.5, string.format("sand %.2f vs grass %.2f", s, g))
	expect.truthy(not gb.awake and not sb.awake, "both came to rest")
	expect.truthy(body.lowestZ(gb) > -0.003 and body.lowestZ(sb) > -0.003, "on the ground, not in it")
end)

test("a thrown kubb lands, loses energy and rests on grass and sand", function()
	for _, s in ipairs { "grass", "sand" } do
		local b, w = kubbLanding(s, 35, 7, 0)
		expect.truthy(not b.awake, s .. " at rest")
		expect.truthy(world.energy(w) < 0.5, s .. " rest energy " .. world.energy(w))
		expect.truthy(body.lowestZ(b) > -0.003, s .. " not sunk")
	end
end)

test("a steep nose-down kubb landing loses more and travels less than a shallow lob", function()
	for _, s in ipairs { "grass", "sand" } do
		local _, _, steepTravel, sb, sa = kubbLanding(s, 70, 7, 0)
		local _, _, flatTravel, fb, fa = kubbLanding(s, 20, 7, 0)
		local steepLoss, flatLoss = 1 - sa / sb, 1 - fa / fb
		expect.truthy(steepLoss > flatLoss, string.format("%s energy lost in 0.1 s: steep %.2f flat %.2f", s, steepLoss, flatLoss))
		expect.truthy(steepTravel < flatTravel, string.format("%s travel: steep %.2f flat %.2f", s, steepTravel, flatTravel))
	end
end)

test("spin about a thrown kubb's long axis carries it sideways, less on sand", function()
	local function drift(surface, spin)
		local b = kubbLanding(surface, 45, 6, spin)
		return b.x
	end
	local gp, gm = drift("grass", 25), drift("grass", -25)
	local sp, sm = drift("sand", 25), drift("sand", -25)
	expect.truthy(math.abs(gp) > 0.1 and math.abs(gm) > 0.1, string.format("grass drift %.2f %.2f", gp, gm))
	expect.truthy(gp * gm < 0, "opposite spin, opposite side")
	expect.truthy(math.abs(sp) < 0.6 * math.abs(gp) and math.abs(sm) < 0.6 * math.abs(gm),
		string.format("sand %.2f %.2f vs grass %.2f %.2f", sp, sm, gp, gm))
end)

test("the same throw twice gives the same result", function()
	local function once()
		local w = batonThrow("grass", 0.05, 8.4, {
			{ id = "a", kind = "kubb", x = 0, y = 8 }, { id = "b", kind = "kubb", x = 0.5, y = 8 },
		})
		local r = world.result(w)
		return r.bodies.a, r.bodies.baton, r.steps
	end
	local a1, b1, n1 = once()
	local a2, b2, n2 = once()
	expect.eq(n1, n2, "steps")
	for _, f in ipairs { "x", "y", "z", "qw", "qx", "qy", "qz" } do
		expect.eq(a1[f], a2[f], "kubb " .. f)
		expect.eq(b1[f], b2[f], "baton " .. f)
	end
end)

test("playback poses equal the stepped poses", function()
	local function build()
		local w = world.new{ texture = false, pieces = { { id = "k", kind = "kubb", x = 0, y = 8 }, { id = "f", kind = "kubb", x = 1, y = 4 } } }
		world.launchBaton(w, 0, 0, 0, 35, aimed(8.5, 35), 7, 0)
		return w
	end
	-- the reference: step and note the poses at each display frame
	local ref, wr = {}, build()
	local frameDt = 1 / 50
	local f = 0
	ref[0] = { wr.byId.k.x, wr.byId.baton.y, wr.byId.baton.qx }
	while not world.isAtRest(wr) do
		world.step(wr)
		while wr.time + world.tune.dt * 0.5 >= (f + 1) * frameDt do
			f = f + 1
			ref[f] = { wr.byId.k.x, wr.byId.baton.y, wr.byId.baton.qx }
		end
	end
	-- the playback, advanced in small clock budgets like the device
	local w = build()
	local pb = playback.new(w, frameDt)
	local tick = 0
	local function clock() tick = tick + 0.001; return tick end
	while not pb.done do playback.advance(pb, 0.005, clock) end
	local ki, bi = w.byId.k.index, w.byId.baton.index
	for i = 0, f do
		local kx = playback.pose(pb, ki, i)
		local _, by, _, _, bqx = playback.pose(pb, bi, i)
		expect.eq(kx, ref[i][1], "kubb x at frame " .. i)
		expect.eq(by, ref[i][2], "baton y at frame " .. i)
		expect.eq(bqx, ref[i][3], "baton qx at frame " .. i)
	end
	-- the far field kubb never woke: nothing recorded for it
	expect.eq(#pb.rec[w.byId.f.index].data, 0, "sleeping kubb stores nothing")
	local fx, fy = playback.pose(pb, w.byId.f.index, 10)
	expect.eq(fx, 1, "sleeping kubb x")
	expect.eq(fy, 4, "sleeping kubb y")
end)

test("the bench scenario hits the group", function()
	import "core/bench"
	local r = tw.bench.run(os.clock)
	expect.eq(r.steps, 720, "3 s at 240 Hz")
	expect.truthy(r.maxAwake >= 4, "awake bodies " .. r.maxAwake)
end)

test("a baton landing at 8 m/s kicks on 0.5 to 2.5 m on grass, much less on sand", function()
	-- Jamie on hardware: the baton should not die on landing on a lawn
	local function kick(surface)
		local w, b = batonThrow(surface, 0, 8)
		return b.y - w.firstContact.y
	end
	local g, s = kick("grass"), kick("sand")
	expect.truthy(g >= 0.5 and g <= 2.5, string.format("grass kick %.2f m", g))
	expect.truthy(s < 0.5 * g, string.format("sand kick %.2f m vs grass %.2f", s, g))
end)

test("a baton thrown at a corner stake deflects off it", function()
	-- along the right sideline at the far corner stake (2.5, 8)
	local function land(stakes)
		local w = world.new{ texture = false, stakes = stakes }
		local b = world.launchBaton(w, 2.5, 0, 0, 35, aimed(8.5, 35), 7, 0)
		world.run(w)
		return b, world.result(w), w
	end
	local free = land(false)
	local b, r, w = land(true)
	expect.truthy(w.firstHit and w.firstHit.with == "stake6", "hit the corner stake first")
	expect.eq(r.stakesTouched[1], "stake6", "result names the stake")
	expect.truthy(b.y < free.y - 1, string.format("stopped short: %.2f vs %.2f without the stake", b.y, free.y))
	local s = w.byId.stake6
	expect.eq(s.x, 2.5, "the stake did not move")
	expect.eq(s.y, 8, "the stake did not move")
end)

test("a sliding kubb stops against a stake", function()
	local function slide(stakes)
		local w = world.new{ texture = false, stakes = stakes }
		-- lying across the pitch line, sliding up the sideline at 3 m/s
		local qw, qx, qy, qz = quat.fromAxisAngle(0, 1, 0, math.pi / 2)
		local b = world.launch(w, "kubb", "k", 2.5, 3.5, 0.035, qw, qx, qy, qz, 0, 3, 0, 0, 0, 0)
		world.run(w)
		return b, world.result(w)
	end
	local free = slide(false)
	local b, r = slide(true)
	expect.truthy(free.y > 4.1, "without the stake it slides past 4: " .. free.y)
	expect.truthy(b.y < 4 - 0.03, "stopped before the centerline stake: " .. b.y)
	expect.eq(r.stakesTouched[1], "stake4", "touched stake4")
	expect.truthy(not b.awake, "came to rest")
end)

-- The leaner rule: a piece propped on another is down if it would fall with
-- the prop taken away (the plumb line through its centre misses its base).
test("would-fall: a kubb goes past about 25 degrees, the king past about 17", function()
	local function leaning(kind, deg, about)
		local qw, qx, qy, qz
		if about == "x" then qw, qx, qy, qz = quat.fromAxisAngle(1, 0, 0, math.rad(deg))
		else qw, qx, qy, qz = quat.fromAxisAngle(0, 1, 0, math.rad(deg)) end
		local w = world.new{ texture = false, pieces = { { id = "k", kind = kind, x = 0, y = 0, qw = qw, qx = qx, qy = qy, qz = qz } } }
		return w.byId.k
	end
	for _, about in ipairs { "x", "y" } do
		expect.truthy(not body.wouldFall(leaning("kubb", 0, about)), "upright kubb")
		expect.truthy(not body.wouldFall(leaning("kubb", 20, about)), "kubb at 20")
		expect.truthy(body.wouldFall(leaning("kubb", 30, about)), "kubb at 30")
		expect.truthy(not body.wouldFall(leaning("kubb", 180, about)), "kubb on its other end")
		expect.truthy(not body.wouldFall(leaning("kubb", 160, about)), "kubb on its other end at 20")
		expect.truthy(not body.wouldFall(leaning("king", 12, about)), "king at 12")
		expect.truthy(body.wouldFall(leaning("king", 22, about)), "king at 22")
	end
	-- a piece put on the pitch already leaning that far counts as down
	expect.truthy(leaning("kubb", 30, "x").toppled, "placed leaner is down")
	expect.truthy(not leaning("kubb", 20, "x").toppled, "placed at 20 stands")
end)

test("a kubb that comes to rest leaning on a fallen kubb is down", function()
	local lw, lx, ly, lz = quat.fromAxisAngle(0, 1, 0, math.pi / 2)
	local w = world.new{ texture = false, pieces = {
		{ id = "k", kind = "kubb", x = 0, y = 0 },
		{ id = "prop", kind = "kubb", x = 0, y = 0.20, qw = lw, qx = lx, qy = ly, qz = lz },
	} }
	local a = w.byId.k
	world.wake(a)
	local om = 6
	a.wx, a.vy, a.vz = -om, om * a.hz, om * a.hy
	local early
	while not world.isAtRest(w) do
		world.step(w)
		if a.awake and a.toppled then early = true end
	end
	local tilt = tiltDeg(a)
	expect.truthy(tilt > 30 and tilt < 80, "rests propped, at " .. tilt)
	expect.truthy(not early, "counted down only once it came to rest")
	expect.truthy(a.toppled, "the leaner is down")
	local r = world.result(w)
	expect.eq(#r.toppled, 1, "result lists one")
	expect.eq(r.toppled[1], "k", "and it is the leaner")
end)
