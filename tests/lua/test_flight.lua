import "core/flight"
import "core/swing"
local flight = tw.flight
local swing = tw.swing

local MID = flight.tune.loftDefaultDeg
-- reference speeds (m/s): the old swing's full and softest throws, which these
-- flight tests were written for
local FULL, SOFT = 9.2, 4.0

local function fly(x, swivel, loft, speed, rate, tilt)
	local fl = flight.new()
	flight.launch(fl, x, 0, swivel, loft, speed, rate or 7, tilt or 0)
	local steps = 0
	while not flight.step(fl, 1 / 50) do
		steps = steps + 1
		assert(steps < 1000, "never landed")
	end
	return fl
end

test("full power at mid loft carries about 8 to 9 m", function()
	local fl = fly(0, 0, MID, FULL)
	expect.truthy(fl.y >= 8 and fl.y <= 9.3, "landed at " .. fl.y)
	expect.near(fl.x, 0, 1e-9)
	expect.truthy(fl.t >= 0.8 and fl.t <= 1.3, "flight time " .. fl.t)
end)

test("minimum power lands short of 3 m at any loft", function()
	for loft = flight.tune.loftMinDeg, flight.tune.loftMaxDeg, flight.tune.loftStepDeg do
		local fl = fly(0, 0, loft, SOFT)
		expect.truthy(fl.y < 3, "loft " .. loft .. " landed at " .. fl.y)
	end
end)

test("a typical full throw turns 1 to 1.5 times over 8 m", function()
	local fl = flight.new()
	flight.launch(fl, 0, 0, 0, MID, FULL, 7.0, 0)
	while fl.y < 8 and not fl.landed do flight.step(fl, 1 / 200) end
	local turns = flight.turns(fl)
	expect.truthy(turns >= 1 and turns <= 1.5, "turns " .. turns)
end)

test("landing prediction matches the stepped flight", function()
	for _, c in ipairs { { 0, 0, 15, 9.2 }, { 1.5, math.rad(-20), 35, 8 }, { -2, math.rad(30), 55, 5 } } do
		local x, sw, loft, v = c[1], c[2], c[3], c[4]
		local lx, ly, T = flight.predict(x, 0, sw, loft, v)
		local fl = fly(x, sw, loft, v)
		expect.near(fl.x, lx, 0.01, "x")
		expect.near(fl.y, ly, 0.01, "y")
		expect.near(fl.t, T, 0.005, "time")
		expect.truthy(fl.landed and fl.z == 0, "stopped on the ground")
		expect.near(flight.distance(fl), math.sqrt((lx - x) ^ 2 + ly ^ 2), 0.01, "distance")
	end
end)

test("swivel sets the direction; the hand is 0.6 m up at the player's x", function()
	local fl = flight.new()
	flight.launch(fl, 1.2, 0, math.rad(-20), MID, 8, 7, 0)
	expect.near(fl.x, 1.2, 1e-9); expect.near(fl.z, 0.6, 1e-9)
	expect.truthy(fl.vx < 0 and fl.vy > 0, "heads left and downfield")
	expect.near(math.atan(-fl.vx, fl.vy), math.rad(20), 1e-9)
end)

test("baton axis: upright at release, end over end when clean, flat when a helicopter", function()
	local fl = flight.new()
	flight.launch(fl, 0, 0, 0, MID, 9, 7, 0)
	local ax, ay, az = flight.axis(fl)
	expect.near(az, 1, 1e-9, "upright in the hand")
	for _ = 1, 20 do
		flight.step(fl, 1 / 50)
		ax, ay, az = flight.axis(fl)
		expect.near(ax, 0, 1e-9, "a clean throw stays in the vertical plane")
		expect.near(ax * ax + ay * ay + az * az, 1, 1e-9, "unit")
	end
	flight.launch(fl, 0, 0, 0, MID, 9, 7, 90)
	local maxZ = 0
	for _ = 1, 40 do
		flight.step(fl, 1 / 50)
		ax, ay, az = flight.axis(fl)
		maxZ = math.max(maxZ, math.abs(az))
	end
	expect.truthy(maxZ < 0.45, "a helicopter stays near flat, |az| max " .. maxZ)
end)

test("the aim preview is the full-power landing point", function()
	local lx, ly = flight.aimPreview(0, 0, 0, MID, FULL)
	local px, py = flight.predict(0, 0, 0, MID, FULL)
	expect.near(lx, px, 1e-12); expect.near(ly, py, 1e-12)
end)

test("a landed baton lies flat and stops", function()
	local fl = fly(0, 0, MID, 8)
	local x, y = fl.x, fl.y
	expect.eq(flight.step(fl, 0.5), false)
	expect.eq(fl.x, x); expect.eq(fl.y, y)
	local ax, ay, az = flight.axis(fl)
	expect.eq(az, 0)
	expect.near(ax * ax + ay * ay, 1, 1e-9)
end)

