-- Positions on the pitch in the game file (Planet Kubb Notation's optional
-- "(@ x,y ...)" after an inkast or a baton token): the frame, what the
-- engine records, the edge cases, and saves from before and after.
import "core/rules"
import "core/notation"
import "core/camera"
import "core/save"
import "core/pitch"
local rules, notation, camera, save, pitch = tw.rules, tw.notation, tw.camera, tw.save, tw.pitch

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local thrower = dofile(here .. "/../../tools/thrower.lua")

local function newGame(players)
	return rules.new {
		teams = { A = { name = "Jamie", players = players or { { name = "Jamie" } } },
			B = { name = "Playdate", players = { { name = "Club" } } } },
	}
end
local MISS = {}
local function topple(...) return { toppled = { ... } } end
local function land(x, y, a)
	return { rest = { x = x, y = y, standing = a == "stand", angle = type(a) == "number" and a or 0 }, moved = {} }
end
local function line(g, n) return notation.turnLine(g.sheet.turns[n or g.turn]) end
local function batons(g, list) for _, o in ipairs(list) do g:throwBaton(o) end end
-- Turn 1: A misses twice. Turn 2: B topples a1 and a2. Turn 3: A to throw them in.
local function toTurn3(g)
	batons(g, { MISS, MISS })
	batons(g, { topple("a1"), topple("a2"), MISS, MISS })
	expect.eq(g.turn, 3)
	return g
end

test("positions: the frame is Team A's baseline, x from the left sideline", function()
	-- the engine's base kubbs: a1..a5 at x = -2..2 on y = 0, b1..b5 on y = 8
	local x, y = notation.pitchXY(pitch.baseX[1], pitch.baseline.A)
	expect.near(x, 0.5, 1e-9); expect.near(y, 0, 1e-9)
	x, y = notation.pitchXY(pitch.baseX[5], pitch.baseline.B)
	expect.near(x, 4.5, 1e-9); expect.near(y, 8, 1e-9)
	-- the king: the middle of column c, on the line between rows 4 and 5
	x, y = notation.pitchXY(pitch.king.x, pitch.king.y)
	expect.near(x, 2.5, 1e-9); expect.near(y, 4, 1e-9)
	-- "left" is left for someone on Team A's baseline looking at Team B's:
	-- the aim camera there puts b1 (x = -2) left of the screen's middle and
	-- b5 (x = 2) right of it, and b1 has the smaller notation x
	local c = camera.new()
	camera.aim(c, 0, pitch.baseline.A, 0)
	local sx1 = camera.project(c, pitch.baseX[1], pitch.baseline.B, 0)
	local sx5 = camera.project(c, pitch.baseX[5], pitch.baseline.B, 0)
	expect.truthy(sx1 < c.cx and sx5 > c.cx, "b1 on the left, b5 on the right")
	expect.truthy(notation.pitchXY(pitch.baseX[1], 8) < notation.pitchXY(pitch.baseX[5], 8))
	-- the sidelines are 0 and 5; nothing is written off the pitch or with a minus
	expect.eq(notation.positions({ { x = -2.5, y = -0.0 }, { x = 2.5, y = 8 } }, 2), " (@ 0.00,0.00 5.00,8.00)")
	expect.eq(notation.positions({ { x = -2.6, y = -0.004 }, { x = 2.7, y = 8.3 } }, 2), " (@ 0.00,0.00 5.00,8.00)")
end)

test("positions: after the token, before the note, never more than the token counts", function()
	local s = notation.sheet()
	s:beginTurn(3, "A")
	s:ink("j", "I", 2)
	s:inkAt("j", 0, 6); s:inkAt("j", -1.18, 7.25); s:inkAt("j", 1, 6)   -- three for a token of two
	s:advantage(1)
	s:baton("j", "2F", { { x = 0, y = 6 }, { x = -1.18, y = 7.25 } })
	s:baton("j", "-", { { x = 0, y = 6 } })                              -- a miss counts none
	s:baton("j", "Z")
	s:note("a note")
	expect.eq(notation.turnLine(s.turns[3]),
		"3. j:2I (@ 2.50,6.00 1.32,7.25) 1A j:2F (@ 2.50,6.00 1.32,7.25) j:- j:Z # a note")
	expect.eq(notation.batonCount("2FB"), 3); expect.eq(notation.batonCount("FE"), 1)
	expect.eq(notation.batonCount("K"), 0); expect.eq(notation.batonCount("="), 0)
end)

test("positions: each kubb on the token of the player who threw it, in the order of its last throw", function()
	local g = toTurn3(newGame { { name = "Jamie" }, { name = "Kim" } })
	g:toss(land(0, 8.4, 0), "jamie")     -- a1 over the baseline: rethrown
	g:toss(land(1, 6, "stand"), "kim")   -- a2 in, standing
	g:toss(land(-1, 7, "stand"), "kim")  -- a1 rethrown by kim
	expect.eq(g.phase, "batons")
	expect.eq(line(g), "3. jamie:I kim:IR (@ 3.50,6.00 1.50,7.00)")
end)

test("positions: a game that ends mid-inkast writes none for it", function()
	-- a kubb that topples the king: E, every due kubb counted, no raising, no positions
	local g = toTurn3(newGame())
	g:toss(land(0, 6, "stand"))
	g:toss { rest = { x = 0.2, y = 4.1, standing = false, angle = 0 }, moved = {}, kingToppled = true }
	expect.eq(g.phase, "over")
	expect.eq(line(g), "3. jamie:2IE X X X X X X # king toppled by a thrown kubb")
	-- a resign before the inkast is done: none either
	g = toTurn3(newGame())
	g:toss(land(0, 6, "stand"))
	g:resign("A")
	expect.eq(line(g), "3. jamie:2I jamie:G X X X X X X # resigned during the inkast")
end)

test("positions: a baton's are its knocked kubbs where they stood; an early base kubb and the king have none", function()
	local g = toTurn3(newGame())
	g:toss(land(0, 6, "stand")); g:toss(land(1, 6, "stand"))
	-- a1 and the base kubb b1 (raised again, II.B.4a): F with a1's place only
	batons(g, { topple("a1", "b1"), topple("a2", "b2") })
	expect.eq(line(g), "3. jamie:2I (@ 2.50,6.00 3.50,6.00) jamie:F (@ 2.50,6.00) jamie:FB (@ 3.50,6.00 1.50,8.00)"
		.. " # b1 toppled a base kubb early; raised (II.B.4a)")
end)

-- A saved match as JSON would give it back.
local function roundTrip(m)
	return save.unpack(save.plain(save.plain(save.pack(m, nil))))
end

test("positions: a save keeps them, and a save from before positions still loads", function()
	local g = toTurn3(newGame())
	g:toss(land(0, 6, "stand")); g:toss(land(1, 6, "stand"))
	batons(g, { topple("a1") })
	local want = line(g)
	local back = roundTrip { game = g, start = {}, mode = "Pass and Play", turn = g.turn, tossed = 2 }
	expect.eq(line(back.game), want, "positions round-trip")
	back.game:throwBaton(topple("a2"))
	expect.eq(line(back.game), want .. " jamie:F (@ 3.50,6.00)", "and the game plays on with them")

	-- before positions: no inkastAt, no baton at, no inkBy or tossSeq on kubbs
	local function strip(t)
		if type(t) ~= "table" then return end
		t.inkastAt, t.at, t.inkBy, t.tossSeq = nil, nil, nil, nil
		for _, v in pairs(t) do strip(v) end
	end
	g = toTurn3(newGame())
	g:toss(land(0, 6, "stand"))                         -- mid-inkast when saved
	local d = save.plain(save.pack({ game = g, start = {}, turn = g.turn, tossed = 1 }, nil))
	strip(d)
	local old = save.unpack(d)
	expect.truthy(old, "an old save unpacks")
	expect.eq(line(old.game), "3. jamie:I")
	old.game:toss(land(1, 6, "stand"))
	-- its one inkaster gets both; the kubb thrown before the save has no
	-- throw order and comes first
	expect.eq(line(old.game), "3. jamie:2I (@ 2.50,6.00 3.50,6.00)")
end)

-- An inkast's kubbs stand raised or placed in the half they were thrown at.
-- A baton's stood where they were before it, which is on the pitch but not
-- always in their half: an earlier baton can push a kubb over the centre
-- line without toppling it (II.B.7 keeps it where it came to rest).
test("positions: in 60 random games every one is on the pitch (an inkast's in the half thrown at), within its token's count", function()
	local written = { inkast = 0, baton = 0 }
	for seed = 1, 60 do
		local g = thrower.playGame(seed)
		for _, t in ipairs(g.sheet.turns) do
			local def = t.side == "A" and "B" or "A"
			local function check(at, most, what, inHalf)
				if not at then return 0 end
				if #at > most then error(("seed %d turn %d: %d positions for %s"):format(seed, t.n, #at, what)) end
				for _, p in ipairs(at) do
					if not (inHalf and pitch.inHalf(def, p.x, p.y) or not inHalf and pitch.onPitch(p.x, p.y)) then
						error(("seed %d turn %d: %s position %.2f,%.2f not in half %s"):format(seed, t.n, what, p.x, p.y, def))
					end
				end
				return #at
			end
			for _, pid in ipairs(t.inkastOrder) do
				local k = t.inkast[pid]
				local most = k.I + k.R + k.P + k.Q + math.min(k.N, 5)
				written.inkast = written.inkast + check(t.inkastAt and t.inkastAt[pid], most, pid .. " inkast", true)
			end
			for _, b in ipairs(t.batons) do
				written.baton = written.baton + check(b.at, notation.batonCount(b.token), b.token)
				if b.at then expect.eq(#b.at, notation.batonCount(b.token), "a baton writes every kubb it counts") end
			end
		end
	end
	expect.truthy(written.inkast > 500 and written.baton > 300,
		("positions written: %d inkast, %d baton"):format(written.inkast, written.baton))
end)
