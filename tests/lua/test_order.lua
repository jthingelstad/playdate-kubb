-- core/order: who throws each baton and kubb inside a team (docs/PLAYERS.md
-- section 5), within Rules V4.0 II.A.4 and II.B.5.
import "core/order"
import "core/rules"
local order, rules = tw.order, tw.rules

local function team(n)
	local ps = {}
	for i = 1, n do ps[i] = { name = string.char(96 + i) .. "x", id = string.char(96 + i) .. "x" } end   -- ax, bx, ...
	return { name = "T" .. n, players = ps }
end

local function join(t) return table.concat(t, ",") end

test("order: the cap, the different players and the blocks", function()
	expect.eq(order.cap(1, 6), 6)
	expect.eq(order.cap(2, 6), 3)
	for n = 3, 6 do expect.eq(order.cap(n, 6), 2) end
	expect.eq(order.cap(1, 2), 2)
	expect.eq(order.distinct(6, 2), 2)
	expect.eq(order.distinct(1, 2), 1)
	expect.eq(order.distinct(6, 4), 3)
	expect.eq(order.distinct(2, 4), 2)
	expect.eq(order.distinct(6, 6), 1)
	local want = {
		[1] = { "6", "4", "2" }, [2] = { "3,3", "2,2", "1,1" }, [3] = { "2,2,2", "2,1,1", "1,1" },
		[4] = { "2,2,1,1", "1,1,1,1", "1,1" }, [5] = { "2,1,1,1,1", "1,1,1,1", "1,1" },
		[6] = { "1,1,1,1,1,1", "1,1,1,1", "1,1" },
	}
	for n, w in pairs(want) do
		expect.eq(join(order.split(n, 6)), w[1], n .. " players, 6 batons")
		expect.eq(join(order.split(n, 4)), w[2], n .. " players, 4 batons")
		expect.eq(join(order.split(n, 2)), w[3], n .. " players, 2 batons")
	end
end)

test("order: every block deal keeps both rules for teams of 1 to 6", function()
	for n = 1, 6 do
		for _, batons in ipairs { 2, 4, 6 } do
			local o = order.new { A = team(n), B = team(1) }
			for start = 1, n do
				o.A.start = start
				order.beginTurn(o, "A", 1, batons)
				expect.eq(#o.deal, batons)
				expect.truthy(order.check(n, batons, o.deal), n .. " players, " .. batons .. " batons")
			end
		end
	end
end)

test("order: check sees a player over the limit and too few throwers", function()
	expect.eq(order.check(3, 6, { "a", "a", "a" }), false)
	expect.eq(select(2, order.check(3, 6, { "a", "a", "a" })), "cap")
	expect.truthy(order.check(2, 6, { "a", "a", "a", "b", "b", "b" }))
	expect.eq(select(2, order.check(3, 4, { "a", "a", "b", "b" })), "distinct")
	expect.truthy(order.check(3, 4, { "a", "a", "b" }), "a third player can still throw the last")
	expect.truthy(order.check(3, 4, { "a", "b", "b" }), "b throws two, c the last")
	expect.eq(select(2, order.check(3, 4, { "a", "b", "b", "b" })), "cap")
	expect.eq(select(2, order.check(2, 2, { "a", "a" })), "distinct")
	expect.truthy(order.check(1, 2, { "a", "a" }), "a team of one throws both")
end)

test("order: the rotation moves on turn by turn and the inkaster opens the turn", function()
	local o = order.new { A = { name = "A", players = { { id = "kim" }, { id = "max" }, { id = "alex" }, { id = "dana" } } },
		B = { name = "B", players = { { id = "sam" } } } }
	order.beginTurn(o, "A", 1, 2)
	expect.eq(join(o.deal), "kim,max")
	expect.eq(o.inkaster, "kim")
	order.beginTurn(o, "B", 2, 4)
	expect.eq(join(o.deal), "sam,sam,sam,sam")
	order.beginTurn(o, "A", 3, 6)
	expect.eq(join(o.deal), "alex,alex,dana,dana,kim,max", "who missed turn 1 opens turn 3")
	expect.eq(o.inkaster, "alex")
	order.beginTurn(o, "A", 5, 6)
	expect.eq(join(o.deal), "kim,kim,max,max,alex,dana")
end)

test("order: a changed thrower swaps with their later baton, within the rules", function()
	local o = order.new { A = { name = "A", players = { { id = "kim" }, { id = "max" }, { id = "alex" }, { id = "dana" } } },
		B = { name = "B", players = { { id = "sam" } } } }
	order.beginTurn(o, "A", 3, 6)    -- kim kim max max alex dana
	expect.truthy(order.change(o, 5, "dana", 4))
	expect.eq(join(o.deal), "kim,kim,max,max,dana,alex")
	local ok, why = order.change(o, 6, "kim", 5)
	expect.eq(ok, false)
	expect.eq(why, "cap")
	expect.eq(join(o.deal), "kim,kim,max,max,dana,alex", "a refused change leaves the deal")
	expect.eq(select(2, order.change(o, 3, "sam", 2)), "team")
	expect.eq(select(2, order.change(o, 2, "alex", 2)), "thrown")
	expect.truthy(order.change(o, 3, "alex", 2))
	expect.eq(join(o.deal), "kim,kim,alex,max,dana,max")
	expect.truthy(order.setInkaster(o, "dana"))
	expect.eq(o.inkaster, "dana")
	expect.eq(order.setInkaster(o, "sam"), false)
	-- the opening's four batons need three throwers
	local p = order.new { A = team(1), B = { name = "B", players = { { id = "a" }, { id = "b" }, { id = "c" } } } }
	order.beginTurn(p, "B", 2, 4)    -- a a b c
	expect.eq(select(2, order.change(p, 4, "b", 3)), "distinct")
	expect.eq(select(2, order.change(p, 3, "a", 2)), "cap")
	expect.truthy(order.change(p, 2, "c", 1))
	expect.eq(join(p.deal), "a,c,b,a")
end)

test("order: the engine's game asks the order who throws, and the sheet keeps the rules", function()
	local g = rules.new { teams = { A = team(4), B = team(2) }, opening = "2-4-6", first = "A" }
	local o = order.new(g.teams)
	expect.eq(order.thrower(o, g), "ax")
	g:throwBaton({}, order.thrower(o, g))
	expect.eq(order.thrower(o, g), "bx")
	g:throwBaton({}, order.thrower(o, g))
	expect.eq(g.turn, 2)
	for _ = 1, 4 do g:throwBaton({}, order.thrower(o, g)) end
	expect.eq(#order.checkSheet(g), 0)
	local t2 = g.sheet.turns[2]
	expect.eq(t2.batons[1].player .. " " .. t2.batons[3].player, "ax_b bx_b", "Team B's ids clash with A's")
	-- a sheet that breaks II.B.5 is caught
	local h = rules.new { teams = { A = team(3), B = team(3) }, opening = "six", first = "A" }
	for _ = 1, 6 do h:throwBaton({}, "ax") end
	local bad = order.checkSheet(h)
	expect.eq(#bad, 1)
	expect.truthy(bad[1]:find("II.B.5", 1, true))
end)
