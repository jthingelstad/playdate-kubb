-- Notation tokens, ids, times, file names, and a full scripted game.
import "core/notation"
import "core/rules"
local notation, rules = tw.notation, tw.rules

test("inkast tokens: I R P Q N counts, 1 left out, E suffix", function()
	local t = notation.inkastBody
	expect.eq(t { I = 5, R = 2 }, "5I2R")
	expect.eq(t { I = 2, R = 1, P = 1 }, "2IRP")
	expect.eq(t { I = 7, R = 3, P = 2 }, "7I3R2P")
	expect.eq(t { I = 3, Q = 1 }, "3IQ")
	expect.eq(t { I = 4, N = 2 }, "4I2N")
	expect.eq(t { I = 4, E = true }, "4IE")
	expect.eq(t { I = 1 }, "I")
	expect.eq(t { I = 10, R = 10 }, "10I10R")
	expect.eq(t { I = 9, N = 7 }, "9I5N", "N is capped at 5 (the grammar's limit)")
end)

test("baton tokens: - F 2F B 2FB 2B FE E", function()
	local h = notation.hitToken
	expect.eq(h(0, 0), "-")
	expect.eq(h(1, 0), "F")
	expect.eq(h(2, 0), "2F")
	expect.eq(h(0, 1), "B")
	expect.eq(h(0, 2), "2B")
	expect.eq(h(2, 1), "2FB")
	expect.eq(h(1, 0, true), "FE")
	expect.eq(h(0, 0, true), "E")
end)

test("turn line: inkast, advantage, batons, notes; no inkast token when nothing was thrown", function()
	local s = notation.sheet()
	s:beginTurn(7, "A")
	s:ink("j", "I", 5); s:ink("j", "R", 2)
	s:advantage(2)
	s:baton("j", "2F"); s:baton("j", "K"); s:baton(nil, "X")
	s:note("first note"); s:note("second # note")
	expect.eq(notation.turnLine(s.turns[7]), "7. j:5I2R 2A j:2F j:K X # first note; second   note")
	s:beginTurn(8, "B")
	s:baton("c", "-")
	expect.eq(notation.turnLine(s.turns[8]), "8. c:-")
end)

test("player ids: lowercased letters and underscores, from names, unique", function()
	expect.eq(notation.baseId("Jamie"), "jamie")
	expect.eq(notation.baseId("Ann-Marie O'Neil"), "ann_marie_oneil")
	expect.eq(notation.baseId("  Club 2 "), "club")
	expect.eq(notation.baseId("R2-D2"), "r_d")
	expect.eq(notation.baseId("42"), "p")
	local teams = { A = { players = { { name = "Dave" }, { name = "Dave" } } },
		B = { players = { { name = "dave" }, { name = "Zoë" } } } }
	notation.assignIds(teams)
	expect.eq(teams.A.players[1].id, "dave")
	expect.eq(teams.A.players[2].id, "dave_b")
	expect.eq(teams.B.players[1].id, "dave_c")
	expect.eq(teams.B.players[2].id, "zo")
	for _, side in ipairs { "A", "B" } do
		for _, p in ipairs(teams[side].players) do expect.truthy(p.id:match("^[a-z_]+$"), p.id) end
	end
end)

test("header names lose quotes and brackets; player names lose commas and parentheses", function()
	expect.eq(notation.cleanName('The "Best" [Team]'), "The Best Team")
	expect.eq(notation.cleanName("Smith, Jo (captain)", true), "Smith Jo captain")
end)

test("times: duration across midnight and month ends; file name", function()
	local a = { year = 2026, month = 12, day = 31, hour = 23, min = 50 }
	local b = notation.addMinutes(a, 25)
	expect.eq(notation.formatTime(b), "2027-01-01 00:15")
	expect.eq(notation.minutesBetween(a, b), 25)
	expect.eq(notation.formatTime(notation.addMinutes({ year = 2028, month = 2, day = 28, hour = 12, min = 0 }, 1440)), "2028-02-29 12:00")
	expect.eq(notation.filename({ year = 2026, month = 11, day = 20, hour = 19, min = 42 }, "Jamie", "Playdate"),
		"2026-11-20-1942-jamie-v-playdate.txt")
	expect.eq(notation.filename({ year = 2026, month = 1, day = 2, hour = 3, min = 4 }, "The Ringers!", "King Pin"),
		"2026-01-02-0304-the-ringers-v-king-pin.txt")
end)

-- A whole game through the engine: II.B.1, II.B.2, II.B.4a, FB, rethrow,
-- II.D.6 (N), rescue (Q), king shots (= and K) and X.
local EXPECTED = [[
[Event "Throwing Wood"]
[Location "Playdate"]
[Start "2026-11-20 19:42"]
[End "2026-11-20 20:05"]
[Duration "23m"]
[Surface "Sand"]
[Team A "Jamie"]
[Team A Players "Jamie (jamie)"]
[Team B "Playdate"]
[Team B Players "Club (club)"]
[First "Team A"]
[Win "Team B"]
[Scored by "Throwing Wood 0.0.1"]
[Mode "Pass and Play"]
[Rules "U.S. Championship 4.0, 2-4-6"]

1. jamie:B jamie:-
2. club:I club:- club:- club:- club:-
3. 2A jamie:B jamie:B jamie:- jamie:Z jamie:- jamie:-
4. club:2IRN club:F club:F club:F club:B club:- club:- # b2 toppled a base kubb early; raised (II.B.4a)
5. jamie:4I jamie:F jamie:F jamie:- jamie:- jamie:- jamie:-
6. club:2I 3A club:F club:FB club:B club:2B club:= club:=
7. jamie:7IQ jamie:- jamie:- jamie:- jamie:- jamie:- jamie:-
8. 3A club:= club:K X X X X
]]

test("a full scripted game renders exactly", function()
	local g = rules.new { teams = { A = { name = "Jamie", players = { { name = "Jamie" } } },
		B = { name = "Playdate", players = { { name = "Club" } } } }, surface = "Sand" }
	local function L(x, y, a, e)
		local o = { rest = { x = x, y = y, standing = a == "stand", angle = type(a) == "number" and a or 0 }, moved = {} }
		for k, v in pairs(e or {}) do o[k] = v end
		return o
	end
	local M = {}
	local function T(...) return { toppled = { ... } } end
	local function B(list) for _, o in ipairs(list) do g:throwBaton(o) end end
	B { T("b3"), M }                                                    -- 1
	g:toss(L(0.5, 2.5, "stand")); B { M, M, M, M }                      -- 2
	B { T("b1"), T("b2"), M, { illegal = true, toppled = { "b4" } }, M, M } -- 3
	g:toss(L(-1, 2, 0)); g:toss(L(2.8, 2, math.pi / 2))                 -- 4: b2 out
	g:toss { rest = { x = -0.98, y = 2.03, standing = false, angle = 0.4, onTop = "b1" } }
	g:raiseAll()
	B { T("b3"), T("b1", "a2"), T("b2"), T("a1"), M, M }
	g:toss(L(0, 6, "stand")); g:toss(L(-1, 6, "stand")); g:toss(L(1, 6, "stand")); g:toss(L(-2, 5, "stand")) -- 5
	B { T("b1"), T("b2"), M, M, M, M }
	g:toss(L(0, 2, "stand")); g:toss(L(1, 2, "stand"))                  -- 6
	B { T("b1"), T("b2", "a2"), T("a3"), T("a4", "a5"), M, M }
	g:toss(L(0.1, 6.2, 0, { moved = { a1 = { x = 2.9, y = 6, standing = false, angle = math.pi / 2 } } })) -- 7
	for _, p in ipairs { { 0.5, 7 }, { -0.5, 7 }, { 1.5, 7 }, { -1.5, 7 }, { 0, 5 }, { 1, 5 } } do
		g:toss(L(p[1], p[2], "stand"))
	end
	g:raiseAll()
	B { M, M, M, M, M, M }
	B { M, { kingToppled = true } }                                      -- 8
	local text = notation.render(g, { start = { year = 2026, month = 11, day = 20, hour = 19, min = 42 },
		finish = { year = 2026, month = 11, day = 20, hour = 20, min = 5 }, version = "0.0.1", mode = "Pass and Play" })
	if text ~= EXPECTED then
		error("rendered game differs:\n" .. text)
	end
end)

test("six from the start is named in the Rules header", function()
	local g = rules.new { opening = "six" }
	g:resign("A")
	local text = notation.render(g, {})
	expect.truthy(text:find('[Rules "U.S. Championship 4.0, six from the start"]', 1, true))
	expect.truthy(text:find('[Win "Team B"]', 1, true))
	expect.truthy(text:find("\n1. team_a:G X X X X X X\n", 1, true))
end)
