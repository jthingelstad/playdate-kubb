import "core/camera"
import "core/flight"
import "core/swing"
local camera = tw.camera
local flight = tw.flight
local swing = tw.swing

local FAR = {}
for x = -2, 2 do FAR[#FAR + 1] = { x = x, y = 8 } end

-- Projected width of a kubb's 7 x 7 cm footprint (screen x extent).
local function footprintWidth(c, x, y)
	local lo, hi = math.huge, -math.huge
	for _, dx in ipairs { -0.035, 0.035 } do
		for _, dy in ipairs { -0.035, 0.035 } do
			local sx = camera.project(c, x + dx, y + dy, 0)
			lo, hi = math.min(lo, sx), math.max(hi, sx)
		end
	end
	return hi - lo
end

local POSES = {
	{ 0, 0 }, { 1.5, 0 }, { -1.5, 0 }, { 2.5, 0 }, { -2.5, 0 },
	{ 0, math.rad(20) }, { 0, math.rad(-20) }, { 1.5, math.rad(-10) },
	{ 2.5, math.rad(-25) }, { -2.5, math.rad(25) }, { -2.5, math.rad(35) }, { 2.5, math.rad(-35) },
}

test("far base kubb at (0, 8) is at least 12 px tall and 5 px wide from every aim pose", function()
	local c = camera.new()
	for _, p in ipairs(POSES) do
		camera.aim(c, p[1], 0, p[2], FAR)
		local what = string.format("player %.1f swivel %.0f", p[1], math.deg(p[2]))
		local h = camera.uprightPx(c, 0, 8, 0.15)
		expect.truthy(h >= 12, what .. ": height " .. h)
		local w = footprintWidth(c, 0, 8)
		expect.truthy(w >= 5, what .. ": width " .. w)
		expect.truthy(c.f >= camera.tune.aim.fMin and c.f <= camera.tune.aim.fMax, what .. ": f in range")
	end
end)

test("stepping back from the line keeps the far base kubb at least 12 px tall", function()
	local c = camera.new()
	for _, back in ipairs { 0.5, 1.5, 3.0 } do
		for _, x in ipairs { 0, 2.5, -2.5 } do
			camera.aim(c, x, -back, 0, FAR, back)
			local h = camera.uprightPx(c, 0, 8, 0.15)
			expect.truthy(h >= 12, string.format("back %.1f at x %.1f: height %.2f", back, x, h))
		end
	end
end)

test("every far base kubb is at least 12 px tall unless f is at its clamp", function()
	local c = camera.new()
	for _, p in ipairs(POSES) do
		camera.aim(c, p[1], 0, p[2], FAR)
		for _, k in ipairs(FAR) do
			local h = camera.uprightPx(c, k.x, k.y, 0.15)
			if c.f < camera.tune.aim.fMax then
				expect.truthy(h >= 12, "kubb at x=" .. k.x .. " is " .. h .. " px")
			end
		end
	end
end)

test("the aimed-at ground point and the whole aim line project to screen center x", function()
	local c = camera.new()
	for _, p in ipairs(POSES) do
		camera.aim(c, p[1], 0, p[2], FAR)
		local sx = camera.project(c, c.lx, c.ly, 0)
		expect.near(sx, 200, 1e-6, "look point")
		local dx, dy = camera.aimDir(p[2])
		for _, d in ipairs { 4, 6, 9 } do
			sx = camera.project(c, p[1] + dx * d, dy * d, 0)
			expect.near(sx, 200, 1e-6, "aim line at " .. d .. " m")
		end
	end
end)

test("the camera moves with the player and pans with the swivel", function()
	local a, b = camera.new(), camera.new()
	camera.aim(a, 0, 0, 0, FAR)
	camera.aim(b, 1.5, 0, 0, FAR)
	expect.near(b.px - a.px, 1.5, 1e-9, "walks with the player")
	camera.aim(b, 0, 0, math.rad(-20), FAR)
	-- swivelled left: the camera swings right behind the player and looks left
	expect.truthy(b.px > a.px and b.fx < 0, "pans with the swivel")
	expect.near(b.pz, camera.tune.aim.height, 1e-9)
end)

test("king and centerline kubb sizes through the aim camera", function()
	local c = camera.new()
	camera.aim(c, 0, 0, 0, FAR)
	local king = camera.uprightPx(c, 0, 4, 0.30)
	expect.truthy(king >= 30 and king <= 40, "king " .. king .. " px")
	local field = camera.uprightPx(c, 0, 4, 0.15)
	expect.truthy(field >= 15 and field <= 20, "centerline kubb " .. field .. " px")
end)

test("far baseline kubb tops clear the minimap", function()
	local c = camera.new()
	camera.aim(c, 0, 0, 0, FAR)
	local m = camera.minimap
	for _, k in ipairs(FAR) do
		local sx, top = camera.project(c, k.x, k.y, 0.15)
		if sx >= m.ox - 4 then
			expect.truthy(top > m.oy + m.h + 3, "kubb x=" .. k.x .. " top row " .. top)
		end
	end
end)

test("impact camera shows a kubb at the landing point about 35 px tall", function()
	local c = camera.new()
	for _, l in ipairs { { 0, 8 }, { 1.2, 7.5 }, { -2, 6 } } do
		camera.impact(c, l[1], l[2], 0, 1)
		local h = camera.uprightPx(c, l[1], l[2], 0.15)
		expect.truthy(h >= 30 and h <= 40, "kubb " .. h .. " px")
		local d = math.sqrt((c.px - l[1]) ^ 2 + (c.py - l[2]) ^ 2)
		expect.truthy(d >= 2.5 and d <= 3, "distance " .. d)
		local sx = camera.project(c, l[1], l[2], camera.tune.impact.lookUp)
		expect.near(sx, 200, 1e-6, "landing point at center x")
	end
end)

test("follow camera blends aim to impact and keeps the baton in frame", function()
	local aim, imp, c = camera.new(), camera.new(), camera.new()
	for _, sw in ipairs { 0, math.rad(15), math.rad(-30) } do
		for _, loft in ipairs { 15, 35, 55 } do
			camera.aim(aim, 0.5, 0, sw, FAR)
			local fl = flight.new()
			flight.launch(fl, 0.5, 0, sw, loft, swing.tune.launchMax, 7, 0)
			camera.impact(imp, fl.lx, fl.ly, fl.dx, fl.dy)
			camera.follow(c, aim, imp, 0)
			expect.near(c.px, aim.px, 1e-9, "starts at the aim camera")
			camera.follow(c, aim, imp, 1)
			expect.near(c.py, imp.py, 1e-9, "ends at the impact camera")
			local seen = false
			while not fl.landed do
				flight.step(fl, 1 / 50)
				local s = flight.progress(fl)
				camera.follow(c, aim, imp, s, fl.x, fl.y, fl.z)
				local sx, sy = camera.project(c, fl.x, fl.y, fl.z)
				local on = sx and sx >= 0 and sx <= 400 and sy >= 0 and sy <= 240
				local what = string.format("t=%.2f loft %d swivel %.0f: %s, %s", fl.t, loft, math.deg(sw), tostring(sx), tostring(sy))
				if seen or s >= camera.tune.follow.catchBy then
					expect.truthy(on, "baton on screen at " .. what)
				end
				if on then
					seen = true
					expect.truthy(sy >= 0, "never above the frame at " .. what)
				end
			end
			expect.truthy(seen, "the baton was seen")
		end
	end
end)

test("near-plane clipping of a ground polygon behind the camera", function()
	local c = camera.new()
	camera.aim(c, 0, 0, 0, FAR)
	local out = {}
	-- a strip from far behind the camera to beyond the far baseline
	local n = camera.projectPoly(c, 4, { -1, 1, 1, -1 }, { -20, -20, 9, 9 }, nil, out)
	expect.truthy(n >= 4, "clipped polygon kept " .. n .. " points")
	for i = 1, 2 * n do expect.truthy(out[i] == out[i], "finite") end
	expect.eq(camera.projectPoly(c, 3, { 0, 1, 0 }, { -10, -10, -11 }, nil, out), 0, "all behind")
	expect.eq(camera.projectSegment(c, 0, -10, 0, 1, -12, 0), nil)
end)

test("minimap mapping: 9 px per meter, far baseline at the top", function()
	local m = camera.minimap
	expect.eq(m.w, 45); expect.eq(m.h, 72); expect.eq(m.scale, 9)
	local x, y = camera.toMinimap(-2.5, 8)
	expect.near(x, m.ox, 1e-9); expect.near(y, m.oy, 1e-9)
	x, y = camera.toMinimap(2.5, 0)
	expect.near(x, m.ox + 45, 1e-9); expect.near(y, m.oy + 72, 1e-9)
	x, y = camera.toMinimap(0, 4)
	expect.near(x, m.ox + 22.5, 1e-9); expect.near(y, m.oy + 36, 1e-9)
	expect.truthy(m.ox + m.w + 3 <= 400, "fits on screen")
end)

test("match framing: look nearer for near targets, the default for the far baseline", function()
	local t = camera.tune.aim
	expect.near(camera.lookDistFor(0, 0, FAR), t.lookDist, 1e-12, "base kubbs")
	expect.near(camera.lookDistFor(0, 0, {}), t.lookDist, 1e-12, "no targets")
	-- a field kubb 4.5 m out: look lookBeyond past it
	expect.near(camera.lookDistFor(0, 0, { { x = 0, y = 4.5 }, { x = 1, y = 7 } }), 4.5 + t.lookBeyond, 1e-12)
	-- from the advantage line, very close: never nearer than lookMin
	expect.near(camera.lookDistFor(0, 3, { { x = 0, y = 4 } }), t.lookMin, 1e-12)
	-- the default call is unchanged; a nearer look keeps the near target on screen
	local a, b = camera.new(), camera.new()
	camera.aim(a, 0, 0, 0, FAR)
	camera.aim(b, 0, 0, 0, FAR, nil, t.lookDist)
	expect.near(a.ly, b.ly, 1e-12)
	local near = { { x = 0.5, y = 3 } }
	camera.aim(b, 0, 0, 0, near, nil, camera.lookDistFor(0, 0, near))
	local _, sy = camera.project(b, 0.5, 3, 0)
	expect.truthy(sy and sy > 0 and sy < 240, "near kubb on screen")
end)
