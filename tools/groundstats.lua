-- How the ground behaves, over many scripted throws (DESIGN 5, the surface
-- texture): batons thrown from the baseline at the five base kubbs, with
-- the spread of real throws (where the thrower stands, aim, loft, speed,
-- end-over-end spin and tilt), each run to rest. Reports per surface:
--   onEnd    s a throw's baton spent sliding on an end (long axis within 30
--            degrees of upright, touching the ground, moving faster than
--            0.2 m/s): what never happens on grass
--   creep    s it spent touching the ground and moving slower than 0.6 m/s
--            but not yet stopped: the slow slide to a stop
--   slide    m it travelled after it first touched the ground
--   rest     s from release to rest
--   hits     share of throws that toppled at least one kubb
--   kubbs    mean kubbs toppled a throw
-- Means, with the 90th percentile in brackets.
--
--   lua5.4 tools/groundstats.lua [--n 300] [--seed 1] [--surface grass]
--     [--flat]   (the surface without its texture, for comparison)
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end
import "core/tw"
import "core/world"
import "core/autothrow"
import "core/pitch"

local world, autothrow = tw.world, tw.autothrow
local sqrt, cos, sin, rad, floor = math.sqrt, math.cos, math.sin, math.rad, math.floor

local n, seed, surfName, flat = 300, 1, "grass", false
local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--n" then n = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--seed" then seed = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--surface" then surfName = arg[i + 1]; i = i + 1
	elseif a == "--flat" then flat = true end
	i = i + 1
end

local surface = world.surfaces[surfName]
if flat then
	local copy = {}
	for k, v in pairs(surface) do copy[k] = v end
	copy.texture = nil
	surface = copy
end

local R = autothrow.rng(seed)
local rng = R.next
local function gauss() return R.normal(1) end

local stats = { onEnd = {}, creep = {}, slide = {}, rest = {}, kubbs = {} }
local hits = 0
local cosEnd = cos(rad(30))
for k = 1, n do
	local pieces = {}
	for j = 1, 5 do pieces[j] = { id = "b" .. j, kind = "kubb", x = -3 + j, y = 8, yaw = 0 } end
	pieces[6] = { id = "king", kind = "king", x = 0, y = 4, yaw = 0 }
	local w = world.new { surface = surface, pieces = pieces }
	-- a thrower somewhere on the baseline aiming at one base kubb
	local tx = -3 + (1 + floor(rng() * 5))
	local x = -2 + rng() * 4
	local loft = 25 + rng() * 12
	local d = sqrt((tx - x) ^ 2 + 8 * 8) - 0.15
	local speed = autothrow.speedFor(d, loft) * (1 + 0.06 * gauss())
	local swivel = math.atan(tx - x, 8) + rad(1.5) * gauss()
	local tumble = 5 + rng() * 5
	local tilt = 8 * gauss()
	world.launchBaton(w, x, 0, swivel, loft, speed, tumble, tilt)
	local b = w.projectile
	local landed, lx, ly = false, 0, 0
	local onEnd, creep = 0, 0
	local dt = world.tune.dt
	while not world.isAtRest(w) do
		world.step(w)
		local ground = b.groundImpulse and b.groundImpulse > 0
		if ground and not landed then landed, lx, ly = true, b.x, b.y end
		if ground and b.awake then
			local v = sqrt(b.vx * b.vx + b.vy * b.vy)
			local up = b.r33 >= 0 and b.r33 or -b.r33
			if up > cosEnd and v > 0.2 then onEnd = onEnd + dt end
			if v < 0.6 and v > 0.02 then creep = creep + dt end
		end
	end
	local down = 0
	for j = 1, w.n do
		local o = w.bodies[j]
		if o ~= b and o.kind == "kubb" and o.toppled then down = down + 1 end
	end
	if down > 0 then hits = hits + 1 end
	stats.onEnd[k], stats.creep[k], stats.rest[k], stats.kubbs[k] = onEnd, creep, w.time, down
	stats.slide[k] = landed and sqrt((b.x - lx) ^ 2 + (b.y - ly) ^ 2) or 0
end

local function summary(t)
	local s = 0
	for _, v in ipairs(t) do s = s + v end
	local c = {}
	for j, v in ipairs(t) do c[j] = v end
	table.sort(c)
	return s / #t, c[math.max(1, floor(#c * 0.9))]
end
local function nonzero(t)
	local z = 0
	for _, v in ipairs(t) do if v > 0 then z = z + 1 end end
	return z
end
print(string.format("%s%s, %d throws (seed %d):", surfName, flat and " (flat)" or "", n, seed))
for _, key in ipairs { "onEnd", "creep", "slide", "rest", "kubbs" } do
	local m, p90 = summary(stats[key])
	print(string.format("  %-6s %6.3f (90%%: %6.3f)%s", key, m, p90,
		key == "onEnd" and string.format("  throws with any: %d", nonzero(stats.onEnd)) or ""))
end
print(string.format("  hits   %5.1f%% of throws toppled a kubb", 100 * hits / n))
