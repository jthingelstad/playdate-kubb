-- core/history: what a saved player's history keeps (docs/PLAYERS.md
-- section 2), folded from whole games and drill runs.
import "core/history"
import "core/roster"
import "core/rules"
import "core/cards"
import "core/drills"
import "core/save"
local history, roster, rules, cards, drills, save = tw.history, tw.roster, tw.rules, tw.cards, tw.drills, tw.save

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local thrower = dofile(here .. "/../../tools/thrower.lua")

test("history: a player's stats from the sheet", function()
	local g = rules.new { teams = { A = { name = "A", players = { { name = "Kim" }, { name = "Max" } } },
		B = { name = "B", players = { { name = "Sam" } } } }, opening = "six" }
	local t = g.sheet:beginTurn(1, "A")
	t.inkast.kim = { I = 3, R = 1, P = 1, Q = 0, N = 0, E = false }
	for _, b in ipairs { { "kim", "2F" }, { "kim", "-" }, { "max", "FB" }, { "max", "=" }, { "max", "Z" },
		{ "kim", "BE" }, { nil, "X" } } do
		g.sheet:baton(b[1], b[2])
	end
	local s = history.gameStats(g)
	expect.eq(s.kim.batons, 3)
	expect.eq(s.kim.hits, 1, "BE toppled the king early: no hit")
	expect.eq(s.kim.field, 2)
	expect.eq(s.kim.I + s.kim.R + s.kim.P, 5)
	expect.eq(s.max.batons, 3)
	expect.eq(s.max.hits, 1)
	expect.eq(s.max.kingMisses, 1)
	expect.eq(s.max.illegal, 1)
	expect.eq(s.sam.batons, 0)
	expect.eq(s.sam.side, "B")
end)

test("history: 30 games folded into the roster match the sheets, capped at the recent games", function()
	local r = roster.new()
	local hs = {}
	local wantBatons, wantHits = {}, {}
	for seed = 1, 30 do
		local g = thrower.playGame(seed)
		-- every player of Team A is a saved player (made when first seen)
		local keys = {}
		for _, p in ipairs(g.teams.A.players) do
			local rec = roster.byId(r, p.id) or roster.add(r, p.name, nil, "2026-11-15")
			if rec and rec.id == p.id then keys[p.id] = rec.key end
		end
		local stats = history.gameStats(g)
		for pid, key in pairs(keys) do
			wantBatons[key] = (wantBatons[key] or 0) + stats[pid].batons
			wantHits[key] = (wantHits[key] or 0) + stats[pid].hits
		end
		-- the team's batons and hits are what the winner card counts
		local hits, thrown = cards.hitRate(g, "A")
		local sh, sb = 0, 0
		for _, p in ipairs(g.teams.A.players) do sh, sb = sh + stats[p.id].hits, sb + stats[p.id].batons end
		expect.eq(sh .. "/" .. sb, hits .. "/" .. thrown, "seed " .. seed .. ": the team's hits")
		history.foldGame(r, hs, g, { keys = keys, date = "2026-11-" .. (10 + seed % 20) .. " 19:00",
			file = "game" .. seed .. ".txt" })
	end
	for key, b in pairs(wantBatons) do
		local p = roster.find(r, key)
		expect.eq(p.totals.batons, b, key .. " batons")
		expect.eq(p.totals.hits, wantHits[key], key .. " hits")
		expect.truthy(#hs[key].games <= history.tune.games)
		expect.eq(p.totals.games >= #hs[key].games, true)
		expect.truthy(p.last, "played")
	end
	-- a history file reads back as it was written
	for key, h in pairs(hs) do
		local back = history.valid(save.plain(save.plain(h)))
		expect.eq(#back.games, #h.games, key)
	end
end)

test("history: won, lost and resigned", function()
	local function game(how)
		local g = rules.new { teams = { A = { name = "Ash", players = { { name = "Kim" } } },
			B = { name = "Birch", players = { { name = "Sam" } } } }, opening = "six" }
		if how == "resign" then g:resign("A") else
			for _ = 1, 6 do g:throwBaton({}) end
			for _ = 1, 6 do g:throwBaton({}) end
			g:resign("A")
		end
		return g
	end
	local r = roster.new()
	local kim, sam = roster.add(r, "Kim", nil, "2026-11-15"), roster.add(r, "Sam", nil, "2026-11-15")
	local hs = {}
	local g = game("resign")
	history.foldGame(r, hs, g, { keys = { kim = kim.key, sam = sam.key }, date = "2026-11-16 10:00", file = "x.txt" })
	expect.eq(hs[kim.key].games[1].res, "resigned")
	expect.eq(hs[kim.key].games[1].vs, "Birch")
	expect.eq(hs[sam.key].games[1].res, "won")
	expect.eq(kim.totals.resigned, 1)
	expect.eq(sam.totals.wins, 1)
	expect.eq(sam.last, "2026-11-16")
end)

test("history: drill runs and level changes", function()
	local r = roster.new()
	local kim = roster.add(r, "Kim", "club", "2026-11-15")
	local h = history.new()
	local d = drills.byId("king")
	local run = drills.newRun(d)
	run.score = 3
	local rec, best = history.foldDrill(r, h, kim.key, d, run, "2026-11-17 09:30")
	expect.eq(rec.best, 3)
	expect.truthy(best)
	expect.eq(kim.last, "2026-11-17")
	expect.truthy(history.setLevel(r, h, kim.key, "pro", "2026-11-18"))
	expect.eq(history.setLevel(r, h, kim.key, "pro", "2026-11-18"), false)
	expect.eq(h.levels[1].from .. ">" .. h.levels[1].to, "club>pro")
	for i = 1, 15 do history.setLevel(r, h, kim.key, i % 2 == 0 and "pro" or "beginner", "2026-11-19") end
	expect.eq(#h.levels, history.tune.levels)
	local back = history.valid(save.plain(save.plain(h)))
	expect.eq(back.drills.king.best, 3)
end)
