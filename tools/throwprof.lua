-- Where a match throw's physics time goes, on the desktop: headless matches
-- as tools/physmatch.lua plays them (core/match, core/autothrow, the turn's
-- debris), every throw stepped to rest with world.prof on, each step put in
-- a class by what was awake and touching:
--   air     one body awake, no contact at all (a projectile in free flight)
--   ground  one body awake, touching only the ground (landing, rolling, sliding)
--   multi   two or more bodies awake (a collision)
--   ...and the slow tail: steps once nothing awake moves faster than
--   --slow m/s (and turns slower than 3 rad/s) until rest.
-- Desktop ratios mislead on the device (AGENTS.md "Speed"), but the counts of
-- steps by class do not.
--
--   lua5.4 tools/throwprof.lua [--n 3] [--seed 1] [--slow 0.25]

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end

import "core/match"
import "core/world"
import "core/autothrow"
local match, world, autothrow = tw.match, tw.world, tw.autothrow

local n, seed, slow = 3, 1, 0.25
local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--n" then n = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--seed" then seed = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--slow" then slow = tonumber(arg[i + 1]); i = i + 1
	else error("unknown argument " .. a) end
	i = i + 1
end

local phases = world.PHASES
local classes = { "air", "ground", "multi" }
local acc = {}
for _, c in ipairs(classes) do
	acc[c] = world.newProf(os.clock)
	acc[c].steps = 0
end
local P = world.newProf(os.clock)
local tailSteps, allSteps, throws = 0, 0, 0
local perThrow = {}

local function fastest(w)
	local v = 0
	for k = 1, w.n do
		local b = w.bodies[k]
		if b.awake then
			local s = math.sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
			local a = math.sqrt(b.wx * b.wx + b.wy * b.wy + b.wz * b.wz)
			if a > 3 then s = math.max(s, slow + 1) end
			if s > v then v = s end
		end
	end
	return v
end

local function simulate(s, a)
	local w = world.new { surface = "grass", pieces = match.worldPieces(s) }

	autothrow.launch(w, s, a)
	world.prof = P
	local steps, slowFrom = 0, nil
	local cnt = { air = 0, ground = 0, multi = 0 }
	while not world.isAtRest(w) do
		for _, k in ipairs(phases) do P[k] = 0 end
		world.step(w)
		steps = steps + 1
		local c
		if w.awakeCount >= 2 then c = "multi"
		elseif w.contacts == 0 then c = "air"
		else c = "ground" end
		local A = acc[c]
		A.steps = A.steps + 1
		cnt[c] = cnt[c] + 1
		for _, k in ipairs(phases) do A[k] = A[k] + P[k] end
		if fastest(w) < slow then slowFrom = slowFrom or steps else slowFrom = nil end
	end
	world.prof = nil
	local tail = slowFrom and (steps - slowFrom) or 0
	tailSteps, allSteps, throws = tailSteps + tail, allSteps + steps, throws + 1
	perThrow[#perThrow + 1] = string.format("%-5s %-6s bodies %2d steps %4d (air %3d ground %3d multi %3d) slow tail %3d",
		s.projectile, w.firstHit and "hit" or "miss", w.n, steps, cnt.air, cnt.ground, cnt.multi, tail)
	return world.result(w)
end

local base = { year = 2026, month = 11, day = 20, hour = 9, min = 0 }
for gi = 1, n do
	local m = match.new { start = base, first = (gi % 2 == 0) and "B" or "A" }
	local r = autothrow.rng(seed * 7919 + gi)
	while not match.over(m) and m.game.turn <= 40 do
		local s = match.setup(m)
		if not s then break end
		local a = autothrow.choose(s, r)
		match.resolve(m, simulate(s, a), not a.legal)
	end
end
for _, l in ipairs(perThrow) do print(l) end
print(string.format("%d throws, %d steps (%.0f per throw), slow tail (< %.2f m/s) %d steps (%.0f%%)",
	throws, allSteps, allSteps / throws, slow, tailSteps, tailSteps * 100 / allSteps))
local total = 0
for _, c in ipairs(classes) do
	for _, k in ipairs(phases) do total = total + acc[c][k] end
end
for _, c in ipairs(classes) do
	local A = acc[c]
	if A.steps > 0 then
		local sum, parts = 0, {}
		for _, k in ipairs(phases) do
			sum = sum + A[k]
			parts[#parts + 1] = string.format("%s %.4f", k, A[k] * 1000 / A.steps)
		end
		print(string.format("%-6s %5d steps (%2.0f%%) %.4f ms/step (%2.0f%% of the time): %s", c, A.steps,
			A.steps * 100 / allSteps, sum * 1000 / A.steps, sum * 100 / total, table.concat(parts, ", ")))
	end
end
