-- A scripted thrower for self-tests and headless physics matches: it picks
-- a throw for a match setup (core/match) the way a player would set it with
-- the controls (where to stand, swivel, loft) plus the swing's outputs
-- (launch speed, tumble, tilt), with a seeded scatter. It does not go
-- through the crank; the throw scene's launch takes these directly. Not the
-- computer opponent (stage 5), though that can grow from it.
-- Pure Lua: no playdate.*.
--
--   local r = autothrow.rng(seed)
--   local a = autothrow.choose(setup, r)
--   -- a = { x, y, swivel, loftDeg, speed, tumbleRate, tilt, legal }
import "core/tw"
import "core/flight"
import "core/swing"

local flight, swing = tw.flight, tw.swing
local sqrt, log, cos, pi, atan, floor = math.sqrt, math.log, math.cos, math.pi, math.atan, math.floor

local autothrow = {}

autothrow.tune = {
	batonLoft = 30,          -- degrees
	batonShort = 0.15,       -- m the baton is aimed short of the target's center
	minRange = 2.0,          -- m: never stands nearer its target than this, even with the
	                         -- advantage line further up (a slow lofted baton under 2 m
	                         -- hit 2 to 7 in 40; at 2 to 3 m about half)
	batonScatter = { 0.07, 0.15 }, -- m, sd across and along the throw (with none every baton
	                         -- hits and a game never ends: every field kubb comes straight back)
	kingScatter = { 0.10, 0.20 },
	tossLoft = 40,
	-- The basket (Jamie, 2026-11-14; "basket" is the right term): real
	-- throwers put their kubbs in one of the two corners of the far half
	-- nearest the centre line, by a sideline,
	-- so a kubb that runs goes out (a rethrow) rather than somewhere bad. A
	-- turn's kubbs go to the corner that already has more field kubbs in it
	-- (either when it is a tie), so they group.
	basketX = 1.9,           -- m from the middle: just inside the sideline's middle stake
	basketY = 4.75,          -- m from the baseline (view y): just past the centre line
	basketNear = 1.5,        -- m: field kubbs within this of a basket count for it
	tossRoll = 0.35,         -- m a lobbed kubb travels after it lands (aimed short by this)
	tossScatter = { 0.25, 0.3 },
	tumble = 5.5,            -- rad/s: a clean end-over-end baton
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
-- from (x, y) at this loft, by bisection over the swing's speed range.
function autothrow.speedFor(d, loftDeg)
	local lo, hi = 0.5, swing.tune.launchMax * flight.loftBoost(loftDeg, swing.tune.launchMax) * 1.2
	for _ = 1, 40 do
		local mid = (lo + hi) / 2
		local _, ly = flight.predict(0, 0, 0, loftDeg, mid)
		if ly < d then lo = mid else hi = mid end
	end
	return (lo + hi) / 2
end

local function aimAt(a, px, py, tx, ty, loft)
	local dx, dy = tx - px, ty - py
	a.x, a.y = px, py
	a.swivel = atan(dx, dy)
	a.loftDeg = loft
	a.speed = autothrow.speedFor(sqrt(dx * dx + dy * dy), loft)
	return a
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

-- A throw for match setup `s` (view frame). Batons: stand in line with the
-- first target (as far forward as allowed) and throw at it; the king from
-- the baseline. Tosses: the basket (autothrow.basket).
-- scale (default 1) multiplies every scatter: below 1 a steadier thrower.
function autothrow.choose(s, r, scale)
	scale = scale or 1
	local t = autothrow.tune
	local a = { tumbleRate = t.tumble, tilt = 0, legal = true }
	if s.kind == "toss" then
		local side = autothrow.basket(s, r)
		local tx = side * t.basketX + r.normal(t.tossScatter[1] * scale)
		local ty = s.lineY + t.basketY + r.normal(t.tossScatter[2] * scale) - t.tossRoll
		return aimAt(a, 0, s.lineY, tx, ty, t.tossLoft)
	end
	local pos = {}
	for _, p in ipairs(s.pieces) do pos[p.id] = p end
	local target = pos[s.targets[1]]
	-- the nearest target to the line
	for _, id in ipairs(s.targets) do
		local p = pos[id]
		if p and p.y < target.y then target = p end
	end
	local sc = s.kingShot and t.kingScatter or t.batonScatter
	local px = target.x
	if px > 2.4 then px = 2.4 elseif px < -2.4 then px = -2.4 end
	local py = s.forwardY or s.lineY
	if py > target.y - t.minRange then py = target.y - t.minRange end
	if py < s.lineY then py = s.lineY end
	local tx = target.x + r.normal(sc[1] * scale)
	local ty = target.y - t.batonShort + r.normal(sc[2] * scale)
	return aimAt(a, px, py, tx, ty, t.batonLoft)
end

tw.autothrow = autothrow
