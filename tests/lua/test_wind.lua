-- The air (core/wind, core/world airDrag): still air drags on the thrown
-- piece as flight.carry says, a zero wind is still air, the thrown piece
-- drifts with the wind until its first contact, the lone flight stays
-- identical to the full step, and the match's turns and gusts.
import "core/tw"
import "core/world"
import "core/wind"
import "core/autothrow"

local world, wind, auto = tw.world, tw.wind, tw.autothrow

local function throwBaton(wx, wy, lone)
	local saved = world.loneFlight
	world.loneFlight = lone ~= false
	local w = world.new { surface = "grass", stakes = false, windX = wx, windY = wy, groundSeed = 1 }
	world.launchBaton(w, 0, 0, 0, 30, auto.speedFor(8, 30), 5.5, 0)
	while not w.firstContact do world.step(w) end
	world.loneFlight = saved
	return w
end

test("still air: a zero wind is no wind at all (bit for bit)", function()
	local a = throwBaton(0, 0)
	local b = world.new { surface = "grass", stakes = false, groundSeed = 1 }
	world.launchBaton(b, 0, 0, 0, 30, auto.speedFor(8, 30), 5.5, 0)
	while not b.firstContact do world.step(b) end
	expect.eq(a.firstContact.x, b.firstContact.x)
	expect.eq(a.firstContact.y, b.firstContact.y)
	expect.eq(a.steps, b.steps)
end)

-- Where a baton's center comes down through height z (m) in still air, with
-- its drag or (drag false) none: y by a straight line between steps.
local function crossing(v, loft, z, drag)
	local w = world.new { surface = "grass", stakes = false, groundSeed = 1 }
	local b = world.launchBaton(w, 0, 0, 0, loft, v, 0.001, 0)
	if drag == false then b.dragK = 0 end
	local py, pz
	repeat py, pz = b.y, b.z; world.step(w) until b.z <= z
	return py + (b.y - py) * (pz - z) / (pz - b.z)
end

test("still air drags: a baton carries as much less as flight.carry says, and the aim allows for it", function()
	local flight = tw.flight
	local ft = flight.tune
	for _, loft in ipairs { 15, 30, 45 } do
		local e = math.rad(loft)
		local v = auto.speedFor(8, loft)
		-- an upright baton (the end down) first touches with its center 0.15 m up
		local lost = crossing(v, loft, 0.15, false) - crossing(v, loft, 0.15)
		local want = flight.carry(v, e, ft.handHeight - 0.15, 0) - flight.carry(v, e, ft.handHeight - 0.15, ft.dragK.baton)
		expect.truthy(lost > 0.3 and lost < 0.6, "loft " .. loft .. ": lost " .. lost)
		expect.near(lost, want, 0.01, "loft " .. loft .. ": the world's drag is flight.carry's")
		-- the aim's speed carries the center to 8 m through the drag
		local _, ly = flight.predict(0, 0, 0, loft, v)
		expect.near(ly, 8, 1e-6)
		expect.near(flight.speedForCarry(8, e, ft.handHeight, ft.dragK.baton), v, 1e-6)
	end
end)

test("a cross wind carries the baton its way; a head wind shortens it, a tail wind lengthens it", function()
	local still = throwBaton(0, 0).firstContact
	local right = throwBaton(6, 0).firstContact
	local left = throwBaton(-2.5, 0).firstContact
	expect.truthy(right.x - still.x > 0.3 and right.x - still.x < 0.6, "strong cross " .. (right.x - still.x))
	expect.truthy(still.x - left.x > 0.1 and still.x - left.x < 0.25, "light cross " .. (still.x - left.x))
	local head = throwBaton(0, -6).firstContact
	local tail = throwBaton(0, 6).firstContact
	expect.truthy(head.y < still.y - 0.6, "head " .. head.y)
	expect.truthy(tail.y > still.y + 0.3, "tail " .. tail.y)
end)

test("with wind, the lone flight is still the full step's arithmetic", function()
	local a, b = throwBaton(4, -3, true), throwBaton(4, -3, false)
	expect.eq(a.firstContact.x, b.firstContact.x)
	expect.eq(a.firstContact.y, b.firstContact.y)
	expect.eq(a.firstContact.z, b.firstContact.z)
end)

test("the wind stops pushing at the first contact", function()
	local w = throwBaton(6, 0)
	local b = w.projectile
	local vx = b.vx
	-- the next steps change vx only by contacts and the ground, never the wind:
	-- with the wind off for the same state the step is the same
	local w2 = throwBaton(6, 0)
	w2.windX, w2.windY = 0, 0
	world.step(w); world.step(w2)
	expect.eq(w.projectile.vx, w2.projectile.vx)
	expect.truthy(vx ~= nil)
end)

test("a match's wind: calm when off, a turn's mean by level, gusts near it", function()
	local r = auto.rng(3)
	local d, s = wind.turn(r, "off")
	expect.eq(s, 0)
	expect.eq(wind.text(s), nil)
	for _ = 1, 50 do
		local dir, sp = wind.turn(r, "strong")
		expect.truthy(sp >= 6 * wind.tune.turnLow - 1e-9 and sp <= 6 * wind.tune.turnHigh + 1e-9, "strong " .. sp)
		local _, g = wind.gust(r, dir, sp)
		expect.truthy(math.abs(g - sp) <= sp * wind.tune.gust + 1e-9, "gust " .. g)
	end
	local _, light = wind.turn(r, "light")
	expect.truthy(light > 1 and light < 3.5)
	expect.eq(wind.text(3.6), "WIND 4 M/S")
	expect.eq(wind.text(0.3), "WIND 1 M/S")
end)

test("Team B's view of the wind is turned like the pitch", function()
	local ax, ay = wind.vector(0.5, 4, "A")
	local bx, by = wind.vector(0.5, 4, "B")
	expect.near(bx, -ax, 1e-12)
	expect.near(by, -ay, 1e-12)
	expect.near(ax * ax + ay * ay, 16, 1e-9)
end)
