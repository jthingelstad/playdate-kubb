-- Headless game generator: plays N seeded random games through the rules
-- engine (tools/thrower.lua, no physics) and writes each as a Planet Kubb
-- Notation file.
--
--   lua5.4 tools/games.lua [--n 500] [--seed 1] [--out build/games]
--
-- Same seed, same files. `make games` runs this and then the notation gate.

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end

local thrower = dofile(here .. "/thrower.lua")
import "core/notation"
local notation = tw.notation

local n, seed, out = 500, 1, "build/games"
local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--n" then n = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--seed" then seed = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--out" then out = arg[i + 1]; i = i + 1
	else error("unknown argument " .. a) end
	i = i + 1
end

os.execute('mkdir -p "' .. out .. '"')
local base = { year = 2026, month = 11, day = 20, hour = 9, min = 0 }
local totals = {}
local wins = { A = 0, B = 0 }
for g_i = 1, n do
	local g, t = thrower.playGame(seed * 100003 + g_i)
	local start = notation.addMinutes(base, (g_i - 1) * 37)
	local finish = notation.addMinutes(start, 5 + g.turn * 2)
	local text = notation.render(g, { start = start, finish = finish, version = "0.0.1",
		mode = "Pass and Play" })
	local name = notation.filename(start, g.teams.A.name, g.teams.B.name)
	local f = assert(io.open(out .. "/" .. name, "w"))
	f:write(text)
	f:close()
	wins[g.winner] = wins[g.winner] + 1
	for k, v in pairs(t.stats) do totals[k] = (totals[k] or 0) + v end
	totals["opening_" .. g.opening] = (totals["opening_" .. g.opening] or 0) + 1
	totals["surface_" .. g.surface] = (totals["surface_" .. g.surface] or 0) + 1
	totals["first_" .. g.first] = (totals["first_" .. g.first] or 0) + 1
end
local keys = {}
for k in pairs(totals) do keys[#keys + 1] = k end
table.sort(keys)
local parts = {}
for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. totals[k] end
print(string.format("games: wrote %d games to %s (Team A won %d, Team B %d)", n, out, wins.A, wins.B))
print("games: events " .. table.concat(parts, " "))
