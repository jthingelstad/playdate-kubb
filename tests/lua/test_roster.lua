-- core/roster: saved players (docs/PLAYERS.md section 2).
import "core/roster"
import "core/save"
import "core/throwplan"
local roster, save, plan = tw.roster, tw.save, tw.plan

local DAY = "2026-11-15"

test("roster: add, unique ids, rename, level, remove", function()
	local r = roster.new()
	local kim = roster.add(r, "Kim", "pro", DAY)
	expect.eq(kim.key, "p1")
	expect.eq(kim.id, "kim")
	expect.eq(kim.level, "pro")
	expect.eq(kim.totals.batons, 0)
	local jo = roster.add(r, "Jo", nil, DAY)
	expect.eq(jo.level, plan.tune.defaultLevel)
	expect.eq(select(2, roster.add(r, "jo-", nil, DAY)), "taken", "the same id is taken")
	expect.eq(select(2, roster.add(r, "123", nil, DAY)), "empty")
	expect.eq(roster.add(r, "Ann-Marie O'Neil", nil, DAY).name, "Ann-Marie", "cut to ten letters, then finished")
	expect.truthy(roster.rename(r, "p2", "Joanna"))
	expect.eq(roster.find(r, "p2").id, "joanna")
	expect.eq(select(2, roster.rename(r, "p2", "Kim")), "taken")
	expect.truthy(roster.rename(r, "p1", "KIM"), "a player may keep their own id")
	expect.eq(roster.setLevel(r, "p1", "beginner"), "pro")
	expect.eq(roster.setLevel(r, "p1", "beginner"), nil, "no change")
	expect.eq(roster.setLevel(r, "p1", "legend"), nil, "not a level")
	expect.truthy(roster.remove(r, "p1"))
	expect.eq(roster.find(r, "p1"), nil)
	expect.eq(roster.add(r, "Lee", nil, DAY).key, "p4", "keys are never reused")
end)

test("roster: the cap", function()
	local r = roster.new()
	for i = 1, roster.tune.max do
		local name = ""
		local n = i
		repeat name = name .. string.char(96 + (n - 1) % 26 + 1); n = (n - 1) // 26 until n == 0
		expect.truthy(roster.add(r, "P" .. name, nil, DAY), "player " .. i)
	end
	expect.eq(select(2, roster.add(r, "Zed", nil, DAY)), "full")
	expect.truthy(roster.rename(r, "p1", "Zed"), "a rename is not an add")
end)

test("roster: a saved roster reads back, and a bad one is cleaned", function()
	local r = roster.new()
	roster.add(r, "Kim", "pro", DAY)
	roster.add(r, "Max", nil, DAY).totals.hits = 3
	local d = save.plain(save.plain(r))
	local back = roster.valid(d)
	expect.eq(#back.players, 2)
	expect.eq(back.players[1].level, "pro")
	expect.eq(back.players[2].totals.hits, 3)
	expect.eq(back.nextKey, 3)
	expect.eq(#roster.valid(nil).players, 0)
	expect.eq(#roster.valid("junk").players, 0)
	local bad = roster.valid { nextKey = 1, players = {
		{ key = "p5", name = "Kim", level = "legend", totals = { hits = -2, batons = "x" } },
		{ key = "p6", name = "kim" },           -- the same id
		{ key = "p5", name = "Ray" },           -- the same key
		{ key = "q", name = "Sol" },            -- not a key
		{ key = "p7", name = "42" },            -- no letter
		"nothing",
	} }
	expect.eq(#bad.players, 1)
	expect.eq(bad.players[1].level, plan.tune.defaultLevel)
	expect.eq(bad.players[1].totals.hits, 0)
	expect.eq(bad.nextKey, 6, "never below a key in use")
end)

test("roster: most recently played first", function()
	local r = roster.new()
	roster.add(r, "Ann", nil, "2026-11-01").last = "2026-11-10"
	roster.add(r, "Bo", nil, "2026-11-02")
	roster.add(r, "Cy", nil, "2026-11-03").last = "2026-11-12"
	roster.add(r, "Di", nil, "2026-11-03")
	local names = {}
	for i, p in ipairs(roster.sorted(r)) do names[i] = p.name end
	expect.eq(table.concat(names, " "), "Cy Ann Di Bo")
end)

test("roster: the names typed before become players", function()
	local r = roster.new()
	local added = roster.migrateNames(r, { match = { A = "Ash", B = "Team B" }, vs = { A = "ash" } }, DAY)
	expect.eq(#added, 1, "a default and a second Ash are left out")
	expect.eq(r.players[1].name, "Ash")
	expect.eq(#roster.migrateNames(r, nil, DAY), 0)
end)
