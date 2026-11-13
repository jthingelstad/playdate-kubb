-- The bit-identity check for changes to core/world and core/collide
-- (AGENTS.md "Speed"): runs fixed scenarios to rest and prints every body's
-- state with full precision, every `--every` steps and at the end. Run it
-- before and after a change and diff the two outputs: they must be identical,
-- or the change must say why not.
--
--   lua5.4 tools/physdump.lua [--every 20] [--games 2] > before.txt
--
-- Scenarios: core/bench's throw (with and without its debris), the match
-- case's throws (core/bench.matchThrows), and the throws of --games headless
-- matches as tools/physmatch.lua plays them.

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end

import "core/bench"
import "core/drill"
import "core/match"
import "core/autothrow"
local bench, world, drill, match, autothrow = tw.bench, tw.world, tw.drill, tw.match, tw.autothrow

local every, games = 20, 2
local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--every" then every = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--games" then games = tonumber(arg[i + 1]); i = i + 1
	else error("unknown argument " .. a) end
	i = i + 1
end

local fmt = string.format
local function dump(name, w)
	local parts = { fmt("%s t=%.17g steps=%d awake=%d contacts=%d", name, w.time, w.steps, w.awakeCount, w.contacts) }
	for k = 1, w.n do
		local b = w.bodies[k]
		parts[#parts + 1] = fmt("  %s %s %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %s %s",
			b.id, tostring(b.awake), b.x, b.y, b.z, b.qw, b.qx, b.qy, b.qz, b.vx, b.vy, b.vz, b.wx, b.wy, b.wz,
			tostring(b.toppled), tostring(b.touched))
	end
	print(table.concat(parts, "\n"))
end

local function run(name, w)
	local s = 0
	while not world.isAtRest(w) do
		world.step(w)
		s = s + 1
		if s % every == 0 then dump(name, w) end
	end
	dump(name .. " rest", w)
	local r = world.result(w)
	print(fmt("%s result: toppled %s touched %s hit %s", name, table.concat(r.toppled, ","),
		table.concat(r.touched, ","), tostring(r.firstHit and r.firstHit.with)))
	return r
end

run("bench", bench.world(false))
run("bench debris", bench.world(true))

for _, t in ipairs(bench.matchThrows) do
	local s = bench.matchSetup(t.projectile)
	local w = world.new { surface = "grass", pieces = match.worldPieces(s) }
	local a = bench.matchThrow(t)
	if a.drill then
		local sol = drill.solve(a.drill.markerX, a.drill.markerY, 0, {})
		local L = drill.launch(sol, { power = sol.band, smoothness = 1, tilt = 0 }, 0, {})
		world.launchDrill(w, s.kubb, sol.x, 0, L.swivel, L.loft, L.speed, L.noseDown, L.rollLand, L.spin,
			L.wobble, L.digGain)
	else
		world.launchBaton(w, a.x, a.y, a.swivel, a.loftDeg, a.speed, a.tumbleRate, a.tilt, s.batonId)
	end
	run("match " .. t.name, w)
end

local base = { year = 2026, month = 11, day = 20, hour = 9, min = 0 }
for gi = 1, games do
	local m = match.new { start = base, first = (gi % 2 == 0) and "B" or "A" }
	local r = autothrow.rng(7919 + gi)
	local n = 0
	while not match.over(m) and m.game.turn <= 40 do
		local s = match.setup(m)
		if not s then break end
		local a = autothrow.choose(s, r)
		local w = world.new { surface = "grass", pieces = match.worldPieces(s) }
		if s.projectile == "kubb" then
			world.launchKubb(w, s.kubb, a.x, a.y, a.swivel, a.loftDeg, a.speed, a.tumbleRate)
		else
			world.launchBaton(w, a.x, a.y, a.swivel, a.loftDeg, a.speed, a.tumbleRate, a.tilt, s.batonId)
		end
		n = n + 1
		match.resolve(m, run(fmt("game %d throw %d", gi, n), w), not a.legal)
	end
	print(fmt("game %d: %s", gi, m.text or ""))
end
