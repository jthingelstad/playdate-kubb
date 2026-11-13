-- The turn engine, one test per rule cited (Rules V4.0).
import "core/rules"
import "core/notation"
local rules, notation = tw.rules, tw.notation

local function newGame(o)
	o = o or {}
	return rules.new {
		teams = { A = { name = "Jamie", players = { { name = "Jamie" } } },
			B = { name = "Playdate", players = { { name = "Club" } } } },
		opening = o.opening, first = o.first, surface = o.surface,
	}
end

local MISS = {}
local function topple(...) return { toppled = { ... } } end
-- A toss landing at (x, y): lying along angle a, or standing on an end.
local function land(x, y, a, extra)
	local o = { rest = { x = x, y = y, standing = a == "stand", angle = type(a) == "number" and a or 0 }, moved = {} }
	for k, v in pairs(extra or {}) do o[k] = v end
	return o
end
local function stand(x, y) return { x = x, y = y, standing = true, angle = 0 } end
local function lie(x, y, a) return { x = x, y = y, standing = false, angle = a or 0 } end
local function line(g, n) return notation.turnLine(g.sheet.turns[n or g.turn]) end
local function batons(g, list) for _, o in ipairs(list) do g:throwBaton(o) end end
local function misses(g, n) for _ = 1, n do g:throwBaton(MISS) end end

-- Turn 1: A misses twice. Turn 2: B topples a1 and a2. Turn 3 begins with
-- A tossing a1 and a2 into B's half; `spots` are their toss outcomes.
local function toTurn3(g, spots)
	misses(g, 2)
	batons(g, { topple("a1"), topple("a2"), MISS, MISS })
	expect.eq(g.turn, 3)
	for _, o in ipairs(spots or {}) do g:toss(o) end
	return g
end

-- a1 and a2 standing at (0, 6) and (1, 6) in B's half, A's batons next.
local function fieldOfTwo(g)
	return toTurn3(g, { land(0, 6, "stand"), land(1, 6, "stand") })
end

test("II.A opening 2-4-6: two batons, then four, then six", function()
	local g = newGame()
	expect.eq(g:need().of, 2); expect.eq(g:need().side, "A")
	misses(g, 2)
	expect.eq(g:need().of, 4); expect.eq(g:need().side, "B")
	misses(g, 4)
	expect.eq(g:need().of, 6)
	misses(g, 6)
	expect.eq(g:need().of, 6)
	expect.eq(line(g, 1), "1. jamie:- jamie:-")
	expect.eq(line(g, 2), "2. club:- club:- club:- club:-")
end)

test("II.A option: six batons from the start, and Team B first", function()
	local g = newGame { opening = "six", first = "B" }
	expect.eq(g:need().of, 6); expect.eq(g:need().side, "B")
	expect.eq(rules.batonsFor("six", 1), 6)
	expect.eq(rules.batonsFor("2-4-6", 3), 6)
end)

test("II.B.1 illegal throw: kubbs it toppled are raised where they were, the baton is forfeited (Z)", function()
	local g = fieldOfTwo(newGame())
	g:throwBaton { illegal = true, toppled = { "a1", "b3" }, moved = { a1 = lie(0.2, 6.3) } }
	expect.eq(g.kubbs.a1.where, "pitch"); expect.eq(g.kubbs.a1.pose.x, 0); expect.truthy(g.kubbs.a1.pose.standing)
	expect.eq(g.kubbs.b3.where, "pitch")
	expect.eq(g:need().n, 2, "the baton was used")
	expect.eq(line(g), "3. jamie:2I jamie:Z")
end)

test("II.B.1 interpretation: an illegal throw that topples the king early still loses (E)", function()
	local g = fieldOfTwo(newGame())
	g:throwBaton { illegal = true, kingToppled = true }
	expect.eq(g.winner, "B")
	expect.eq(line(g), "3. jamie:2I jamie:E X X X X X # b1 illegal throw toppled the king early")
end)

test("II.B.2 advantage line through the field kubb closest to the centerline; nA from the attacker's baseline", function()
	local g = toTurn3(newGame(), { land(0, 6.5, "stand"), land(1, 5.2, "stand") })
	misses(g, 6)  -- A leaves both standing
	local n = g:need()
	expect.eq(n.side, "B")
	expect.near(n.advantageY, 5.2, 1e-12)
	expect.near(n.throwY, 5.2, 1e-12, "base kubbs may be attacked from the line")
	expect.eq(g.sheet.turns[4].advantage, 2, "2.8 m from B's baseline rounds down to 2")
	expect.eq(tw.pitch.advantageMeters("A", 3.99), 3)
	expect.eq(tw.pitch.advantageMeters("B", 4.0), 4)
	expect.eq(tw.pitch.advantageMeters("B", 7.5), 0)
end)

test("II.B.2 king shots are from the baseline even with an advantage line; K wins", function()
	local g = toTurn3(newGame(), { land(0, 6.5, "stand"), land(1, 5.2, "stand") })
	misses(g, 6)
	batons(g, { topple("a3"), topple("a4"), topple("a5") })
	local n = g:need()
	expect.truthy(n.kingShot)
	expect.eq(n.throwY, 8)
	expect.eq(n.targets[1], "king")
	g:throwBaton { kingToppled = true }
	expect.eq(g.winner, "B"); expect.eq(g.how, "king")
	expect.eq(line(g, 4), "4. 2A club:B club:B club:B club:K X X")
	expect.eq(g:need().kind, "over")
end)

test("king shot missed is =; a baton is a king shot only when every kubb is down", function()
	local g = toTurn3(newGame(), { land(0, 6.5, "stand"), land(1, 5.2, "stand") })
	misses(g, 6)
	expect.eq(g:need().kingShot, false)
	batons(g, { topple("a3"), topple("a4"), topple("a5"), MISS })
	expect.eq(line(g, 4), "4. 2A club:B club:B club:B club:=")
end)

test("king toppled by a baton before every kubb is down: the attacker loses (FE, X for the rest)", function()
	local g = fieldOfTwo(newGame())
	g:throwBaton { toppled = { "a1" }, kingToppled = true }
	expect.eq(g.winner, "B")
	expect.eq(line(g), "3. jamie:2I jamie:FE X X X X X # b1 toppled the king early")
	local ok = pcall(g.throwBaton, g, MISS)
	expect.eq(ok, false, "no baton after game over")
end)

test("II.B.4a a base kubb toppled while a field kubb stands is raised and stays a base kubb", function()
	local g = fieldOfTwo(newGame())
	g:throwBaton(topple("a1", "b3"))
	expect.eq(g.kubbs.b3.where, "pitch"); expect.eq(g.kubbs.b3.kind, "base")
	expect.eq(line(g), "3. jamie:2I jamie:F # b1 toppled a base kubb early; raised (II.B.4a)")
end)

test("II.B.4a a baton that takes the last field kubb and a base kubb counts both: FB", function()
	local g = fieldOfTwo(newGame())
	batons(g, { topple("a1"), topple("a2", "b4") })
	expect.eq(g.kubbs.b4.where, "hand")
	expect.eq(line(g), "3. jamie:2I jamie:F jamie:FB")
	misses(g, 4)
	expect.eq(g:need().kind, "toss")
	expect.eq(g:need().left, 3, "B throws in the three kubbs it lost")
end)

test("II.B.7 a kubb pushed out of bounds without toppling goes back; pushed in bounds it stays", function()
	local g = fieldOfTwo(newGame())
	g:throwBaton { moved = { a1 = stand(-2.7, 6), a2 = stand(1.2, 6.1) } }
	expect.eq(g.kubbs.a1.pose.x, 0)
	expect.eq(g.kubbs.a2.pose.x, 1.2)
	expect.eq(line(g), "3. jamie:2I jamie:- # b1 pushed a kubb out without toppling; put back (II.B.7)")
end)

test("II.B.10 a toppled kubb that comes to rest standing on an end is still toppled", function()
	local g = fieldOfTwo(newGame())
	g:throwBaton { toppled = { "a1" }, moved = { a1 = stand(0, 6.4) } }
	expect.eq(g.kubbs.a1.where, "hand")
	expect.eq(line(g), "3. jamie:2I jamie:F")
end)

test("II.B.11 own-half field kubbs hit: they and anything toppled go back, the baton is forfeited (Z)", function()
	local g = toTurn3(newGame(), { land(0, 6.5, "stand"), land(1, 5.2, "stand") })
	misses(g, 6)
	g:throwBaton { toppled = { "a3" }, ownHalfHit = { "a2" } }
	expect.eq(g.kubbs.a3.where, "pitch")
	g:throwBaton { toppled = { "a1", "a4" } }   -- a1 is in B's own half too
	expect.eq(g.kubbs.a1.where, "pitch"); expect.eq(g.kubbs.a4.where, "pitch")
	expect.eq(line(g, 4), "4. 2A club:Z club:Z # b1 hit a field kubb in the thrower's own half; all put back (II.B.11); "
		.. "b2 hit a field kubb in the thrower's own half; all put back (II.B.11)")
end)

test("king toppled by a thrown kubb: the throwing team loses (IE); the token counts every kubb due", function()
	local g = toTurn3(newGame())
	g:toss(land(0, 4.1, 0, { kingToppled = true }))
	expect.eq(g.winner, "B")
	expect.eq(line(g), "3. jamie:2IE X X X X X X # king toppled by a thrown kubb")
end)

test("II.C.4 a thrown kubb that strikes a field kubb: each is raised where it comes to rest", function()
	local g = toTurn3(newGame(), { land(0, 6, "stand") })
	g:toss(land(0.1, 6, 0, { moved = { a1 = lie(0.5, 6.4, math.pi / 2) } }))
	expect.eq(g.phase, "raise")
	g:raiseAll("first")
	expect.near(g.kubbs.a1.pose.x, 0.5, 1e-9)
	expect.near(g.kubbs.a1.pose.y, 6.51, 1e-9)
	expect.truthy(g.kubbs.a1.pose.standing and g.kubbs.a2.pose.standing)
	expect.eq(g.phase, "batons")
end)

test("II.C.4b a thrown kubb that hits a field kubb in the thrower's own half: put back, thrown kubb out", function()
	local g = fieldOfTwo(newGame())
	batons(g, { topple("a1"), MISS, MISS, MISS, MISS, MISS })   -- a2 stays in B's half
	expect.eq(g:need().kubb, "a1")
	g:toss(land(0, 3, 0, { moved = { a2 = lie(1.2, 6.3) } }))
	expect.eq(g.kubbs.a2.pose.x, 1, "put back"); expect.truthy(g.kubbs.a2.pose.standing)
	local n = g:need()
	expect.eq(n.kubb, "a1"); expect.truthy(n.rethrow)
	g:toss(land(0, 2, "stand"))
	expect.eq(g.phase, "batons")
	expect.eq(line(g), "4. club:IR 2A # a kubb hit a field kubb in the thrower's own half (II.C.4b)")
end)

test("II.C.5a rescue: an established field kubb knocked out returns to be thrown, counted in I and Q", function()
	local g = fieldOfTwo(newGame())
	misses(g, 6)
	batons(g, { topple("a3"), MISS, MISS, MISS, MISS, MISS })
	expect.eq(g.turn, 5)
	expect.truthy(g.kubbs.a1.established)
	g:toss(land(0, 6.3, 0, { moved = { a1 = lie(0, 8.6, 0) } }))
	local n = g:need()
	expect.eq(n.kubb, "a1"); expect.eq(n.rethrow, false, "treated as not yet thrown")
	g:toss(land(-1, 7, "stand"))
	g:raiseAll()
	expect.eq(line(g), "5. jamie:2IQ")
end)

test("II.C.5b a struck kubb thrown once this turn that cannot be raised in bounds is rethrown (R)", function()
	local g = toTurn3(newGame(), { land(0, 7.85, "stand") })
	g:toss(land(0.1, 7.6, 0, { moved = { a1 = lie(0, 8.4, 0) } }))
	local n = g:need()
	expect.eq(n.kubb, "a1"); expect.truthy(n.rethrow)
	g:toss(land(0, 6, "stand"))
	g:raiseAll()
	expect.eq(line(g), "3. jamie:2IR")
end)

test("II.C.5c a struck kubb already thrown twice is a punishment kubb (P)", function()
	local g = toTurn3(newGame(), { land(0, 8.4, 0), land(1, 8.4, 0) })   -- both out
	g:toss(land(0, 7.85, "stand"))                                        -- a1 rethrown in
	g:toss(land(0.1, 7.6, 0, { moved = { a1 = lie(0, 8.4, 0) } }))        -- a2 rethrown, knocks a1 out
	g:raiseAll()
	local n = g:need()
	expect.eq(n.kind, "punish"); expect.eq(n.kubb, "a1")
	expect.eq(line(g), "3. jamie:2I2RP")
end)

test("II.C.6 out kubbs are rethrown after all first throws; out twice is a punishment kubb placed by the defender", function()
	local g = toTurn3(newGame(), { land(0, 3.8, 0) })   -- a1 short of the centerline
	local n = g:need()
	expect.eq(n.kubb, "a2"); expect.eq(n.rethrow, false, "first throws first")
	g:toss(land(1, 6, "stand"))
	n = g:need()
	expect.eq(n.kubb, "a1"); expect.truthy(n.rethrow)
	g:toss(land(2.7, 6, math.pi / 2))                  -- out over the sideline again
	n = g:need()
	expect.eq(n.kind, "punish"); expect.eq(n.side, "B")
	local ok, why = g:placePunishment(stand(0, 4.2))
	expect.eq(ok, false); expect.eq(why, "closer than a baton length to the king")
	expect.truthy(g:placePunishment(stand(-1, 7)))
	expect.eq(g.kubbs.a1.kind, "field"); expect.eq(g.kubbs.a1.half, "B")
	expect.eq(g.phase, "batons")
	expect.eq(line(g), "3. jamie:2IRP")
end)

test("II.D.2 a thrown kubb standing on an end in bounds is already raised and not moved", function()
	local g = toTurn3(newGame(), { land(0.3, 6.2, "stand"), land(-0.4, 5, "stand") })
	expect.eq(g.phase, "batons", "nothing to raise")
	expect.near(g.kubbs.a1.pose.x, 0.3, 1e-12)
end)

test("II.D.6 a kubb resting on another is lowered beside it, N counted", function()
	local g = toTurn3(newGame(), { land(0, 6, 0) })
	g:toss { rest = { x = 0.02, y = 6.04, standing = false, angle = 0.2, onTop = "a1" } }
	expect.eq(g.kubbs.a2.pose.onTop, nil)
	expect.eq(tw.rect.overlap(tw.raising.kubbRect(g.kubbs.a2.pose), tw.raising.kubbRect(g.kubbs.a1.pose)), false)
	g:raiseAll()
	expect.eq(line(g), "3. jamie:2IN")
end)

test("II.D.6 a kubb resting on a kubb it moved is lowered beside where that kubb came to rest", function()
	local g = toTurn3(newGame(), { land(0, 6, 0) })
	-- the toss pushes a1 a metre and a half and comes to rest on top of it
	g:toss { rest = { x = 0.02, y = 7.52, standing = false, angle = 0.2, onTop = "a1" },
		moved = { a1 = lie(0, 7.5, 0) } }
	expect.near(g.kubbs.a1.pose.y, 7.5, 1e-9)
	expect.eq(g.kubbs.a2.pose.onTop, nil)
	expect.eq(tw.rect.overlap(tw.raising.kubbRect(g.kubbs.a2.pose), tw.raising.kubbRect(g.kubbs.a1.pose)), false)
	local dx, dy = g.kubbs.a2.pose.x - 0.02, g.kubbs.a2.pose.y - 7.52
	expect.truthy(dx * dx + dy * dy > 1e-6, "it was lowered off the kubb under it")
end)

test("the inkast is the kubbs knocked down last turn; no inkast token when there are none", function()
	local g = newGame()
	batons(g, { topple("b1"), topple("b2") })
	expect.eq(g:need().kind, "toss"); expect.eq(g:need().left, 2)
	g:toss(land(0, 2, "stand")); g:toss(land(1, 2, "stand"))
	misses(g, 4)
	expect.eq(g:need().kind, "baton", "B knocked nothing: no inkast for A")
	expect.eq(line(g, 2), "2. club:2I club:- club:- club:- club:-")
end)

test("resign: G on the resigning team's own turn, X for the batons left", function()
	local g = newGame()
	g:throwBaton(MISS)
	expect.eq(pcall(g.resign, g, "B"), false, "not on the other team's turn")
	g:resign("A")
	expect.eq(g.winner, "B"); expect.eq(g.how, "resigned")
	expect.eq(line(g), "1. jamie:- jamie:G X")
end)

test("resign during the inkast writes the whole inkast and a note", function()
	local g = toTurn3(newGame(), { land(0, 6, "stand") })
	g:resign("A")
	expect.eq(line(g), "3. jamie:2I jamie:G X X X X X X # resigned during the inkast")
end)

test("ten kubbs are always accounted for", function()
	local g = fieldOfTwo(newGame())
	local c = g:census()
	expect.eq(c.total, 10); expect.eq(c.pitch, 10)
	batons(g, { topple("a1"), topple("a2", "b5") })
	c = g:census()
	expect.eq(c.pitch, 7); expect.eq(c.hand, 3)
end)
