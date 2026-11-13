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
	batonScatter = { 0.07, 0.15 }, -- m, sd across and along the throw (with none every baton
	                         -- hits and a game never ends: every field kubb comes straight back)
	kingScatter = { 0.10, 0.20 },
	tossLoft = 40,
	tossSpot = { 4.8, 6.2 }, -- m from the baseline: where tossed kubbs are aimed (view y)
	tossX = 1.6,             -- m either side of the middle
	kingClear = 0.5,         -- m; tosses are not aimed closer to the middle than this
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
	local lo, hi = 0.5, swing.tune.launchMax * 1.2
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

-- A throw for match setup `s` (view frame). Batons: stand in line with the
-- first target (as far forward as allowed) and throw at it; the king from
-- the baseline. Tosses: a random spot in the far half.
function autothrow.choose(s, r)
	local t = autothrow.tune
	local a = { tumbleRate = t.tumble, tilt = 0, legal = true }
	if s.kind == "toss" then
		local tx = r.uniform(-t.tossX, t.tossX)
		local ty = r.uniform(t.tossSpot[1], t.tossSpot[2])
		-- keep clear of the king (a toss that topples it loses the game)
		if tx > -t.kingClear and tx < t.kingClear then tx = (tx < 0) and -t.kingClear or t.kingClear end
		tx, ty = tx + r.normal(t.tossScatter[1]), ty + r.normal(t.tossScatter[2]) - t.tossRoll
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
	local tx = target.x + r.normal(sc[1])
	local ty = target.y - t.batonShort + r.normal(sc[2])
	return aimAt(a, px, py, tx, ty, t.batonLoft)
end

tw.autothrow = autothrow
