-- What scatters the drilled kubbs? (AGENTS.md "What scatters a drilled kubb";
-- Jamie approved the measuring, 2026-11-16; no game changes.) Two parts:
--
-- 1. One drill into an empty far half, the computer's own throw at the
--    basket: where it first touches the ground against its mark (the air:
--    the swing's mistakes) and how far it travels from there to rest (the
--    ground: bounce, skid and roll), with the swing's mistakes scaled and
--    the ground flat or textured.
-- 2. Every drill of physics matches (tools/physmatch's path): how far it
--    rests from its mark when it touched no other piece and when it did,
--    how far it moved the pieces it touched, and what the mark was (the
--    basket itself or a spot beside the group).
--
--   lua5.4 tools/drillscatter.lua [--n 300] [--matches 40] [--seed 2]

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end

import "core/match"
import "core/world"
import "core/autothrow"
local match, world, autothrow = tw.match, tw.world, tw.autothrow
local fmt, sqrt = string.format, math.sqrt

local n, matches, seed = 300, 40, 2
local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--n" then n = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--matches" then matches = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--seed" then seed = tonumber(arg[i + 1]); i = i + 1
	else error("unknown argument " .. a) end
	i = i + 1
end

local START = { year = 2026, month = 11, day = 20, hour = 9, min = 0 }

-- running mean and sd of a value
local function acc() return { n = 0, s = 0, ss = 0 } end
local function add(a, v) a.n, a.s, a.ss = a.n + 1, a.s + v, a.ss + v * v end
local function mean(a) return a.n > 0 and a.s / a.n or 0 end
local function sd(a)
	if a.n < 2 then return 0 end
	local m = a.s / a.n
	local v = a.ss / a.n - m * m
	return v > 0 and sqrt(v) or 0
end
local function cm(v) return 100 * v end

-- Part 1 ---------------------------------------------------------------

-- The first toss of a match: an empty far half.
local function firstToss()
	local m = match.new { start = START, first = "A" }
	local r = autothrow.rng(seed)
	while true do
		local s = match.setup(m)
		if s.kind == "toss" then return s end
		local a = autothrow.choose(s, r, 0.3)
		local w = world.new { surface = "grass", pieces = match.worldPieces(s) }
		autothrow.launch(w, s, a)
		world.run(w)
		match.resolve(m, world.result(w), not a.legal)
	end
end

print(fmt("drillscatter 1: one drill into an empty half, %d throws a row (cm; along is up the pitch)", n))
print("  mistakes  ground    lands: along sd, across sd | travels: along mean sd, across sd | rests from mark: mean, along sd, across sd")
do
	local s = firstToss()
	local drillScale = autothrow.tune.drillScale
	for _, flat in ipairs { true, false } do
		-- scale is of a baton's mistakes, as the game counts it: the game's drill is drillScale
		for _, sc in ipairs { 0, drillScale, 1 } do
			local r = autothrow.rng(seed * 31 + 7)
			local lx, ly, tx, ty, rx, ry, rd = acc(), acc(), acc(), acc(), acc(), acc(), acc()
			local far = 0
			for k = 1, n do
				-- choose() multiplies a toss's scale by drillScale itself
				local a = autothrow.choose(s, r, sc / drillScale)
				local o = { surface = "grass", pieces = match.worldPieces(s), groundSeed = k }
				if flat then o.texture = false end
				local w = world.new(o)
				autothrow.launch(w, s, a)
				world.run(w)
				local b, c = w.projectile, w.firstContact
				local mx, my = a.plan.tx, a.plan.ty
				if c then
					add(lx, c.x - mx); add(ly, c.y - my)
					add(tx, b.x - c.x); add(ty, b.y - c.y)
				end
				local dx, dy = b.x - mx, b.y - my
				add(rx, dx); add(ry, dy); add(rd, sqrt(dx * dx + dy * dy))
				if dx * dx + dy * dy > 0.09 then far = far + 1 end
			end
			print(fmt("  x%-7g  %-8s  %5.1f %5.1f                | %+6.1f %5.1f %5.1f                | %5.1f %5.1f %5.1f, %2.0f%% over 30",
				sc, flat and "flat" or "textured", cm(sd(ly)), cm(sd(lx)), cm(mean(ty)), cm(sd(ty)), cm(sd(tx)),
				cm(mean(rd)), cm(sd(ry)), cm(sd(rx)), 100 * far / n))
		end
	end
end

-- Part 2 ---------------------------------------------------------------

local clean, hit = acc(), acc()          -- rest from mark: touched nothing, touched a piece
local cleanOver, hitOver = 0, 0          -- ... and rested over 30 cm away
local moved, movedOver = acc(), 0        -- how far the pieces a drill touched were moved
local atBasket, atSpot, tosses = 0, 0, 0
local hitLying, hitStanding = 0, 0
local t0 = os.clock()
for gi = 1, matches do
	local m = match.new { start = START, first = (gi % 2 == 0) and "B" or "A" }
	local r = autothrow.rng(seed * 7919 + gi)
	while not match.over(m) and m.game.turn <= 40 do
		local s = match.setup(m)
		if not s then break end
		local a = autothrow.choose(s, r, 1)
		local w = world.new { surface = "grass", pieces = match.worldPieces(s) }
		local before
		if s.kind == "toss" then
			before = {}
			for j = 1, w.n do
				local b = w.bodies[j]
				before[j] = { b.x, b.y, b.toppled }
			end
		end
		autothrow.launch(w, s, a)
		world.run(w)
		if s.kind == "toss" then
			tosses = tosses + 1
			local t = autothrow.tune
			local bx = a.plan.tx < 0 and -a.plan.tx or a.plan.tx
			if bx == t.basketX and a.plan.ty == s.lineY + t.basketY then atBasket = atBasket + 1 else atSpot = atSpot + 1 end
			local p = w.projectile
			local dx, dy = p.x - a.plan.tx, p.y - a.plan.ty
			local d = sqrt(dx * dx + dy * dy)
			local touchedOther = false
			for j = 1, #before do
				local b = w.bodies[j]
				if b ~= p and not b.static and b.touched then
					touchedOther = true
					local mx, my = b.x - before[j][1], b.y - before[j][2]
					local md = sqrt(mx * mx + my * my)
					add(moved, md)
					if md > 0.10 then movedOver = movedOver + 1 end
					if before[j][3] then hitLying = hitLying + 1 else hitStanding = hitStanding + 1 end
				end
			end
			if touchedOther then
				add(hit, d)
				if d > 0.30 then hitOver = hitOver + 1 end
			else
				add(clean, d)
				if d > 0.30 then cleanOver = cleanOver + 1 end
			end
		end
		match.resolve(m, world.result(w), not a.legal)
	end
end

local function pct(a, b) return b > 0 and fmt("%.0f%%", 100 * a / b) or "-" end
print(fmt("drillscatter 2: %d drills in %d physics matches, seed %d (%.0f s)", tosses, matches, seed, os.clock() - t0))
print(fmt("  aimed at the basket itself %s, at a spot beside the group %s", pct(atBasket, tosses), pct(atSpot, tosses)))
print(fmt("  touched no other piece: %s of drills; rest %.0f cm from the mark on average, %s over 30 cm",
	pct(clean.n, tosses), cm(mean(clean)), pct(cleanOver, clean.n)))
print(fmt("  touched a piece:        %s of drills; rest %.0f cm from the mark on average, %s over 30 cm",
	pct(hit.n, tosses), cm(mean(hit)), pct(hitOver, hit.n)))
print(fmt("  pieces a drill touched: %d (%d lying, %d standing), moved %.0f cm on average, %s over 10 cm",
	moved.n, hitLying, hitStanding, cm(mean(moved)), pct(movedOver, moved.n)))
