-- core/cards: what the hand-off and winner cards say, from the engine.
import "core/cards"
import "core/match"
local cards, match = tw.cards, tw.match

test("cards: baton tokens to kubbs, hits and throws", function()
	local function c(t) return { cards.batonCounts(t) } end
	local cases = {
		["-"] = { 0, 0, false, true }, ["F"] = { 1, 0, true, true }, ["2F"] = { 2, 0, true, true },
		["B"] = { 0, 1, true, true }, ["3B"] = { 0, 3, true, true }, ["2FB"] = { 2, 1, true, true },
		["F2B"] = { 1, 2, true, true }, ["K"] = { 0, 0, true, true }, ["="] = { 0, 0, false, true },
		["Z"] = { 0, 0, false, true }, ["E"] = { 0, 0, false, true }, ["2FE"] = { 2, 0, true, true },
		["BE"] = { 0, 1, true, true }, ["X"] = { 0, 0, false, false }, ["G"] = { 0, 0, false, false },
	}
	for tok, want in pairs(cases) do
		local got = c(tok)
		for i = 1, 4 do expect.eq(got[i], want[i], tok .. " value " .. i) end
	end
end)

-- A match driven straight through the engine: Team A's two opening batons
-- topple b3 and miss.
local function opened()
	local m = match.new { start = { year = 2026, month = 11, day = 13, hour = 20, min = 50 } }
	local g = m.game
	match.setup(m)
	g:throwBaton { toppled = { "b3" }, moved = { b3 = { x = 0, y = 8.3, standing = false, angle = 0 } } }
	match.setup(m)
	g:throwBaton { toppled = {} }
	return m, g
end

test("cards: the first hand-off has no last turn", function()
	local m = match.new {}
	local c = cards.handoff(m, match.setup(m))
	expect.eq(c.to, "A")
	expect.eq(c.toName, "Team A")
	expect.eq(c.from, nil)
	expect.eq(c.took, nil)
	expect.eq(c.kubbs, 0)
	expect.eq(c.batons, 2, "2-4-6: two batons on turn 1")
	expect.eq(c.turn, 1)
	expect.eq(c.base[1], 5)
	expect.eq(c.base[2], 5)
	expect.eq(#c.pieces, 11, "ten base slots and the king")
	-- Team A throws from the bottom: its base kubbs at y = 0
	for _, p in ipairs(c.pieces) do
		if p.id:sub(1, 1) == "a" then expect.eq(p.y, 0) end
		expect.eq(p.down, false)
	end
end)

test("cards: the hand-off to Team B says what Team A took", function()
	local m, g = opened()
	local s = match.setup(m)
	local c = cards.handoff(m, s)
	expect.eq(c.to, "B")
	expect.eq(c.fromName, "Team A")
	expect.eq(c.took.field, 0)
	expect.eq(c.took.base, 1)
	expect.eq(c.kubbs, 1, "b3 to throw in")
	expect.eq(c.batons, 4)
	expect.eq(c.turn, 2)
	expect.eq(c.base[1], 5, "Team A's base kubbs")
	expect.eq(c.base[2], 4, "Team B's base kubbs")
	-- Team B's view is turned: its own baseline (world y = 8) at the bottom
	local down = 0
	for _, p in ipairs(c.pieces) do
		if p.id == "b3" then
			expect.eq(p.down, true)
			expect.near(p.y, 0, 1e-9)
		end
		if p.down then down = down + 1 end
	end
	expect.eq(down, 1)
end)

test("cards: the winner card counts turns, minutes and the winner's hit rate", function()
	local m, g = opened()
	g:resign("B")
	local c = cards.winner(m, { year = 2026, month = 11, day = 13, hour = 21, min = 6 })
	expect.eq(c.winner, "A")
	expect.eq(c.winnerName, "Team A")
	expect.eq(c.turns, 2)
	expect.eq(c.minutes, 16)
	expect.eq(c.hits, 1)
	expect.eq(c.thrown, 2)
	-- across midnight, and with no start time
	m.start = { year = 2026, month = 11, day = 13, hour = 23, min = 55 }
	expect.eq(cards.winner(m, { year = 2026, month = 11, day = 14, hour = 0, min = 5 }).minutes, 10)
	m.start = nil
	expect.eq(cards.winner(m, { year = 2026, month = 11, day = 14, hour = 0, min = 5 }).minutes, nil)
end)
