-- Headless matches with real physics: core/match driven by core/autothrow,
-- every throw simulated by core/world to rest, the same path as the match
-- scene without the screen. Writes each game file; the notation gate checks
-- them (`make physgames`).
--
--   lua5.4 tools/physmatch.lua [--n 3] [--seed 1] [--out build/physgames] [--maxturns 40] [-v]

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
import "core/notation"
local match, world, autothrow, notation = tw.match, tw.world, tw.autothrow, tw.notation

local n, seed, out, maxTurns, verbose = 3, 1, "build/physgames", 40, false
local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--n" then n = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--seed" then seed = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--out" then out = arg[i + 1]; i = i + 1
	elseif a == "--maxturns" then maxTurns = tonumber(arg[i + 1]); i = i + 1
	elseif a == "-v" then verbose = true
	else error("unknown argument " .. a) end
	i = i + 1
end

-- One throw of setup s with throw a, simulated to rest.
local function simulate(s, a, surface)
	local w = world.new { surface = surface, pieces = match.worldPieces(s) }
	if s.projectile == "kubb" then
		world.launchKubb(w, s.kubb, a.x, a.y, a.swivel, a.loftDeg, a.speed, a.tumbleRate)
	else
		world.launchBaton(w, a.x, a.y, a.swivel, a.loftDeg, a.speed, a.tumbleRate, a.tilt, s.batonId)
	end
	world.run(w)
	return world.result(w)
end

os.execute('mkdir -p "' .. out .. '"')
local base = { year = 2026, month = 11, day = 20, hour = 9, min = 0 }
local t0 = os.clock()
local throws = 0
for gi = 1, n do
	local start = notation.addMinutes(base, (gi - 1) * 41)
	local m = match.new { start = start, first = (gi % 2 == 0) and "B" or "A" }
	local r = autothrow.rng(seed * 7919 + gi)
	while not match.over(m) do
		if m.game.turn > maxTurns then
			match.resign(m)
			break
		end
		local s = match.setup(m)
		if not s then break end
		local a = autothrow.choose(s, r)
		local res = simulate(s, a, "grass")
		match.resolve(m, res, not a.legal)
		throws = throws + 1
		if verbose then print(string.format("turn %d %s -> %s", m.game.turn, s.label, m.text)) end
	end
	local finish = notation.addMinutes(start, 5 + m.game.turn * 2)
	local text, name = match.file(m, finish, "0.0.1")
	local f = assert(io.open(out .. "/" .. name, "w"))
	f:write(text)
	f:close()
	print(string.format("physmatch %d: %s in %d turns (%s)", gi, match.teamName(m.game.winner), m.game.turn, m.game.how))
end
print(string.format("physmatch: %d games, %d throws, %.1f s", n, throws, os.clock() - t0))
