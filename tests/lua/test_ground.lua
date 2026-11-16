-- core/world: the ground texture (world.surfaces.*.texture; DESIGN 5 and
-- AGENTS.md "Physics", "The ground's texture").
import "core/world"
import "core/autothrow"
local world, autothrow = tw.world, tw.autothrow
local sqrt, cos, rad = math.sqrt, math.cos, math.rad

local function pieces()
	local p = {}
	for j = 1, 5 do p[j] = { id = "b" .. j, kind = "kubb", x = -3 + j, y = 8, yaw = 0 } end
	p[6] = { id = "king", kind = "king", x = 0, y = 4, yaw = 0 }
	return p
end

-- One throw at a base kubb run to rest; returns the baton, the world and the
-- seconds it slid on an end, and how far it went after first touching down.
local function throw(i, opts)
	local surface = opts and opts.surface or "grass"
	local R = autothrow.rng(1000 + i)
	local tx = -3 + (1 + math.floor(R.next() * 5))
	local x = -2 + R.next() * 4
	local loft = 25 + R.next() * 12
	local d = sqrt((tx - x) ^ 2 + 64) - 0.15
	local speed = autothrow.speedFor(d, loft) * (1 + R.normal(0.06))
	local w = world.new { surface = surface, pieces = pieces(), texture = opts and opts.texture,
		groundSeed = opts and opts.groundSeed }
	world.launchBaton(w, x, 0, math.atan(tx - x, 8) + rad(R.normal(1.5)), loft, speed,
		5 + R.next() * 5, R.normal(8))
	local b = w.projectile
	local onEnd, landed, lx, ly = 0, false, 0, 0
	local cosEnd = cos(rad(30))
	while not world.isAtRest(w) do
		world.step(w)
		if b.groundImpulse > 0 then
			if not landed then landed, lx, ly = true, b.x, b.y end
			local up = b.r33 >= 0 and b.r33 or -b.r33
			if b.awake and up > cosEnd and b.vx * b.vx + b.vy * b.vy > 0.04 then onEnd = onEnd + world.tune.dt end
		end
	end
	return b, w, onEnd, landed and sqrt((b.x - lx) ^ 2 + (b.y - ly) ^ 2) or 0
end

test("ground: the same throw meets the same ground; another ground sends it elsewhere", function()
	local a = throw(1)
	local b = throw(1)
	expect.eq(a.x, b.x); expect.eq(a.y, b.y); expect.eq(a.qw, b.qw)
	local moved = 0
	for seed = 1, 6 do
		local c = throw(1, { groundSeed = seed })
		if math.abs(c.x - a.x) + math.abs(c.y - a.y) > 0.01 then moved = moved + 1 end
	end
	expect.truthy(moved >= 4, "other grounds moved the rest " .. moved .. " of 6 times")
end)

test("ground: texture = false is the plain surface, and leaves the shared one alone", function()
	local _, w = throw(2, { texture = false })
	expect.eq(w.surface.texture, nil)
	expect.truthy(world.surfaces.grass.texture ~= nil, "grass keeps its texture")
	expect.eq(w.surface.mu, world.surfaces.grass.mu)
end)

test("ground: on textured grass a baton hardly ever slides on an end and stops sooner", function()
	-- over 80 throws, against the same throws on flat grass (tools/groundstats
	-- gives the full picture). On an end: under 0.015 s a throw on average
	-- (0.011 measured; 0.007 with the trip, taken out 2026-11-16: what is left
	-- is mostly a baton vaulting up over an end at the end of a tumble and
	-- falling back, its centre moving at 0.2 to 0.4 m/s, which the trip's
	-- added spin cut short). Before 2026-11-15 the flat ground was the comparison
	-- (2.3 s over these 80 against 0.44 textured), but a baton that keeps the
	-- spin it lands with (the turn and roll held apart, AGENTS.md "Physics")
	-- hardly slides on an end on flat grass either now (0.2 s)
	local endT, slideT, slideF = 0, 0, 0
	for i = 1, 80 do
		local _, _, e1, s1 = throw(i)
		local _, _, _, s2 = throw(i, { texture = false })
		endT, slideT, slideF = endT + e1, slideT + s1, slideF + s2
	end
	expect.truthy(endT / 80 < 0.015, string.format("on an end %.2f s over 80 throws", endT))
	expect.truthy(slideT < 0.85 * slideF, string.format("slide %.1f m against %.1f flat", slideT, slideF))
end)

test("ground: sand stops a baton far sooner than grass; snow lets it run farther, then stops it", function()
	local g, sa, sn = 0, 0, 0
	for i = 1, 60 do
		local _, _, _, s1 = throw(i)
		local _, _, _, s2 = throw(i, { surface = "sand" })
		local b, w, _, s3 = throw(i, { surface = "snow" })
		g, sa, sn = g + s1, sa + s2, sn + s3
		expect.truthy(w.time < world.tune.maxTime, "snow throw " .. i .. " came to rest")
		expect.truthy(not b.awake, "snow baton " .. i .. " asleep")
	end
	-- 400 throws (tools/groundstats): grass 1.39 m, sand 0.46, snow 1.85
	expect.truthy(sa < 0.5 * g, string.format("sand %.1f m against grass %.1f", sa, g))
	expect.truthy(sn > 1.1 * g, string.format("snow %.1f m against grass %.1f", sn, g))
end)

test("ground: in snow the drag grows with the distance ploughed, and resets off the ground", function()
	local w = world.new { surface = "snow", stakes = false,
		pieces = { { id = "b", kind = "baton", x = 0, y = 2, qw = math.cos(math.pi / 4), qx = math.sin(math.pi / 4), qy = 0, qz = 0, z = 0.025 } },
		groundSeed = 1 }
	local b = w.byId.b
	tw.world.wake(b)
	b.vx = 3
	for _ = 1, 60 do world.step(w) end
	expect.truthy(b.plough > 0.2, "ploughed " .. b.plough .. " m")
	b.z, b.vz = 1, 0          -- lifted clear: the next step it is off the ground
	world.step(w)
	expect.eq(b.plough, 0)
end)

test("ground: every surface a game can be played on has its texture", function()
	for _, name in ipairs(world.SURFACES) do
		local s = world.surfaces[name]
		expect.truthy(s and s.texture, name .. " has a texture")
	end
end)

-- A standing kubb shoved at its centre (no spin) to speed v across the ground,
-- run to rest: did it topple, and how far did it go.
local function shove(surface, v, seed, texture)
	local w = world.new { surface = surface, stakes = false, texture = texture,
		pieces = { { id = "k", kind = "kubb", x = 0.3, y = 2, yaw = 0 } }, groundSeed = seed }
	local k = w.byId.k
	for _ = 1, 4 do world.step(w) end
	world.wake(k)
	k.vy = v
	local y0 = k.y
	while not world.isAtRest(w) and w.time < 6 do world.step(w) end
	return k.toppled, k.y - y0
end

test("ground: a standing kubb sliding on snow ploughs at its foot and tips; a nudge leaves it standing", function()
	-- flat snow is too slick to tip a sliding kubb (mu 0.25 against the 0.47
	-- its footprint needs): it glides standing
	local flatDown, flatSlide = shove("snow", 2, 1, false)
	expect.truthy(not flatDown, "flat snow: glides standing")
	expect.truthy(flatSlide > 0.5, "flat snow: slid " .. flatSlide .. " m")
	local down, nudged = 0, 0
	for seed = 1, 10 do
		if shove("snow", 2, seed) then down = down + 1 end
		if shove("snow", 0.5, seed) then nudged = nudged + 1 end
		if shove("grass", 0.5, seed) then nudged = nudged + 1 end
	end
	expect.truthy(down >= 9, "textured snow: " .. down .. " of 10 tipped at 2 m/s")
	expect.eq(nudged, 0)
end)
