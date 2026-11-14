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
	local R = autothrow.rng(1000 + i)
	local tx = -3 + (1 + math.floor(R.next() * 5))
	local x = -2 + R.next() * 4
	local loft = 25 + R.next() * 12
	local d = sqrt((tx - x) ^ 2 + 64) - 0.15
	local speed = autothrow.speedFor(d, loft) * (1 + R.normal(0.06))
	local w = world.new { surface = "grass", pieces = pieces(), texture = opts and opts.texture,
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
	-- gives the full picture: 400 throws, 0.050 -> 0.008 s on an end, 2.1 ->
	-- 1.4 m of slide)
	local endT, endF, slideT, slideF = 0, 0, 0, 0
	for i = 1, 80 do
		local _, _, e1, s1 = throw(i)
		local _, _, e2, s2 = throw(i, { texture = false })
		endT, endF, slideT, slideF = endT + e1, endF + e2, slideT + s1, slideF + s2
	end
	expect.truthy(endT < 0.4 * endF, string.format("on an end %.2f s against %.2f flat", endT, endF))
	expect.truthy(slideT < 0.85 * slideF, string.format("slide %.1f m against %.1f flat", slideT, slideF))
end)
