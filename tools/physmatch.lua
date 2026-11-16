-- Headless matches with real physics: core/match driven by core/autothrow,
-- every throw simulated by core/world to rest, the same path as the match
-- scene without the screen. Writes each game file; the notation gate checks
-- them (`make physgames`). Team sizes go round one to six (game i: Team A
-- has (i - 1) % 6 + 1 players, Team B (i + 1) % 6 + 1), and every sheet is
-- checked against the throwing order's rules (core/order: II.A.4, II.B.5).
--
--   lua5.4 tools/physmatch.lua [--n 3] [--seed 1] [--out build/physgames] [--maxturns 40]
--     [--surface Grass|Sand|Snow] [--scatter 1] [-v]
--
-- --scatter multiplies every mistake of the computer's swing (core/autothrow's
-- scale): 1 is the game's Playdate, lower a steadier thrower.

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
import "core/order"
local match, world, autothrow, notation, order = tw.match, tw.world, tw.autothrow, tw.notation, tw.order

local NAMES = { A = { "Alex", "Kim", "Max", "Nell", "Otto", "Pia" }, B = { "Sam", "Lee", "Dana", "Rae", "Sol", "Tam" } }

-- Team `side` of `size` players.
local function team(side, size)
	local ps = {}
	for j = 1, size do ps[j] = { name = NAMES[side][j] } end
	return { name = "Team " .. side, players = ps }
end

local n, seed, out, maxTurns, verbose, surface, scatter = 3, 1, "build/physgames", 40, false, "Grass", nil
local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--n" then n = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--seed" then seed = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--out" then out = arg[i + 1]; i = i + 1
	elseif a == "--maxturns" then maxTurns = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--surface" then surface = arg[i + 1]; i = i + 1   -- Grass, Sand or Snow
	elseif a == "--scatter" then scatter = tonumber(arg[i + 1]); i = i + 1
	elseif a == "-v" then verbose = true
	else error("unknown argument " .. a) end
	i = i + 1
end

-- One throw of setup s with throw a, simulated to rest.
local function simulate(s, a, surface)
	local w = world.new { surface = surface, pieces = match.worldPieces(s) }
	autothrow.launch(w, s, a)
	world.run(w)
	return world.result(w)
end

os.execute('mkdir -p "' .. out .. '"')
local base = { year = 2026, month = 11, day = 20, hour = 9, min = 0 }
local t0 = os.clock()
local throws = 0
-- what the computer's throws did (printed at the end): batons by target
-- (base kubbs from the baseline, field kubbs, the king), how many toppled
-- one of their targets, helicopters; kubbs drilled, rethrown, punishment kubbs
local st = { base = { 0, 0 }, field = { 0, 0 }, king = { 0, 0 }, heli = 0, tosses = 0, rethrow = 0, punish = 0,
	turns = 0, how = {} }
local function targetKind(s)
	if s.kingShot then return "king" end
	for _, p in ipairs(s.pieces) do
		if p.id == s.targets[1] then return p.role == "field" and "field" or (p.role == "king" and "king" or "base") end
	end
	return "base"
end
for gi = 1, n do
	local start = notation.addMinutes(base, (gi - 1) * 41)
	local m = match.new { start = start, first = (gi % 2 == 0) and "B" or "A", surface = surface,
		teams = { A = team("A", (gi - 1) % 6 + 1), B = team("B", (gi + 1) % 6 + 1) } }
	local r = autothrow.rng(seed * 7919 + gi)
	while not match.over(m) do
		if m.game.turn > maxTurns then
			match.resign(m)
			break
		end
		local s = match.setup(m)
		if not s then break end
		local a = autothrow.choose(s, r, scatter)
		local res = simulate(s, a, s.surface or "grass")
		match.resolve(m, res, not a.legal)
		throws = throws + 1
		if s.kind == "toss" then
			st.tosses = st.tosses + 1
			local j = m.game.judgment
			if j then st.rethrow, st.punish = st.rethrow + j.rethrow, st.punish + j.punish end
		else
			local k = st[targetKind(s)]
			k[1] = k[1] + 1
			if not a.legal then
				st.heli = st.heli + 1
			else
				local want = {}
				for _, id in ipairs(s.targets) do want[id] = true end
				for _, id in ipairs(res.toppled) do
					if want[id] then k[2] = k[2] + 1; break end
				end
			end
		end
		if verbose then print(string.format("turn %d %s -> %s", m.game.turn, s.label, m.text)) end
	end
	local bad = order.checkSheet(m.game)
	if #bad > 0 then error("physmatch " .. gi .. ": " .. bad[1]) end
	local finish = notation.addMinutes(start, 5 + m.game.turn * 2)
	local text, name = match.file(m, finish, "0.0.1")
	local f = assert(io.open(out .. "/" .. name, "w"))
	f:write(text)
	f:close()
	st.turns = st.turns + m.game.turn
	st.how[m.game.how or "?"] = (st.how[m.game.how or "?"] or 0) + 1
	print(string.format("physmatch %d: %s in %d turns (%s)", gi, match.teamName(m.game.winner), m.game.turn, m.game.how))
end
print(string.format("physmatch: %d games, %d throws, %.1f s", n, throws, os.clock() - t0))
local function pct(k) return k[1] > 0 and 100 * k[2] / k[1] or 0 end
local hows = {}
for h, c in pairs(st.how) do hows[#hows + 1] = string.format("%s %d", h, c) end
table.sort(hows)
print(string.format("physmatch: %.1f turns a game; batons hit base %d/%d (%.0f%%), field %d/%d (%.0f%%), king %d/%d; "
	.. "%d helicopters; %d kubbs drilled, %d rethrown, %d punishment; ended: %s",
	st.turns / n, st.base[2], st.base[1], pct(st.base), st.field[2], st.field[1], pct(st.field), st.king[2], st.king[1],
	st.heli, st.tosses, st.rethrow, st.punish, table.concat(hows, ", ")))
