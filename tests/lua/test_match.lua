-- The match path: the view frame (core/frame), physics results to outcome
-- records (core/outcome), the match driver (core/match) and the scripted
-- thrower (core/autothrow). Most cases feed a made-up tw.world result so
-- each rule case is exact; the last ones run real physics.
import "core/frame"
import "core/outcome"
import "core/match"
import "core/autothrow"
import "core/world"
import "core/notation"
local frame, outcome, match, autothrow, world, notation =
	tw.frame, tw.outcome, tw.match, tw.autothrow, tw.world, tw.notation

local pi = math.pi

-- A result where nothing moved: every piece's body where it started.
local function still(pieces)
	local r = { touched = {}, toppled = {}, kingToppled = false, bodies = {} }
	for _, p in ipairs(pieces) do
		r.bodies[p.id] = { kind = p.kind, x = p.x, y = p.y, z = p.toppled and 0.035 or 0.075,
			qw = p.qw, qx = p.qx, qy = p.qy, qz = p.qz, toppled = p.toppled }
	end
	return r
end

-- Put body `id` at a view-frame pose (and mark it touched).
local function place(r, id, pose, z)
	local qw, qx, qy, qz = outcome.quatOf(pose)
	r.bodies[id] = { kind = "kubb", x = pose.x, y = pose.y, z = z or (pose.standing and 0.075 or 0.035),
		qw = qw, qx = qx, qy = qy, qz = qz, toppled = not pose.standing }
	r.touched[#r.touched + 1] = id
end

-- Topple body `id` where it stands (lying along +y).
local function topple(r, id)
	local b = r.bodies[id]
	place(r, id, { x = b.x, y = b.y + 0.1, standing = false, angle = pi / 2 })
	r.toppled[#r.toppled + 1] = id
	if id == "king" then r.kingToppled = true end
end

local function byId(s)
	local m = {}
	for _, p in ipairs(s.pieces) do m[p.id] = p end
	return m
end

-- The next throw, which must be of `kind`.
local function setup(m, kind)
	local s = match.setup(m)
	expect.truthy(s, "a throw to set up")
	expect.eq(s.kind, kind, "throw kind")
	return s
end

local function miss(m) local s = setup(m, "baton"); match.resolve(m, still(s.pieces), false) end
local function lastToken(m)
	local t = m.game.sheet.turns[m.game.turn]
	local b = t.batons[#t.batons]
	return b and b.token
end

-- A tosses its kubb to view (x, y), lying across the pitch.
local function tossTo(m, x, y)
	local s = setup(m, "toss")
	local r = still(s.pieces)
	place(r, s.kubb, { x = x, y = y, standing = false, angle = 0 })
	match.resolve(m, r, false)
	return s
end

-- Turn 1 A misses twice; turn 2 B topples a1 and a2 and misses twice; turn 3
-- A tosses a1 and a2 to (-0.8, 6) and (0.8, 6.2) in B's half (both in) and
-- the next throw is A's first baton at two standing field kubbs.
local function toFieldKubbs()
	local m = match.new { start = { year = 2026, month = 11, day = 20, hour = 9, min = 0 } }
	miss(m); miss(m)
	for i = 1, 4 do
		local s = setup(m, "baton")
		expect.eq(s.side, "B")
		local r = still(s.pieces)
		if i <= 2 then topple(r, "a" .. i) end
		match.resolve(m, r, false)
	end
	expect.eq(m.game.turn, 3)
	tossTo(m, -0.8, 6)
	expect.eq(m.text, "kubb in")
	tossTo(m, 0.8, 6.2)
	return m
end

-- ---------- frame ----------

test("frame: B view is the pitch turned 180 degrees, its own inverse", function()
	local x, y = frame.point("B", 1.5, 2)
	expect.near(x, -1.5); expect.near(y, 6)
	x, y = frame.point("B", x, y)
	expect.near(x, 1.5); expect.near(y, 2)
	x, y = frame.point("A", 1.5, 2)
	expect.near(x, 1.5); expect.near(y, 2)
	expect.near(frame.y("B", 1), 7)
	expect.near(frame.angle("B", 0.3), 0.3 - pi)
	expect.near(frame.angle("B", frame.angle("B", 0.3)), 0.3, 1e-12)
end)

test("frame: the quaternion turn matches the pose turn", function()
	for _, pose in ipairs { { x = 1, y = 2, standing = false, angle = 0.4 }, { x = -1, y = 7, standing = true, angle = -1.1 },
		{ x = 0, y = 5, standing = false, angle = 2.9 } } do
		local qw, qx, qy, qz = outcome.quatOf(pose)
		local bw, bx, by, bz = frame.quat("B", qw, qx, qy, qz)
		local vx, vy = frame.point("B", pose.x, pose.y)
		local back = outcome.poseOf(vx, vy, 0, bw, bx, by, bz)
		local want = frame.pose("B", pose)
		expect.eq(back.standing, want.standing)
		-- a standing kubb's yaw is only defined modulo a quarter turn; lying modulo nothing
		local d = back.angle - want.angle
		local period = pose.standing and pi / 2 or 2 * pi
		d = (d + period / 2) % period - period / 2
		expect.near(d, 0, 1e-9, "angle")
		-- and back again
		local aw, ax, ay, az = frame.quat("B", bw, bx, by, bz)
		local dot = math.abs(aw * qw + ax * qx + ay * qy + az * qz)
		expect.near(dot, 1, 1e-12, "round trip")
	end
end)

test("outcome: pose <-> quaternion round trip, standing and lying", function()
	for _, a in ipairs { -2.5, -0.3, 0, 1.2, 3.0 } do
		local p = outcome.poseOf(0, 0, 0, outcome.quatOf { standing = false, angle = a })
		expect.eq(p.standing, false)
		expect.near(p.angle, a, 1e-9)
		p = outcome.poseOf(0, 0, 0, outcome.quatOf { standing = true, angle = a * 0.2 })
		expect.eq(p.standing, true)
		expect.near(p.angle, a * 0.2, 1e-9)
	end
end)

-- ---------- the B mirror round trip ----------

test("match: Team B's view puts A's base kubbs at its far end, and its throws come back to world", function()
	local m = match.new {}
	miss(m); miss(m)
	local s = setup(m, "baton")
	expect.eq(s.side, "B")
	local p = byId(s)
	-- a1 stands at world y = 0, x = -2 (core/pitch); B sees it at y = 8, x = +2
	local a1 = m.game.kubbs.a1.pose
	expect.near(p.a1.x, -a1.x); expect.near(p.a1.y, 8 - a1.y)
	expect.near(p.b1.y, 8 - m.game.kubbs.b1.pose.y)
	expect.eq(s.targets[1]:sub(1, 1), "a")
	-- push a3 (standing) 0.3 m further from B in its view: in the world it moves toward y < 0
	local r = still(s.pieces)
	place(r, "a3", { x = p.a3.x + 0.1, y = p.a3.y + 0.3, standing = true, angle = 0.2 })
	local o = match.resolve(m, r, false)
	expect.near(o.moved.a3.x, -(p.a3.x + 0.1), 1e-9)
	expect.near(o.moved.a3.y, 8 - (p.a3.y + 0.3), 1e-9)
	expect.eq(o.moved.a3.standing, true)
end)

-- ---------- baton outcomes ----------

test("baton: a toppled field kubb", function()
	local m = toFieldKubbs()
	local s = setup(m, "baton")
	expect.eq(s.side, "A")
	expect.eq(#s.targets, 2)
	local r = still(s.pieces)
	topple(r, "a1")
	local o = match.resolve(m, r, false)
	expect.eq(o.toppled[1], "a1")
	expect.eq(lastToken(m), "F")
	expect.eq(m.text, "field kubb down")
	expect.eq(m.game.kubbs.a1.where, "hand") -- B tosses it back next turn
end)

test("baton: a base kubb toppled while field kubbs stand is raised (II.B.4a)", function()
	local m = toFieldKubbs()
	local s = setup(m, "baton")
	local r = still(s.pieces)
	topple(r, "b2")
	match.resolve(m, r, false)
	expect.truthy(m.text:find("base kubb early: raised", 1, true), m.text)
	expect.eq(m.game.kubbs.b2.where, "pitch")
	-- it stands again for the next throw
	local s2 = setup(m, "baton")
	expect.eq(byId(s2).b2.toppled, false)
end)

test("baton: hitting a field kubb in your own half is illegal (II.B.11)", function()
	local m = toFieldKubbs()
	-- A misses all six: a1 and a2 stay standing in B's half, and B is at bat
	-- with field kubbs in its own half (it may only throw past them)
	for _ = 1, 6 do miss(m) end
	expect.eq(m.game.attacker, "B")
	local s = setup(m, "baton")
	expect.eq(s.side, "B")
	local own
	for _, q in ipairs(s.pieces) do if q.role == "field" and q.half == "B" then own = q.id end end
	expect.truthy(own, "a field kubb in B's half")
	local r = still(s.pieces)
	r.touched[#r.touched + 1] = own
	local o = match.resolve(m, r, false)
	expect.eq(o.ownHalfHit[1], own)
	expect.eq(lastToken(m), "Z")
	expect.eq(m.text, "own-half kubb hit: all put back")
end)

test("baton: a kubb pushed but standing keeps its new spot", function()
	local m = toFieldKubbs()
	local s = setup(m, "baton")
	local p = byId(s)
	local r = still(s.pieces)
	place(r, "a2", { x = p.a2.x + 0.2, y = p.a2.y + 0.15, standing = true, angle = 0.3 })
	local o = match.resolve(m, r, false)
	expect.eq(#o.toppled, 0)
	expect.eq(lastToken(m), "-")
	expect.eq(m.text, "missed")
	local k = m.game.kubbs.a2
	expect.eq(k.where, "pitch")
	expect.near(k.pose.x, p.a2.x + 0.2, 1e-9)
	expect.near(k.pose.y, p.a2.y + 0.15, 1e-9)
	expect.eq(k.pose.standing, true)
end)

test("baton: a helicopter is illegal", function()
	local m = toFieldKubbs()
	local s = setup(m, "baton")
	local r = still(s.pieces)
	topple(r, "a1")
	match.resolve(m, r, true)
	expect.eq(lastToken(m), "Z")
	expect.eq(m.text, "helicopter: illegal")
	expect.eq(m.game.kubbs.a1.where, "pitch")
end)

test("baton: the king toppled early loses; toppled after the base kubbs wins", function()
	local m = toFieldKubbs()
	local s = setup(m, "baton")
	local r = still(s.pieces)
	topple(r, "king")
	match.resolve(m, r, false)
	expect.truthy(match.over(m))
	expect.eq(m.game.winner, "B")
	expect.eq(m.text, "king down early: Team B wins")

	-- a clean game: A clears B's base kubbs on turn 1 (2 batons can't), so play on
	m = match.new {}
	local turnGuard = 0
	while not match.over(m) and turnGuard < 200 do
		turnGuard = turnGuard + 1
		local st = match.setup(m)
		if not st then break end
		local rr = still(st.pieces)
		if st.kind == "toss" then
			-- every kubb in, far from everything
			local spot = (m.tossed % 5) * 0.7 - 1.4
			place(rr, st.kubb, { x = spot, y = 6.5, standing = false, angle = 0 })
		elseif st.side == "A" then
			-- A topples whatever it aims at, B misses
			if st.kingShot then topple(rr, "king") else topple(rr, st.targets[1]) end
		end
		match.resolve(m, rr, false)
	end
	expect.truthy(match.over(m), "the game ends")
	expect.eq(m.game.winner, "A")
	expect.eq(m.game.how, "king")
	expect.eq(m.text, "king down: Team A wins")
	expect.eq(match.howText(m), "Team A toppled the king")
	local text, name = match.file(m, { year = 2026, month = 11, day = 20, hour = 9, min = 30 }, "0.0.1")
	expect.truthy(text:find('[Win "Team A"]', 1, true), "the Win tag")
	expect.truthy(text:find('[Mode "Pass and Play"]', 1, true), "the Mode tag")
	expect.eq(name, "2026-11-20-0930-team-a-v-team-b.txt")
end)

-- ---------- toss outcomes ----------

test("toss: in, out (rethrow) and out twice", function()
	local m = match.new {}
	miss(m); miss(m)
	for i = 1, 4 do
		local s = setup(m, "baton")
		local r = still(s.pieces)
		if i <= 2 then topple(r, "a" .. i) end
		match.resolve(m, r, false)
	end
	local s = setup(m, "toss")
	expect.eq(s.label, "Team A  kubb 1 of 2")
	local r = still(s.pieces)
	local first = s.kubb
	place(r, s.kubb, { x = 0.3, y = 9.0, standing = false, angle = 0 }) -- past B's baseline
	match.resolve(m, r, false)
	expect.eq(m.text, "kubb out: rethrown last")
	-- every first throw comes before the rethrows (II.C.5)
	s = setup(m, "toss")
	expect.truthy(not s.rethrow)
	-- the out kubb lies where it stopped while the other kubb is thrown
	expect.eq(#s.debris, 1, "the out kubb is on the pitch")
	expect.eq(s.debris[1].id, first)
	expect.near(s.debris[1].x, 0.3, 1e-9); expect.near(s.debris[1].y, 9.0, 1e-9)
	expect.eq(s.label, "Team A  kubb 2 of 3")
	r = still(s.pieces)
	place(r, s.kubb, { x = 1.0, y = 6.0, standing = false, angle = 0 })
	match.resolve(m, r, false)
	expect.eq(m.text, "kubb in")
	s = setup(m, "toss")
	expect.truthy(s.rethrow)
	expect.eq(s.label, "Team A  rethrow 3 of 3")
	expect.eq(s.kubb, first)
	expect.eq(#s.debris, 0, "picked up for the rethrow")
	r = still(s.pieces)
	place(r, s.kubb, { x = 3.0, y = 6.0, standing = false, angle = 0 }) -- out over the side
	match.resolve(m, r, false)
	expect.eq(m.text, "out twice: punishment kubb")
	-- the punishment kubb is placed by the defender automatically, then A bats
	local b = setup(m, "baton")
	expect.eq(m.settled and m.settled.punished, 1)
	expect.eq(b.side, "A")
	expect.eq(#b.debris, 0, "nothing waits once the kubbs are thrown")
end)

test("toss: a kubb resting on another is lowered beside it", function()
	local m = match.new {}
	miss(m); miss(m)
	for i = 1, 4 do
		local s = setup(m, "baton")
		local r = still(s.pieces)
		if i <= 2 then topple(r, "a" .. i) end
		match.resolve(m, r, false)
	end
	tossTo(m, 0.5, 6)
	local s = setup(m, "toss")
	local r = still(s.pieces)
	-- flat on top of a1 (which still lies where it landed)
	local a1 = byId(s).a1
	place(r, s.kubb, { x = a1.x + 0.03, y = a1.y + 0.02, standing = false, angle = 0.1 }, 0.105)
	local o = match.resolve(m, r, false)
	expect.eq(o.rest.onTop, "a1")
	expect.eq(o.rest.standing, false)
	expect.truthy(m.text:find("on a kubb: lowered", 1, true), m.text)
	expect.eq(m.game.kubbs.a2.where, "pitch")
	expect.truthy(not m.game.kubbs.a2.pose.onTop, "lowered")
end)

test("toss: a kubb resting on an out kubb that waits on the pitch lies where it is, not lowered", function()
	local m = match.new {}
	miss(m); miss(m)
	for i = 1, 4 do
		local s = setup(m, "baton")
		local r = still(s.pieces)
		if i <= 2 then topple(r, "a" .. i) end
		match.resolve(m, r, false)
	end
	-- the first kubb stops just short of the middle line: out, and it waits
	local s = setup(m, "toss")
	local first = s.kubb
	local r = still(s.pieces)
	place(r, first, { x = 0.5, y = 3.8, standing = false, angle = 0 })
	match.resolve(m, r, false)
	expect.eq(m.game.kubbs[first].where, "out")
	-- the second comes to rest on top of it, its center in bounds
	s = setup(m, "toss")
	expect.eq(s.debris[1].id, first)
	r = still(s.pieces)
	r.bodies[first] = { kind = "kubb", x = 0.5, y = 3.8, z = 0.035, qw = 1, qx = 0, qy = 0, qz = 0, toppled = true }
	place(r, s.kubb, { x = 0.52, y = 3.95, standing = false, angle = 0 }, 0.105)
	local second = s.kubb
	local o = match.resolve(m, r, false)
	expect.eq(o.rest.onTop, nil, "an out kubb is not a support in play")
	expect.eq(o.rest.standing, false)
	expect.truthy(not m.text:find("lowered", 1, true), m.text)
	expect.near(m.game.kubbs[second].pose.y, 3.95, 1e-9)
end)

test("toss: Team B tosses in its own view and the kubb lands in A's half", function()
	local m = match.new {}
	-- A topples b1 on turn 1
	local s = setup(m, "baton")
	local r = still(s.pieces)
	topple(r, "b1")
	match.resolve(m, r, false)
	miss(m)
	expect.eq(m.game.attacker, "B")
	s = setup(m, "toss")
	expect.eq(s.kubb, "b1")
	r = still(s.pieces)
	place(r, "b1", { x = 1.2, y = 6.0, standing = false, angle = 0 })
	match.resolve(m, r, false)
	expect.eq(m.text, "kubb in")
	local k = m.game.kubbs.b1
	expect.near(k.pose.x, -1.2, 1e-9)
	expect.near(k.pose.y, 2.0, 1e-9)
	expect.eq(k.half, "A")
end)

-- ---------- labels and the advantage line ----------

test("setup: labels and the advantage line in the thrower's view", function()
	local m = toFieldKubbs()
	local s = setup(m, "baton")
	expect.eq(s.label, "Team A  baton 1 of 6")
	expect.eq(s.n, 1); expect.eq(s.of, 6)
	expect.eq(s.targets[1]:sub(1, 1), "a")
	-- the advantage line, when there is one, is in A's view as is
	if m.game.advantageY then
		expect.near(s.advY, m.game.advantageY)
		expect.near(s.forwardY, m.game.advantageY)
	end
end)

test("resign: the team on turn gives up", function()
	local m = match.new {}
	miss(m)
	expect.truthy(match.resign(m))
	expect.truthy(match.over(m))
	expect.eq(m.game.winner, "B")
	expect.eq(m.game.how, "resigned")
	expect.eq(match.howText(m), "Team A resigned")
	local b = m.game.sheet.turns[1].batons
	expect.eq(b[2].token, "G")   -- then X for each unthrown baton
	expect.eq(lastToken(m), "X")
	expect.eq(match.resign(m), false)
end)

-- ---------- real physics ----------

local function simulate(s, a)
	local w = world.new { surface = "grass", pieces = s.pieces }
	if s.projectile == "kubb" then
		world.launchKubb(w, s.kubb, a.x, a.y, a.swivel, a.loftDeg, a.speed, a.tumbleRate)
	else
		world.launchBaton(w, a.x, a.y, a.swivel, a.loftDeg, a.speed, a.tumbleRate, a.tilt)
	end
	world.run(w)
	return world.result(w)
end

test("physics: a lobbed kubb comes to rest in the far half", function()
	local m = match.new {}
	local s = setup(m, "baton")
	local r = still(s.pieces)
	topple(r, "b1")
	match.resolve(m, r, false)
	miss(m)
	s = setup(m, "toss")
	local res = simulate(s, { x = 0, y = 0, swivel = 0.25, loftDeg = 40, speed = autothrow.speedFor(5.3, 40), tumbleRate = 5.5 })
	local b = res.bodies.b1
	expect.truthy(b, "the tossed kubb's body")
	expect.truthy(b.y > 4 and b.y < 8 and math.abs(b.x) < 2.5, string.format("rests in the far half (%.2f, %.2f)", b.x, b.y))
	match.resolve(m, res, false)
	expect.eq(m.text, "kubb in")
	expect.eq(m.game.kubbs.b1.half, "A")
end)

test("physics: a scripted match runs to a winner and renders a game file", function()
	local m = match.new { start = { year = 2026, month = 11, day = 20, hour = 9, min = 0 } }
	local r = autothrow.rng(3)
	local throws = 0
	while not match.over(m) and m.game.turn <= 40 do
		local s = match.setup(m)
		if not s then break end
		match.resolve(m, simulate(s, autothrow.choose(s, r)), false)
		throws = throws + 1
	end
	if not match.over(m) then match.resign(m) end
	expect.truthy(match.over(m))
	expect.truthy(throws > 4, "throws")
	local text = match.file(m, notation.addMinutes(m.start, 30), "0.0.1")
	expect.truthy(text:find("Pass and Play", 1, true), "mode")
	expect.truthy(text:find("Team A", 1, true), "team")
end)
