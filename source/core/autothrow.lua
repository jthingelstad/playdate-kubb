-- The computer thrower (DESIGN.md section 4: "the computer throws the same
-- way: it plans a target and an arc and makes a swing with mistakes in it").
-- For a match setup (core/match) it does what a player does: picks a target,
-- stands behind it (tw.plan.stance), takes the default arc (tw.plan.arcFor),
-- solves the plan at a throw level (tw.plan.solve), then makes a synthetic
-- swing (the fields core/swing measures at a release) with seeded mistakes
-- in it, and tw.plan.launch turns that swing into the launch. Self-tests,
-- headless physics matches (tools/physmatch.lua) and the Playdate opponent
-- use it. Pure Lua: no playdate.*.
--
--   local r = autothrow.rng(seed)
--   local a = autothrow.choose(setup, r [, scale [, level]])
--   -- a = { x, y, swivel, loftDeg, speed, tumbleRate, tilt, legal,
--   --       plan  = the solve (tx, ty, back, release, powerLo/Hi, releaseLo/Hi, ...),
--   --       swing = the synthetic swing (back, releaseAngle, flickDps, flickFrac,
--   --               smoothness, shake, pull, how),
--   --       launch = tw.plan.launch's table (verdicts powerV, releaseV, steady),
--   --       drill = for a kubb: { markerX, markerY (from lineY), noseDown, rollLand,
--   --               spin, wobble, digGain } (world.launchDrill's arguments) }
--   autothrow.launch(w, s, a)  -- puts the throw into world w (core/world)
import "core/tw"
import "core/flight"
import "core/swing"
import "core/throwplan"
import "core/world"

local flight, swing, plan, world = tw.flight, tw.swing, tw.plan, tw.world
local sqrt, log, cos, pi, floor = math.sqrt, math.log, math.cos, math.pi, math.floor

local autothrow = {}

autothrow.tune = {
	level = "club",          -- the throw level it solves at (tw.plan.levels) when none is given
	batonShort = 0,          -- m the baton's target is short of the kubb's center: none, the
	                         -- center, where a player's target snaps (measured 2026-11-15 with
	                         -- the plan's arcs: a clean baton landing up to 0.2 m past the
	                         -- center hits most often at 2 to 8 m; aimed 0.15 short, a 2 m
	                         -- baton at a field kubb hit a quarter of the time)
	minRange = 2.0,          -- m: never stands nearer its target than this, even with the
	                         -- advantage line further up (a slow lofted baton under 2 m
	                         -- hit 2 to 7 in 40; at 2 to 3 m about half)
	halfWidth = 2.4,         -- m: the stance stays inside the throwing line's ends (the stakes)
	-- The basket (Jamie, 2026-11-14; "basket" is the right term): real
	-- throwers put their kubbs in one of the two corners of the far half
	-- nearest the centre line, by a sideline,
	-- so a kubb that runs goes out (a rethrow) rather than somewhere bad. A
	-- turn's kubbs go to the corner that already has more field kubbs in it
	-- (either when it is a tie), so they group. The kubb is drilled to rest there.
	basketX = 1.9,           -- m from the middle: just inside the sideline's middle stake
	basketY = 4.75,          -- m from the baseline (view y): just past the centre line
	basketNear = 1.5,        -- m: field kubbs within this of a basket count for it
	-- The synthetic swing: the mistakes, each multiplied by choose's scale.
	-- With none every baton hits and a game never ends (every toppled field
	-- kubb comes straight back).
	backSd = 5,              -- degrees sd of the backswing about the power target's center
	releaseSd = 9,           -- degrees sd of where the crank stops about the release target's center
	flickDps = { 1050, 1400 }, -- deg/s: a strong flick (swing.tune.fullFlickDps and over: all the power)
	softChance = 0.05,       -- chance the flick is not quite full ...
	softDps = { 850, 1000 }, -- ... and then this fast (flickFrac 0.85 to 1: short)
	shakeMax = 0.44,         -- a steady swing's shake is even between 0 and this (the shake is
	                         -- the only sideways error, as for a player: tw.plan.launch pulls
	                         -- the swivel and tilts the baton by it; a half-normal's tail made
	                         -- too many helicopters for the sideways spread)
	shakyChance = 0.015,     -- chance of a shaky swing ...
	shaky = { 0.25, 0.6 },   -- ... with this much shake (over about 0.44 a baton is a helicopter at club)
}

-- Park-Miller with a scrambled seed (as tools/thrower.lua).
function autothrow.rng(seed)
	local h = floor(seed) & 0xffffffff
	h = ((h ~ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h = ((h ~ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h = h ~ (h >> 16)
	local s = h % 2147483647
	if s <= 0 then s = s + 2147483646 end
	local r = {}
	function r.next()
		s = (s * 48271) % 2147483647
		return (s - 1) / 2147483646
	end
	for _ = 1, 8 do r.next() end
	function r.uniform(a, b) return a + (b - a) * r.next() end
	function r.normal(sd)
		local u1 = r.next()
		if u1 < 1e-12 then u1 = 1e-12 end
		return sd * sqrt(-2 * log(u1)) * cos(2 * pi * r.next())
	end
	return r
end

-- The launch speed that lands the center at distance d (along the throw)
-- from (x, y) at this loft, by bisection up to the fastest throw the plan
-- makes (the backswing's cap). Tools, tests and core/bench aim with it.
function autothrow.speedFor(d, loftDeg)
	local lo, hi = 0.5, plan.speedFor(swing.tune.backswingMaxDeg)
	for _ = 1, 40 do
		local mid = (lo + hi) / 2
		local _, ly = flight.predict(0, 0, 0, loftDeg, mid)
		if ly < d then lo = mid else hi = mid end
	end
	return (lo + hi) / 2
end

-- Which basket a toss goes to: -1 (left, view frame) or 1 (right), the one
-- with more field kubbs of the far half within basketNear of it.
function autothrow.basket(s, r)
	local t = autothrow.tune
	local left, right = 0, 0
	local ky = s.lineY + t.basketY
	local near2 = t.basketNear * t.basketNear
	for _, p in ipairs(s.pieces) do
		if p.role == "field" and p.half ~= s.side then
			local dy = p.y - ky
			local dl, dr = p.x + t.basketX, p.x - t.basketX
			if dl * dl + dy * dy < near2 then left = left + 1 end
			if dr * dr + dy * dy < near2 then right = right + 1 end
		end
	end
	if left > right then return -1 elseif right > left then return 1 end
	return (r.next() < 0.5) and -1 or 1
end

-- The swing a thrower makes at solution sol, with seeded mistakes scaled by
-- scale (0: the clean swing, every field on its target). Always draws the
-- same number of values from r. Fills and returns out: core/swing's result
-- fields (back, releaseAngle, flickDps, flickFrac, smoothness, shake, pull,
-- how = "stopped").
function autothrow.swing(sol, r, scale, out)
	local t, st = autothrow.tune, swing.tune
	out = out or {}
	local back = sol.back + r.normal(t.backSd) * scale
	if back > st.backswingMaxDeg then back = st.backswingMaxDeg end
	out.back = back
	local rel = sol.release + r.normal(t.releaseSd) * scale
	if rel < 1 then rel = 1 elseif rel > st.skyDeg - 1 then rel = st.skyDeg - 1 end
	out.releaseAngle = rel
	-- the flick: strong, now and then not quite
	local soft = r.next() < t.softChance * scale
	local u = r.next()
	local dps
	if soft then dps = t.softDps[1] + (t.softDps[2] - t.softDps[1]) * u
	else dps = t.flickDps[1] + (t.flickDps[2] - t.flickDps[1]) * u end
	if scale <= 0 then dps = st.fullFlickDps end
	local f = (dps - st.swingStartDps) / (st.fullFlickDps - st.swingStartDps)
	if f < 0 then f = 0 elseif f > 1 then f = 1 end
	out.flickDps = dps
	out.flickFrac = st.minFlickFrac + (1 - st.minFlickFrac) * f
	-- the steadiness: mostly steady, now and then shaky
	local shaky = r.next() < t.shakyChance * scale
	local u2 = r.next()
	local shake = t.shakeMax * r.next() * scale
	if shaky then shake = t.shaky[1] + (t.shaky[2] - t.shaky[1]) * u2 end
	if shake > 1 then shake = 1 end
	out.shake, out.smoothness = shake, 1 - shake
	out.pull = (r.next() < 0.5) and -1 or 1
	out.how = "stopped"
	return out
end

-- A throw for match setup `s` (view frame). Batons: target the nearest
-- live target and stand behind it as far forward as allowed (never nearer
-- than minRange); the king from the baseline. Kubbs: drilled to the basket
-- (autothrow.basket) from the baseline. scale (default 1) multiplies every
-- mistake: below 1 a steadier thrower. level: a tw.plan level (default
-- tune.level).
function autothrow.choose(s, r, scale, level)
	scale = scale or 1
	local t = autothrow.tune
	local q = { level = level or t.level }
	local tx, ty, py, arc
	if s.kind == "toss" then
		local side = autothrow.basket(s, r)
		tx, ty = side * t.basketX, s.lineY + t.basketY
		q.projectile, arc = "kubb", plan.arcFor("drill")
		py = s.lineY
	else
		local pos = {}
		for _, p in ipairs(s.pieces) do pos[p.id] = p end
		local target = pos[s.targets[1]]
		-- the nearest target to the line
		for _, id in ipairs(s.targets) do
			local p = pos[id]
			if p and p.y < target.y then target = p end
		end
		tx, ty = target.x, target.y - t.batonShort
		q.projectile = "baton"
		if s.kingShot or target.role == "king" then arc = plan.arcFor("king")
		elseif target.role == "field" then arc = plan.arcFor("field")
		else arc = plan.arcFor("base") end
		py = s.kingShot and s.lineY or (s.forwardY or s.lineY)
		if py > target.y - t.minRange then py = target.y - t.minRange end
		if py < s.lineY then py = s.lineY end
	end
	local st = plan.stance(tx, ty, s.lineY, py, t.halfWidth, {})
	q.px, q.py, q.tx, q.ty, q.release = st.x, st.y, tx, ty, arc
	local sol = plan.solve(q, {})
	local sw = autothrow.swing(sol, r, scale, {})
	local L = plan.launch(sol, sw, { projectile = q.projectile, tilt = 0, spin = 0 }, {})
	local a = { x = st.x, y = st.y, swivel = L.swivel, loftDeg = L.loft, speed = L.speed,
		tumbleRate = L.tumble, tilt = L.tilt, legal = L.legal, plan = sol, swing = sw, launch = L }
	if q.projectile == "kubb" then
		a.drill = { markerX = tx, markerY = ty - s.lineY, noseDown = L.noseDown, rollLand = L.rollLand,
			spin = L.spin, wobble = L.wobble, digGain = L.digGain }
	end
	return a
end

-- Put throw a (autothrow.choose) for setup s into world w: a drilled kubb
-- (world.launchDrill, kubb s.kubb) or a baton (world.launchBaton, the turn's
-- baton id s.batonId). Returns the body.
function autothrow.launch(w, s, a)
	local d = a.drill
	if d then
		return world.launchDrill(w, s.kubb, a.x, a.y, a.swivel, a.loftDeg, a.speed, d.noseDown, d.rollLand,
			d.spin, d.wobble, d.digGain)
	end
	return world.launchBaton(w, a.x, a.y, a.swivel, a.loftDeg, a.speed, a.tumbleRate, a.tilt, s.batonId)
end

tw.autothrow = autothrow
