-- What scatters the drilled kubbs? (AGENTS.md "What scatters a drilled kubb";
-- Jamie approved the measuring, 2026-11-16; no game changes.) Three parts:
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
-- 3. The landing (2026-11-16, Jamie: "When thrown they just stop dead on
--    the ground"): the plan's clean drill (no swing mistakes) onto markers
--    across the far half, on many grounds, at the drill's two arcs: how much
--    its attitude changes in the air, how far it runs on from its first
--    touch, how often it stops dead (rests within 5 cm of where its centre
--    was at the first touch), how it ends (flat, on an end, propped) and how
--    far its long axis is turned from the line of the throw, and how long it
--    takes from the first touch to rest (simulated seconds).
--
--   lua5.4 tools/drillscatter.lua [--n 300] [--matches 40] [--seed 2]
--     [--only 1|2|3] [--grounds 24] [--surface grass] [--set name=value ...]
--   (--set: a number in drill.tune, autothrow.tune as auto.name or world.tune as
--   world.name, for the run)

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
import "core/drill"
local match, world, autothrow = tw.match, tw.world, tw.autothrow
local fmt, sqrt = string.format, math.sqrt

local n, matches, seed, only, grounds, surfaceOnly = 300, 40, 2, nil, 24, nil
local sets = {}
local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--n" then n = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--matches" then matches = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--seed" then seed = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--only" then only = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--grounds" then grounds = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--surface" then surfaceOnly = arg[i + 1]; i = i + 1
	elseif a == "--set" then
		-- a number in drill.tune (or autothrow.tune with "auto.") for the run
		local k, v = arg[i + 1]:match("^([%w%.]+)=(.+)$")
		sets[#sets + 1] = { k, tonumber(v) }
		i = i + 1
	else error("unknown argument " .. a) end
	i = i + 1
end

for _, kv in ipairs(sets) do
	local k, v = kv[1], kv[2]
	if k:sub(1, 5) == "auto." then autothrow.tune[k:sub(6)] = v
	elseif k:sub(1, 6) == "world." then
		assert(world.tune[k:sub(7)] ~= nil, "no world.tune." .. k:sub(7))
		world.tune[k:sub(7)] = v
	else
		assert(tw.drill.tune[k] ~= nil, "no drill.tune." .. k)
		tw.drill.tune[k] = v
	end
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

if not only or only == 1 then
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

end

-- Part 2 ---------------------------------------------------------------
if not only or only == 2 then

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
print(fmt("  aimed at the basket itself %s, at a spot by the group (into it or beside it) %s", pct(atBasket, tosses), pct(atSpot, tosses)))
print(fmt("  touched no other piece: %s of drills; rest %.0f cm from the mark on average, %s over 30 cm",
	pct(clean.n, tosses), cm(mean(clean)), pct(cleanOver, clean.n)))
print(fmt("  touched a piece:        %s of drills; rest %.0f cm from the mark on average, %s over 30 cm",
	pct(hit.n, tosses), cm(mean(hit)), pct(hitOver, hit.n)))
print(fmt("  pieces a drill touched: %d (%d lying, %d standing), moved %.0f cm on average, %s over 10 cm",
	moved.n, hitLying, hitStanding, cm(mean(moved)), pct(movedOver, moved.n)))
end

-- Part 4 ---------------------------------------------------------------
-- Into the group (2026-11-16, Jamie: "good drillers roll into other kubbs"):
-- every drill of physics matches thrown while a kubb of this turn already
-- lies in the far half. Did it reach a lying kubb, how fast was it going
-- when it did, and where did the two end (edge to edge, the footprints of
-- the lying bodies)? And the ones that never reached one: short, beside or
-- past the group?
if not only or only == 4 then
import "core/rect"
local rect = tw.rect
local HL, HW = 0.075, 0.035
local function foot(b)
	return rect.new(b.x, b.y, math.atan(b.r23, b.r13), HL, HW)
end
local function lying(b) return b.r33 < 0.7 and b.r33 > -0.7 end
local into, reached, hitV, gapR, gapN, movedR = 0, 0, acc(), acc(), acc(), acc()
local GB = { 0.01, 0.05, 0.15, 0.30 }
local GL = { "touching (<1 cm)", "1-5 cm", "5-15 cm", "15-30 cm", "over 30 cm" }
local histR, histN = { 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0 }
local VB = { 0.25, 0.5, 1.0, 2.0 }
local VL = { "under 0.25 m/s", "0.25-0.5", "0.5-1", "1-2", "over 2" }
local histV, touchByV = { 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0 }
local short, beside, past, onTop = 0, 0, 0, 0
local landOn = 0
local function bucket(B, v) local k = 1; while k <= #B and v >= B[k] do k = k + 1 end; return k end
local t0 = os.clock()
for gi = 1, matches do
	local m = match.new { start = START, first = (gi % 2 == 0) and "B" or "A" }
	local r = autothrow.rng(seed * 7919 + gi)
	while not match.over(m) and m.game.turn <= 40 do
		local s = match.setup(m)
		if not s then break end
		local a = autothrow.choose(s, r, 1)
		local w = world.new { surface = "grass", pieces = match.worldPieces(s) }
		local group = {}
		if s.kind == "toss" then
			for j = 1, w.n do
				local b = w.bodies[j]
				if b.kind == "kubb" and not b.static and b.y > s.lineY + 4 and b.y < s.lineY + 8.6 and lying(b) then
					group[#group + 1] = { b = b, x = b.x, y = b.y }
				end
			end
		end
		autothrow.launch(w, s, a)
		if #group > 0 then
			local p = w.projectile
			-- the drill's own touch of a group kubb, not its first hit of any
			-- body (a stake or a standing kubb on the way) nor a group kubb
			-- knocked by something else: a group kubb struck this step with the
			-- drill's footprint within 2 cm of it
			local ids = {}
			for _, gk in ipairs(group) do ids[gk.b.id] = true end
			local v0, vHit, landed, hitGroup = 0, nil, nil, false
			while not world.isAtRest(w) and w.time < world.tune.maxTime do
				v0 = sqrt(p.vx * p.vx + p.vy * p.vy + p.vz * p.vz)
				world.step(w)
				if w.firstContact and landed == nil then landed = ids[w.firstContact.with] == true end
				if not hitGroup and p.touchT then
					local pf = foot(p)
					for _, gk in ipairs(group) do
						if gk.b.touchT and rect.distance(pf, foot(gk.b)) < 0.02 then
							hitGroup, vHit = true, v0
							break
						end
					end
				end
			end
			into = into + 1
			local pf = foot(p)
			local best, bestG = math.huge, nil
			for _, gk in ipairs(group) do
				local d = rect.distance(pf, foot(gk.b))
				if d < best then best, bestG = d, gk end
			end
			if hitGroup then
				reached = reached + 1
				add(hitV, vHit or 0)
				local k = bucket(VB, vHit or 0)
				histV[k] = histV[k] + 1
				if best < 0.01 then touchByV[k] = touchByV[k] + 1 end
				add(gapR, best)
				histR[bucket(GB, best)] = histR[bucket(GB, best)] + 1
				for _, gk in ipairs(group) do
					if gk.b.touched then add(movedR, sqrt((gk.b.x - gk.x) ^ 2 + (gk.b.y - gk.y) ^ 2)) end
				end
				if landed then landOn = landOn + 1 end
			else
				add(gapN, best)
				histN[bucket(GB, best)] = histN[bucket(GB, best)] + 1
				-- against the nearest kubb of the group, along the throw
				local dy = p.y - bestG.y
				local dx = p.x - bestG.x
				if dx < 0 then dx = -dx end
				if dx > 0.12 then beside = beside + 1 elseif dy < 0 then short = short + 1 else past = past + 1 end
			end
		else
			world.run(w)
		end
		match.resolve(m, world.result(w), not a.legal)
	end
end
local function pct(a, b) return b > 0 and fmt("%.0f%%", 100 * a / b) or "-" end
print(fmt("drillscatter 4: %d drills thrown while a kubb lay in the far half, %d matches, seed %d (%.0f s)",
	into, matches, seed, os.clock() - t0))
print(fmt("  reached a lying kubb: %s (landed on one first: %s of those); speed at the touch mean %.2f m/s",
	pct(reached, into), pct(landOn, reached), mean(hitV)))
for k = 1, 5 do
	print(fmt("    at %-15s %s of touches, of which ended touching %s", VL[k], pct(histV[k], reached), pct(touchByV[k], histV[k])))
end
print(fmt("  reached: drill's edge gap to the nearest lying kubb at rest mean %.0f cm; the kubb it touched moved %.0f cm",
	cm(mean(gapR)), cm(mean(movedR))))
for k = 1, 5 do print(fmt("    %-18s %s", GL[k], pct(histR[k], reached))) end
print(fmt("  never reached: gap mean %.0f cm; short of the nearest %s, beside it %s, past it %s",
	cm(mean(gapN)), pct(short, into - reached), pct(beside, into - reached), pct(past, into - reached)))
for k = 1, 5 do print(fmt("    %-18s %s", GL[k], pct(histN[k], into - reached))) end
end

-- Part 3 ---------------------------------------------------------------
if not only or only == 3 then
import "core/drill"
import "core/throwplan"
local drill = tw.drill
local deg, asin, atan, abs = math.deg, math.asin, math.atan, math.abs
local MX, MY = { -1.5, 0, 1.5 }, { 4.6, 5.5, 6.5, 7.5 }
print(fmt("drillscatter 3: the plan's clean drill, %d markers x %d grounds (cm, degrees, s)", #MX * #MY, grounds))
print("  ground  loft | nose at release, at touch (sd) turned | run on: mean sd p10 p50 p90 max, dead<5cm | rest from mark | flat end other, yaw 0-30 30-60 60-90 | touch to rest mean max")
for _, surface in ipairs { "grass", "sand", "snow" } do
	if not surfaceOnly or surfaceOnly == surface then
	for _, loft in ipairs { 47, 30 } do
		local rel, tch, turned, run, rest, ttr = acc(), acc(), acc(), acc(), acc(), acc()
		local runs, dead, flat, onEnd, other, worstT = {}, 0, 0, 0, 0, 0
		local yaw = { 0, 0, 0 }
		for _, my in ipairs(MY) do
			for _, mx in ipairs(MX) do
				for g = 1, grounds do
					local sol = drill.solveAt(mx, my, 0, loft, {}, nil, surface)
					local L = drill.body(1, 1, 0, {})
					local w = world.new { surface = surface, groundSeed = g * 7919 + 13 }
					local b = world.launchDrill(w, "d", sol.x, 0, sol.swivel, sol.loft, sol.speed, L.noseDown, L.rollLand,
						L.spin, L.wobble)
					local n0 = deg(asin(-b.r33))
					local ax0, ay0, az0 = b.r13, b.r23, b.r33
					local land, n1, t1, ax1, ay1, az1
					while not world.isAtRest(w) do
						local az = b.r33
						local qx, qy, qz = b.r13, b.r23, b.r33
						world.step(w)
						if w.firstContact and not land then
							land, t1 = { x = b.x, y = b.y }, w.time
							n1 = deg(asin(-az))
							ax1, ay1, az1 = qx, qy, qz
						end
					end
					add(rel, n0); add(tch, n1)
					local dot = ax0 * ax1 + ay0 * ay1 + az0 * az1
					if dot > 1 then dot = 1 elseif dot < -1 then dot = -1 end
					add(turned, deg(math.acos(dot)))
					local d = sqrt((b.x - land.x) ^ 2 + (b.y - land.y) ^ 2)
					add(run, d); runs[#runs + 1] = d
					if d < 0.05 then dead = dead + 1 end
					add(rest, sqrt((b.x - mx) ^ 2 + (b.y - my) ^ 2))
					local tt = w.time - t1
					add(ttr, tt)
					if tt > worstT then worstT = tt end
					local r33 = abs(b.r33)
					if r33 > 0.866 then onEnd = onEnd + 1
					elseif r33 < 0.17 and (abs(b.r31) > 0.98 or abs(b.r32) > 0.98) then flat = flat + 1
					else other = other + 1 end
					if r33 < 0.866 then
						local y = deg(atan(abs(b.r13), abs(b.r23)))
						yaw[y < 30 and 1 or (y < 60 and 2 or 3)] = yaw[y < 30 and 1 or (y < 60 and 2 or 3)] + 1
					end
				end
			end
		end
		table.sort(runs)
		local N = #runs
		local function q(p) return runs[math.max(1, math.floor(p * N + 0.5))] end
		local ny = yaw[1] + yaw[2] + yaw[3]
		print(fmt("  %-6s  %4d | %5.1f %5.1f (%4.1f) %5.1f | %5.1f %5.1f %5.1f %5.1f %5.1f %5.1f, %3.0f%% | %5.1f | %3.0f%% %3.0f%% %3.0f%%, %3.0f%% %3.0f%% %3.0f%% | %4.2f %4.2f",
			surface, loft, mean(rel), mean(tch), sd(tch), mean(turned),
			cm(mean(run)), cm(sd(run)), cm(q(0.1)), cm(q(0.5)), cm(q(0.9)), cm(runs[N]), 100 * dead / N,
			cm(mean(rest)), 100 * flat / N, 100 * onEnd / N, 100 * other / N,
			100 * yaw[1] / math.max(1, ny), 100 * yaw[2] / math.max(1, ny), 100 * yaw[3] / math.max(1, ny),
			mean(ttr), worstT))
	end
	end
end
end
