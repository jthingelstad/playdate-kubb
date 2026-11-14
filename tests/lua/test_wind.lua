-- The wind (core/wind, core/world windForce): still air changes nothing, the
-- thrown piece drifts with the wind until its first contact, the lone flight
-- stays identical to the full step, and the match's turns and gusts.
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
