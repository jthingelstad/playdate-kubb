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
	-- (with the crane straight behind the thrower: side 0)
	local side = camera.tune.aim.side
	camera.tune.aim.side = 0
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
	camera.tune.aim.side = side
end)

test("over the shoulder: the aimed-at point stays centered, the aim line comes in from the left", function()
	local c = camera.new()
	local side = camera.tune.aim.side
	camera.tune.aim.side = 1.0
	for _, p in ipairs(POSES) do
		camera.aim(c, p[1], 0, p[2], FAR)
		expect.near(camera.project(c, c.lx, c.ly, 0), 200, 1e-6, "look point")
		local dx, dy = camera.aimDir(p[2])
		local near = camera.project(c, p[1] + dx * 3, dy * 3, 0)
		expect.truthy(near < 200, "the near aim line is left of center: " .. near)
		-- the crane is to the thrower's right: its right vector points the same way
		expect.truthy((c.px - p[1]) * dy - c.py * dx > 0.99, "a metre to the right")
	end
	camera.tune.aim.side = side
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

-- in the HUD's clear area: under the rail, and above the plaques unless
-- in the middle column
local function inClear(x, y)
	local a = camera.clear
	if y <= a.rail or y > a.bottom or x < 0 or x > 400 then return false end
	return y <= a.top or (x >= a.x0 and x <= a.x1)
end

test("far baseline kubbs stand in the HUD's clear area from every aim pose", function()
	local c = camera.new()
	for _, p in ipairs(POSES) do
		camera.aim(c, p[1], 0, p[2], FAR)
		for _, k in ipairs(FAR) do
			local sx, top = camera.project(c, k.x, k.y, 0.15)
			local bx, foot = camera.project(c, k.x, k.y, 0)
			local what = string.format("player %.1f swivel %.0f kubb x=%d", p[1], math.deg(p[2]), k.x)
			if sx >= 0 and sx <= 400 then
				expect.truthy(inClear(sx, top) and inClear(bx, foot), what .. ": top " .. top .. " foot " .. foot)
			end
		end
	end
end)

test("the minimap's frame sits under the clear area's bottom-left corner", function()
	local m, a = camera.minimap, camera.clear
	expect.truthy(m.ox + m.w + 2 < a.x0, "left of the middle column")
	expect.truthy(m.oy - 2 > a.top, "below the full-width band")
	expect.truthy(m.oy + m.h + 2 <= 240, "on screen")
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
			flight.launch(fl, 0.5, 0, sw, loft, 9.2, 7, 0)
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

-- ---------------------------------------------------------------------------
-- First person and the plan view (Jamie, 2026-11-15: first person while
-- aiming, over the shoulder and zoomed out while B is held)

import "core/throwplan"
local plan = tw.plan

local CIRCLES = {}
for _, x in ipairs { -2.5, -1, 0, 1.5, 2.5 } do
	for _, y in ipairs { 3.5, 4.2, 5, 6, 7, 8, 8.6 } do CIRCLES[#CIRCLES + 1] = { x, y } end
end
local STANCES = { false, -2.5, 2.5 }   -- false: straight behind the circle

local function stanceFor(cx, px)
	if px then return px, 0 end
	return math.max(-2.5, math.min(2.5, cx)), 0
end

test("first person is straight behind the thrower, looking circleBeyond past the circle", function()
	expect.eq(camera.tune.aim.side, 0, "side")
	local c = camera.new()
	local t = camera.tune.aim
	expect.near(camera.lookDistAt(0, 0, 0, 5), 5 + t.circleBeyond, 1e-12)
	expect.near(camera.lookDistAt(0, 0, 0, 8), t.lookDist, 1e-12, "the far baseline: the default framing")
	expect.near(camera.lookDistAt(0, 3, 0, 4), t.lookMin, 1e-12, "close up: never nearer than lookMin")
	camera.aim(c, 1, 0, 0.1, FAR, 0, camera.lookDistAt(1, 0, 1.5, 6))
	local dx, dy = camera.aimDir(0.1)
	expect.near(c.px, 1 - dx * t.back, 1e-9, "behind along the aim")
	expect.near(c.py, -dy * t.back, 1e-9)
	expect.near(camera.project(c, 1 + dx * 4, dy * 4, 0), 200, 1e-6, "the aim line at centre x")
end)

test("first person: the circle wholly on screen and the far base kubbs at least 12 px", function()
	local c = camera.new()
	local R = 0.25
	for _, ci in ipairs(CIRCLES) do
		for _, sp in ipairs(STANCES) do
			local px, py = stanceFor(ci[1], sp)
			local sw = math.atan(ci[1] - px, ci[2] - py)
			camera.aim(c, px, py, sw, FAR, 0, camera.lookDistAt(px, py, ci[1], ci[2]))
			local what = string.format("circle %.1f %.1f stance %.1f", ci[1], ci[2], px)
			for k = 0, 11 do
				local a = k * math.pi / 6
				local sx, sy = camera.project(c, ci[1] + R * math.cos(a), ci[2] + R * math.sin(a), 0)
				expect.truthy(sx and sx >= 0 and sx <= 400 and sy >= 14 and sy <= 240,
					what .. ": ring at " .. tostring(sx) .. ", " .. tostring(sy))
			end
			if c.f < camera.tune.aim.fMax then
				for _, k in ipairs(FAR) do
					local h = camera.uprightPx(c, k.x, k.y, 0.15)
					local sx = camera.project(c, k.x, k.y, 0)
					if sx >= 0 and sx <= 400 then expect.truthy(h >= 12, what .. ": kubb " .. k.x .. " " .. h .. " px") end
				end
			end
			expect.truthy(camera.uprightPx(c, 0, 8, 0.15) >= 12 or c.f >= camera.tune.aim.fMax, what .. ": (0, 8)")
		end
	end
end)

-- The planned arc (as throw.lua's drawArc: points arcSkip..arcPoints of the
-- plan's clean throw) and the circle's four sides, into xs, ys, zs.
local AX, AY, AZ = {}, {}, {}
local function planArc(px, py, tx, ty, rel)
	local sol = plan.solve({ projectile = "baton", px = px, py = py, tx = tx, ty = ty, release = rel,
		level = "club" }, {})
	local e = math.rad(sol.loft)
	local _, _, T = flight.predict(px, py, sol.swivel, sol.loft, sol.speed)
	local vx, vy = sol.speed * math.sin(sol.swivel) * math.cos(e), sol.speed * math.cos(sol.swivel) * math.cos(e)
	local vz, h, g = sol.speed * math.sin(e), flight.tune.handHeight, flight.tune.g
	local n = 0
	for i = 2, 24 do
		local tt = T * i / 24
		n = n + 1
		AX[n], AY[n], AZ[n] = px + vx * tt, py + vy * tt, h + vz * tt - 0.5 * g * tt * tt
	end
	for k = 0, 3 do
		n = n + 1
		AX[n], AY[n], AZ[n] = tx + 0.25 * math.cos(k * math.pi / 2), ty + 0.25 * math.sin(k * math.pi / 2), 0
	end
	return n, sol
end

test("the plan view: over the right shoulder, zoomed out, the target half, the arc and the circle in its box", function()
	local t = camera.tune.shoulder
	local c, fp = camera.new(), camera.new()
	local pt = plan.tune
	local ACROSS = 4   -- (throw.tune.arcFitFrom - arcSkip: the arc's first rise only across)
	for _, ci in ipairs { { 0, 8 }, { -2.5, 8 }, { 2.5, 8 }, { 0, 4.2 }, { -2.5, 4.2 }, { 2.5, 6 }, { 1, 5 } } do
		for _, sp in ipairs(STANCES) do
			local px, py = stanceFor(ci[1], sp)
			for rel = pt.releaseMinDeg, pt.releaseMaxDeg, pt.arcStepDeg do
				local n, sol = planArc(px, py, ci[1], ci[2], rel)
				local what = string.format("circle %.1f %.1f stance %.1f release %d", ci[1], ci[2], px, rel)
				camera.shoulder(c, px, py, sol.swivel, 0, n, AX, AY, AZ, ACROSS)
				camera.aim(fp, px, py, sol.swivel, FAR, 0, camera.lookDistAt(px, py, ci[1], ci[2]))
				expect.truthy(c.f < fp.f and c.f >= t.fMin and c.f <= t.fMax, what .. ": lens " .. c.f)
				-- to the right of the thrower, behind and above
				local dx, dy = camera.aimDir(sol.swivel)
				expect.truthy((c.px - px) * dy - (c.py - py) * dx > t.side - 1e-6, what .. ": to the right")
				expect.near(c.pz, t.height, 1e-9)
				local function inBox(x, y, z, sidesOnly)
					local sx, sy = camera.project(c, x, y, z)
					if not sx then return false end
					if sx < t.left - 0.5 or sx > t.right + 0.5 then return false end
					return sidesOnly or (sy >= t.top - 0.5 and sy <= t.bottom + 0.5)
				end
				for _, p in ipairs { { -2.5, 8 }, { 2.5, 8 }, { -1, 4 }, { 1, 4 }, { 0, 4 } } do
					expect.truthy(inBox(p[1], p[2], 0), what .. string.format(": (%.1f, %.0f)", p[1], p[2]))
				end
				for i = 1, n do
					expect.truthy(inBox(AX[i], AY[i], AZ[i], i <= ACROSS), what .. ": fit point " .. i)
				end
			end
		end
	end
end)

test("camera.blend runs first person to the plan view; the follow starts from either", function()
	local a, b, c = camera.new(), camera.new(), camera.new()
	camera.aim(a, 0, 0, 0, FAR, 0, camera.lookDistAt(0, 0, 0, 8))
	local n = planArc(0, 0, 0, 8, 90)
	camera.shoulder(b, 0, 0, 0, 0, n, AX, AY, AZ, 4)
	camera.blend(c, a, b, 0)
	for _, k in ipairs { "px", "py", "pz", "lx", "ly", "f", "cx", "cy" } do expect.near(c[k], a[k], 1e-9, k .. " at 0") end
	camera.blend(c, a, b, 1)
	for _, k in ipairs { "px", "py", "pz", "lx", "ly", "f", "cx", "cy" } do expect.near(c[k], b[k], 1e-6, k .. " at 1") end
	camera.blend(c, a, b, 0.5)
	expect.near(c.f, math.sqrt(a.f * b.f), 1e-6, "the lens half way in log space")
	expect.near(c.px, (a.px + b.px) / 2, 1e-9, "half way across")
	-- the follow starts from the aim camera's principal point, wherever it is
	local imp, f = camera.new(), camera.new()
	camera.impact(imp, 0, 8, 0, 1)
	camera.follow(f, b, imp, 0)
	expect.near(f.cx, b.cx, 1e-9, "follow from the plan view: its cx")
	camera.follow(f, b, imp, 1)
	expect.near(f.cx, imp.cx, 1e-9, "to the impact camera's")
end)
