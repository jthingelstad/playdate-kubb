-- Debris within a turn (core/debris through core/match): the batons thrown
-- and the kubbs they knocked down stay lying where they came to rest until
-- the turn is over, as bodies in the next throw's physics world. Made-up
-- results pin the carrying; the physics cases run core/world.
import "core/match"
import "core/debris"
import "core/outcome"
import "core/world"
import "core/frame"
local match, debris, outcome, world, frame = tw.match, tw.debris, tw.outcome, tw.world, tw.frame

local pi = math.pi

local function still(s)
	local r = { touched = {}, toppled = {}, kingToppled = false, bodies = {} }
	for _, p in ipairs(match.worldPieces(s)) do
		r.bodies[p.id] = { kind = p.kind, x = p.x, y = p.y, z = p.z or (p.toppled and 0.035 or 0.075),
			qw = p.qw, qx = p.qx, qy = p.qy, qz = p.qz, toppled = p.toppled }
	end
	return r
end

-- Put body `id` of `kind` lying at view (x, y) along `angle`.
local function lay(r, id, kind, x, y, angle)
	local qw, qx, qy, qz = outcome.quatOf { standing = false, angle = angle or 0 }
	r.bodies[id] = { kind = kind, x = x, y = y, z = kind == "baton" and 0.022 or 0.035,
		qw = qw, qx = qx, qy = qy, qz = qz, toppled = true }
end

local function topple(r, id, x, y, angle)
	lay(r, id, "kubb", x, y, angle)
	r.toppled[#r.toppled + 1] = id
	r.touched[#r.touched + 1] = id
end

local function find(list, id)
	for _, p in ipairs(list) do if p.id == id then return p end end
	return nil
end

-- The last baton token of turn `turn` (default: the current turn).
local function token(m, turn)
	local t = m.game.sheet.turns[turn or m.game.turn]
	return t.batons[#t.batons].token
end

-- A baton lying across the pitch sliding along +y at `speed` from view (x, y).
local function slide(w, id, x, y, speed)
	local qw, qx, qy, qz = outcome.quatOf { standing = false, angle = 0 }
	return world.launch(w, "baton", id, x, y, 0.03, qw, qx, qy, qz, 0, speed, 0, 0, 0, 0)
end

-- Turn 1, Team A's first baton: it topples b1, which falls to view (-1, 7.88),
-- and the baton comes to rest at (1, 6).
local function firstBaton(m, b1x, b1y)
	local s = match.setup(m)
	expect.eq(s.kind, "baton")
	expect.eq(s.batonId, "baton1")
	expect.eq(#s.debris, 0, "no debris before the first throw")
	local r = still(s)
	topple(r, "b1", b1x or -1, b1y or 7.88, 0)
	lay(r, "baton1", "baton", 1, 6, pi / 2)
	match.resolve(m, r, false)
	expect.eq(m.text, "base kubb down")
end

test("debris: a toppled kubb and the thrown baton lie on the pitch for the next throw", function()
	local m = match.new {}
	firstBaton(m)
	local s = match.setup(m)
	expect.eq(s.batonId, "baton2")
	expect.eq(#s.debris, 2)
	local b1, bt = find(s.debris, "b1"), find(s.debris, "baton1")
	expect.truthy(b1 and bt, "b1 and baton1 in the debris")
	expect.near(b1.x, -1, 1e-9); expect.near(b1.y, 7.88, 1e-9); expect.near(b1.z, 0.035, 1e-9)
	expect.eq(b1.kind, "kubb"); expect.eq(bt.kind, "baton")
	expect.truthy(b1.toppled and bt.toppled, "debris is down")
	-- b1 is in B's hand, not one of the engine's pieces
	expect.eq(find(s.pieces, "b1"), nil)
	expect.eq(m.game.kubbs.b1.where, "hand")
	-- and it is a body of the next world, already down and asleep
	local w = world.new { surface = "grass", pieces = match.worldPieces(s) }
	local b = w.byId.b1
	expect.truthy(b and b.toppled and b.wasToppled and not b.awake, "b1 body down and asleep")
	expect.truthy(w.byId.baton1 and not w.byId.baton1.awake, "baton1 body asleep")
end)

test("debris: moves when struck, and a downed kubb hit again adds nothing", function()
	local m = match.new {}
	firstBaton(m, -1.5, 6)
	local s = match.setup(m)
	local w = world.new { surface = "grass", pieces = match.worldPieces(s) }
	slide(w, s.batonId, -1.5, 5.6, 5)
	world.run(w)
	local res = world.result(w)
	expect.eq(#res.toppled, 0, "nothing toppled")
	local rb = res.bodies.b1
	expect.truthy(rb.y > 6.05, "b1 was pushed up the pitch")
	match.resolve(m, res, false)
	expect.eq(token(m, 1), "-")
	-- turn 1 has two batons: the turn is over, so check the carry directly
	-- on a turn with more (below); here the hand-off clears it
	expect.eq(#m.debris.list, 0)
	-- the same throw in turn 2 (four batons): b1 moves and stays debris
	m = match.new {}
	match.setup(m); match.resolve(m, still(m.setup), false)
	match.setup(m); match.resolve(m, still(m.setup), false)
	s = match.setup(m)
	expect.eq(s.side, "B")
	local r = still(s)
	topple(r, "a1", -1.5, 6, 0)   -- view frame of B
	lay(r, "baton1", "baton", 1, 6, pi / 2)
	match.resolve(m, r, false)
	s = match.setup(m)
	w = world.new { surface = "grass", pieces = match.worldPieces(s) }
	slide(w, s.batonId, -1.5, 5.6, 5)
	world.run(w)
	res = world.result(w)
	expect.eq(#res.toppled, 0, "nothing toppled")
	match.resolve(m, res, false)
	expect.eq(token(m), "-")
	s = match.setup(m)
	local a1 = find(s.debris, "a1")
	expect.near(a1.x, res.bodies.a1.x, 1e-9)
	expect.near(a1.y, res.bodies.a1.y, 1e-9)
	expect.truthy(a1.y > 6.05, "a1 lies where the baton pushed it")
	expect.truthy(find(s.debris, "baton2"), "the second baton lies there too")
	expect.eq(#s.debris, 3)
end)

test("debris: a standing kubb toppled by pushed debris counts for this throw", function()
	local m = match.new {}
	-- b1 lies across, 12 cm in front of b2 (x = -1, y = 8)
	firstBaton(m, -1, 7.88)
	local s = match.setup(m)
	local w = world.new { surface = "grass", pieces = match.worldPieces(s) }
	-- (7.9 m/s: the middle of the speeds, 7.8 to 8.05, at which this push
	-- topples b2; the air's drag, 2026-11-16, left 8 at the edge)
	slide(w, s.batonId, -1, 7.58, 7.9)
	world.run(w)
	local res = world.result(w)
	expect.eq(#res.toppled, 1)
	expect.eq(res.toppled[1], "b2")
	expect.truthy(res.bodies.b1.touched, "b1 was struck")
	local o = match.resolve(m, res, false)
	expect.eq(o.toppled[1], "b2")
	expect.eq(token(m, 1), "B")
	expect.eq(m.game.kubbs.b2.where, "hand")
end)

test("debris: gone after the turn; the pitch is the engine's again", function()
	local m = match.new {}
	firstBaton(m)
	local s = match.setup(m)
	expect.eq(#s.debris, 2)
	match.resolve(m, still(s), false)
	-- turn 2: B's first throw is a toss (b1 was knocked down)
	s = match.setup(m)
	expect.eq(s.side, "B")
	expect.eq(#s.debris, 0)
	expect.eq(#m.debris.list, 0)
end)

test("debris: Team B's view round trip", function()
	local m = match.new {}
	match.setup(m); match.resolve(m, still(m.setup), false)
	match.setup(m); match.resolve(m, still(m.setup), false)
	local s = match.setup(m)
	expect.eq(s.side, "B")
	local r = still(s)
	-- view frame of B: a2 (world (-1, 0)) is at view (1, 8)
	topple(r, "a2", 1.1, 7.8, 0.4)
	lay(r, "baton1", "baton", -0.5, 6.5, 1.2)
	match.resolve(m, r, false)
	-- stored in the world frame
	local e = m.debris.list[1]
	expect.eq(e.id, "a2")
	expect.near(e.x, -1.1, 1e-9); expect.near(e.y, 0.2, 1e-9)
	s = match.setup(m)
	expect.eq(s.side, "B")
	for _, id in ipairs { "a2", "baton1" } do
		local p, rb = find(s.debris, id), r.bodies[id]
		expect.near(p.x, rb.x, 1e-9, id .. " x"); expect.near(p.y, rb.y, 1e-9, id .. " y")
		-- the same orientation (q or -q)
		local d = p.qw * rb.qw + p.qx * rb.qx + p.qy * rb.qy + p.qz * rb.qz
		expect.near(math.abs(d), 1, 1e-9, id .. " orientation")
	end
	-- and Team A would see it turned: the world pose
	local v = debris.pieces(m.debris, "A")
	expect.near(v[1].x, -1.1, 1e-9); expect.near(v[1].y, 0.2, 1e-9)
end)

test("debris: a throw put back (Z) leaves the earlier debris where it was", function()
	local m = match.new {}
	match.setup(m); match.resolve(m, still(m.setup), false)
	match.setup(m); match.resolve(m, still(m.setup), false)
	local s = match.setup(m)
	local r = still(s)
	topple(r, "a1", -1.5, 6, 0)
	lay(r, "baton1", "baton", 1, 6, pi / 2)
	match.resolve(m, r, false)
	s = match.setup(m)
	r = still(s)
	lay(r, "a1", "kubb", -1.2, 6.4, 0.3)   -- struck by a helicopter
	lay(r, "baton2", "baton", -1, 6.3, 0)
	match.resolve(m, r, true)
	expect.eq(token(m), "Z")
	s = match.setup(m)
	local a1 = find(s.debris, "a1")
	expect.near(a1.x, -1.5, 1e-9); expect.near(a1.y, 6, 1e-9)
	expect.truthy(find(s.debris, "baton2"), "the illegal baton still lies there")
end)

test("debris: tossed kubbs keep their exact rest pose until raised", function()
	local m = match.new {}
	match.setup(m); match.resolve(m, still(m.setup), false)
	match.setup(m); match.resolve(m, still(m.setup), false)
	for i = 1, 4 do
		local s = match.setup(m)
		local r = still(s)
		if i <= 2 then topple(r, "a" .. i, -1 + i * 0.5, 7.9, 0) end
		match.resolve(m, r, false)
	end
	local s = match.setup(m)
	expect.eq(s.kind, "toss")
	expect.eq(#s.debris, 0)
	local r = still(s)
	-- a1 lands tilted (leaning on its edge a little) at (-0.6, 6)
	local qw, qx, qy, qz = outcome.quatOf { standing = false, angle = 0.3 }
	local tw_, tx, ty, tz = tw.quat.fromAxisAngle(1, 0, 0, 0.2)
	qw, qx, qy, qz = tw.quat.mul(tw_, tx, ty, tz, qw, qx, qy, qz)
	r.bodies[s.kubb] = { kind = "kubb", x = -0.6, y = 6, z = 0.045, qw = qw, qx = qx, qy = qy, qz = qz, toppled = true }
	match.resolve(m, r, false)
	expect.eq(m.text, "kubb in for now")
	s = match.setup(m)
	expect.eq(s.kind, "toss")
	local p = find(s.pieces, "a1")
	expect.near(p.x, -0.6, 1e-9); expect.near(p.y, 6, 1e-9); expect.near(p.z, 0.045, 1e-9)
	local d = p.qw * qw + p.qx * qx + p.qy * qy + p.qz * qz
	expect.near(math.abs(d), 1, 1e-9, "the exact orientation")
	-- the next toss lands elsewhere: a1 keeps its pose
	r = still(s)
	lay(r, s.kubb, "kubb", 0.8, 6.2, 0)
	match.resolve(m, r, false)
	-- raised: batons now, the pitch is the engine's (standing field kubbs)
	s = match.setup(m)
	expect.eq(s.kind, "baton")
	local a1 = find(s.pieces, "a1")
	expect.eq(a1.toppled, false)
	expect.eq(a1.z, nil)
end)
