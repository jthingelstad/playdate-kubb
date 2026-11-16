-- Drill spin: how far the planned spin rolls a drilled kubb sideways, and
-- whether drills rolled into the centerline stake build a wall. A headless,
-- deterministic experiment on core/world, core/drill and core/throwplan (the
-- ground texture seed is fixed per throw, so two spins at the same marker
-- meet the same ground).
--
--   lua5.4 tools/spinwall.lua [--quick] [--lofts 47,30] [--no-sand] [--no-wall]
--
-- Every drill is the plan's clean drill (core/throwplan): drill.solveAt onto
-- the marker at the loft, launched by world.launchDrill with drill.body's
-- numbers, the spin `taps` * plan.tune.spinPerStep (+ rolls right, toward +x).
-- The lofts are launch angles: 47 is the drill's default arc (half past 1 on
-- the clock), 30 a low arc (about 3 o'clock).
--
-- 1. Roll: for taps -spinSteps .. +spinSteps at markers 4.6 to 7.2 m out at
--    three x, on several grounds; per tap, over markers and grounds:
--      side    rest x minus the 0-tap drill's rest x (same marker, ground), m
--      roll    rest x minus the centre's x at the first touch (after landing)
--      fwd     rest y minus the centre's y at the first touch (the forward slide)
--      miss    distance from the rest to the marker
--      hop     highest the centre rose after the first touch, above a lying kubb's 0.035 m
--      lying/end/other  how it rests: long axis within 10 degrees of horizontal and
--              a face down (within 10 degrees), on an end (within 30 of vertical),
--              or neither (on an edge, propped)
--      nose    share of drills whose first touch was ahead of the centre
--              along the long axis (nose first)
--      sd      spread (standard deviation) of side over markers and grounds
-- 2. Wall: markers inward of the stake at (2.5, 4) by o along x at a few y
--    just past 4, rolled toward it with 1, 2 and 3 taps. The first kubb is
--      against  rests within 1.5 cm of the stake
--      bounced  touched the stake, rests farther than that
--      short    never touched it, rests inward of it
--      past     never touched it, went by it (beyond in y, or out past x = 2.5)
--    Per cell: gap = the first kubb's mean distance from the stake (m), its rest y
--    mean and spread. Then a second and a third kubb at the same marker and taps,
--    on the same ground, the earlier ones lying where they came to rest (asleep,
--    toppled, as core/debris carries them). Each later kubb is
--      beside   rests touching the wall (an earlier kubb or the stake) within
--               1.5 cm, lying, centre within 12 cm of y = 4, and no earlier
--               kubb moved more than 3 cm
--      shoved   as beside, but an earlier kubb moved 3 to 10 cm
--      knocked  an earlier kubb moved more than 10 cm
--      ontop    it rests on another kubb (centre above 6 cm)
--      apart    none of these (stopped short of the wall or went elsewhere)
--    and "wall n" counts series whose final kubbs make a chain of n from the
--    stake (each within 1.5 cm of the one before, centre within 12 cm of y = 4).
--    "best" lists, per tap count, the offset that built the most walls of 3.
--    The full run repeats the wall with the marker moved 7 cm (a kubb's width)
--    inward for each later kubb, as a player who sees the wall would.
--
-- --quick: fewer markers, grounds and wall cells, no stepped wall (about 10
-- seconds; the full run about two minutes).

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end

import "core/world"
import "core/drill"
import "core/throwplan"
import "core/rect"
import "core/raising"
import "core/pitch"
local world, drill, plan, rect, raising, pitch = tw.world, tw.drill, tw.plan, tw.rect, tw.raising, tw.pitch

local quick, sand, wall, loftArg = false, true, true, "47,30"
local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--quick" then quick = true
	elseif a == "--no-sand" then sand = false
	elseif a == "--no-wall" then wall = false
	elseif a == "--lofts" then loftArg = arg[i + 1]; i = i + 1
	else error("unknown argument " .. a) end
	i = i + 1
end
local LOFTS = {}
for s in loftArg:gmatch("[^,]+") do LOFTS[#LOFTS + 1] = tonumber(s) end

local fmt = string.format
local sqrt, sin, cos, atan, rad, abs, max, min = math.sqrt, math.sin, math.cos, math.atan, math.rad,
	math.abs, math.max, math.min
local PER, STEPS = plan.tune.spinPerStep, plan.tune.spinSteps
local STAKE_X, STAKE_Y, STAKE_R = 2.5, 4, pitch.stakeRadius

-- ---------------------------------------------------------------------------
-- The launch

-- (aimed short by what it runs on with that spin on that ground: drill.slideFor)
local function solveAt(mx, my, loft, surface, taps)
	return drill.solveAt(mx, my, 0, loft, {}, nil, surface, (taps or 0) * PER)
end

local BODY = {}

-- One clean drill as body `id` into world w at the solution sol with this
-- many taps of spin. Steps it to rest and fills `out`: land (centre at the
-- first touch), nose (first touch ahead of the centre), hop, the body.
local function drillInto(w, id, sol, taps, out)
	local L = drill.body(1, 1, taps * PER, BODY)
	local b = world.launchDrill(w, id, sol.x, 0, sol.swivel, sol.loft, sol.speed, L.noseDown, L.rollLand,
		L.spin, L.wobble)
	local landX, landY, hop, nose = nil, nil, 0, false
	while not world.isAtRest(w) do
		world.step(w)
		local fc = w.firstContact
		if fc then
			if not landX then
				landX, landY = b.x, b.y
				nose = (fc.x - b.x) * b.r13 + (fc.y - b.y) * b.r23 + (fc.z - b.z) * b.r33 > 0
			end
			if b.z - 0.035 > hop then hop = b.z - 0.035 end
		end
	end
	out.b, out.landX, out.landY, out.hop, out.nose = b, landX or b.x, landY or b.y, hop, nose
	return out
end

-- How a box rests: "lying" (on a face), "end" or "other".
local function restKind(b)
	local a = abs(b.r33)
	if a > cos(rad(30)) then return "end" end
	if a < sin(rad(10)) then
		-- a face down: one cross axis within 10 degrees of vertical
		if abs(b.r31) > cos(rad(10)) or abs(b.r32) > cos(rad(10)) then return "lying" end
	end
	return "other"
end

-- The ground rectangle of a body at rest (raising's kubb footprint).
local function footprint(b)
	local standing = abs(b.r33) > cos(rad(45))
	local ang = standing and atan(b.r21, b.r11) or atan(b.r23, b.r13)
	return raising.kubbRect { x = b.x, y = b.y, standing = standing, angle = ang }
end

local function stakeGap(b)
	return rect.pointDistance(footprint(b), STAKE_X, STAKE_Y) - STAKE_R
end

local function stats(list)
	local n = #list
	if n == 0 then return 0, 0 end
	local s, s2 = 0, 0
	for _, v in ipairs(list) do s, s2 = s + v, s2 + v * v end
	local m = s / n
	return m, sqrt(max(0, s2 / n - m * m))
end

-- ---------------------------------------------------------------------------
-- 1. Roll

local MARKERS = quick
	and { { -1.2, 4.6 }, { 0, 5.8 }, { 1.2, 7.2 } }
	or { { -1.2, 4.6 }, { 0, 4.6 }, { 1.2, 4.6 }, { -1.2, 5.4 }, { 0, 5.4 }, { 1.2, 5.4 },
		{ -1.2, 6.3 }, { 0, 6.3 }, { 1.2, 6.3 }, { -1.2, 7.2 }, { 0, 7.2 }, { 1.2, 7.2 } }
local GROUNDS = quick and { 11, 12 } or { 11, 12, 13, 14, 15, 16, 17, 18 }

local function rollTable(surface, loft, markers, grounds)
	local t0, sims = os.clock(), 0
	print(fmt("  %s, loft %d: %d markers x %d grounds per tap (%g rad/s a tap)", surface, loft, #markers,
		#grounds, PER))
	print("   taps  spin   side m (sd)      roll m   fwd m (sd)      miss m  hop cm     lying end other  nose")
	local base, out = {}, {}
	local rows = {}
	for k = -STEPS, STEPS do rows[#rows + 1] = k end
	table.sort(rows, function(p, q) return abs(p) < abs(q) or (abs(p) == abs(q) and p > q) end)
	local summary = {}
	for _, k in ipairs(rows) do
		local side, roll, fwd, miss, hop = {}, {}, {}, {}, {}
		local kinds, noses = { lying = 0, ["end"] = 0, other = 0 }, 0
		for mi, m in ipairs(markers) do
			local sol = solveAt(m[1], m[2], loft, surface, k)
			for gi, g in ipairs(grounds) do
				local w = world.new { surface = surface, groundSeed = g }
				drillInto(w, "d1", sol, k, out)
				sims = sims + 1
				local b = out.b
				local key = mi * 100 + gi
				if k == 0 then base[key] = b.x end
				side[#side + 1] = b.x - base[key]
				roll[#roll + 1] = b.x - out.landX
				fwd[#fwd + 1] = b.y - out.landY
				miss[#miss + 1] = sqrt((b.x - m[1]) ^ 2 + (b.y - m[2]) ^ 2)
				hop[#hop + 1] = out.hop
				local rk = restKind(b)
				kinds[rk] = kinds[rk] + 1
				if out.nose then noses = noses + 1 end
			end
		end
		local n = #side
		local sm, ss = stats(side)
		local rm = stats(roll)
		local fm, fs = stats(fwd)
		local mm = stats(miss)
		local hm = stats(hop)
		local hmax = 0
		for _, v in ipairs(hop) do if v > hmax then hmax = v end end
		print(fmt("   %+3d  %+5.1f  %+6.3f (%5.3f)  %+6.3f  %+6.3f (%5.3f)  %5.2f  %4.1f/%4.1f  %3d %3d %3d  %3d%%",
			k, k * PER, sm, ss, rm, fm, fs, mm, hm * 100, hmax * 100,
			kinds.lying, kinds["end"], kinds.other, math.floor(100 * noses / n + 0.5)))
		summary[k] = { side = sm, sd = ss, fwd = fm, roll = rm }
	end
	print(fmt("   (%d drills, %.1f s; hop mean/max)", sims, os.clock() - t0))
	return summary
end

print(fmt("1. Roll: the plan's clean drills, spin in taps of %g rad/s (side = rest x vs the 0-tap drill"
	.. " on the same ground)", PER))
local rolls = {}
for _, loft in ipairs(LOFTS) do rolls["grass" .. loft] = rollTable("grass", loft, MARKERS, GROUNDS) end
if sand then
	local SMK = quick and { { -1.2, 4.6 }, { 0, 5.8 }, { 1.2, 7.2 } }
		or { { -1.2, 4.6 }, { 0, 5.4 }, { 1.2, 6.3 }, { -0.5, 7.2 } }
	local SGR = quick and { 11, 12 } or { 11, 12, 13, 14 }
	for _, loft in ipairs(LOFTS) do rolls["sand" .. loft] = rollTable("sand", loft, SMK, SGR) end
end
print()
print("   summary: side m (fwd m) by taps 1 / 2 / 3, the mean of + and - taps signed toward the spin:")
for _, surface in ipairs { "grass", "sand" } do
	for _, loft in ipairs(LOFTS) do
		local r = rolls[surface .. loft]
		if r then
			local parts = {}
			for k = 1, STEPS do
				parts[#parts + 1] = fmt("%.2f (%+.2f)", (r[k].side - r[-k].side) / 2, (r[k].fwd + r[-k].fwd) / 2)
			end
			print(fmt("     %-5s loft %d: %s", surface, loft, table.concat(parts, " / ")))
		end
	end
end

if not wall then return end

-- ---------------------------------------------------------------------------
-- 2. Wall

local OFFSETS = quick and { 0.15, 0.3, 0.5, 0.8 }
	or { 0.1, 0.15, 0.2, 0.25, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9 }
local YS = quick and { 4.05, 4.15 } or { 4.0, 4.05, 4.1, 4.15, 4.2 }
local WALL_TAPS = { 1, 2, 3 }
local WALL_GROUNDS = quick and { 21 } or { 21, 22, 23, 24, 25, 26 }
local TOUCH = 0.015
local ONLINE = 0.12

local function nearWall(fp, others)
	if rect.pointDistance(fp, STAKE_X, STAKE_Y) - STAKE_R < TOUCH then return true end
	for _, o in ipairs(others) do
		if rect.distance(fp, o) < TOUCH then return true end
	end
	return false
end

-- Length of the chain from the stake among final poses `fps` (with y's).
local function chainLength(fps)
	local inWall, n, grew = {}, 0, true
	local members = {}
	while grew do
		grew = false
		for k, f in ipairs(fps) do
			if not inWall[k] and abs(f.y - STAKE_Y) < ONLINE and nearWall(f, members) then
				inWall[k], n, grew = true, n + 1, true
				members[#members + 1] = f
			end
		end
	end
	return n
end

local function wallRun(loft, step)
	local t0, sims = os.clock(), 0
	local out = {}
	print(fmt("  loft %d, %s: %d y's x %d grounds per cell (marker y %s)", loft,
		step and fmt("marker stepped %.0f cm inward per kubb", step * 100) or "same marker every kubb",
		#YS, #WALL_GROUNDS, table.concat(YS, "/")))
	print("   taps  off  | gap  rest y/sd | 1st: against bounced short past | 2nd: beside shoved knocked ontop apart"
		.. " | 3rd: beside shoved knocked ontop apart | wall>=2 wall3")
	local best = {}
	for _, k in ipairs(WALL_TAPS) do
		for _, o in ipairs(OFFSETS) do
			local c1 = { against = 0, bounced = 0, short = 0, past = 0 }
			local c2 = { beside = 0, shoved = 0, knocked = 0, ontop = 0, apart = 0 }
			local c3 = { beside = 0, shoved = 0, knocked = 0, ontop = 0, apart = 0 }
			local w2, w3, n = 0, 0, 0
			local gaps, rys = {}, {}
			for _, y in ipairs(YS) do
				local sols = {}
				for throw = 1, 3 do sols[throw] = solveAt(STAKE_X - o - (throw - 1) * (step or 0), y, loft, "grass", k) end
				for _, g in ipairs(WALL_GROUNDS) do
					n = n + 1
					local lying = {}   -- pieces at rest so far
					local fps = {}
					for throw = 1, 3 do
						local w = world.new { surface = "grass", groundSeed = g, pieces = lying }
						local before = {}
						for _, p in ipairs(lying) do before[p.id] = { p.x, p.y } end
						local id = "d" .. throw
						drillInto(w, id, sols[throw], k, out)
						sims = sims + 1
						local b = out.b
						local res = world.result(w)
						local stakeHit = false
						for _, s in ipairs(res.stakesTouched) do if s == "stake4" then stakeHit = true end end
						if throw == 1 then
							local gap = stakeGap(b)
							gaps[#gaps + 1], rys[#rys + 1] = gap, b.y
							if gap < TOUCH then c1.against = c1.against + 1
							elseif stakeHit then c1.bounced = c1.bounced + 1
							elseif b.x < STAKE_X - 0.04 and b.y < STAKE_Y + 0.11 then c1.short = c1.short + 1
							else c1.past = c1.past + 1 end
						else
							local moved = 0
							local others = {}
							for _, p in ipairs(lying) do
								local q = w.byId[p.id]
								local d = sqrt((q.x - before[p.id][1]) ^ 2 + (q.y - before[p.id][2]) ^ 2)
								if d > moved then moved = d end
								others[#others + 1] = footprint(q)
							end
							local c = (throw == 2) and c2 or c3
							local fp = footprint(b)
							if b.z > 0.06 then c.ontop = c.ontop + 1
							elseif moved > 0.10 then c.knocked = c.knocked + 1
							elseif restKind(b) == "lying" and abs(b.y - STAKE_Y) < ONLINE and nearWall(fp, others) then
								if moved > 0.03 then c.shoved = c.shoved + 1 else c.beside = c.beside + 1 end
							else c.apart = c.apart + 1 end
						end
						-- carry everything to the next throw as it lies
						local nextLying = {}
						fps = {}
						for _, p in ipairs(lying) do nextLying[#nextLying + 1] = p.id end
						nextLying[#nextLying + 1] = id
						lying = {}
						for _, pid in ipairs(nextLying) do
							local q = w.byId[pid]
							lying[#lying + 1] = { id = pid, kind = "kubb", x = q.x, y = q.y, z = q.z,
								qw = q.qw, qx = q.qx, qy = q.qy, qz = q.qz, toppled = true }
							local f = footprint(q)
							f.y = q.y
							fps[#fps + 1] = f
						end
						if throw == 2 and chainLength(fps) >= 2 then w2 = w2 + 1 end
					end
					if chainLength(fps) >= 3 then w3 = w3 + 1 end
				end
			end
			local gm = stats(gaps)
			local ym, ysd = stats(rys)
			print(fmt("   %3d  %4.2f | %5.2f %5.2f/%4.2f | %7d %7d %5d %4d | %11d %6d %7d %5d %5d | %11d %6d %7d %5d %5d | %4d/%d %3d/%d",
				k, o, gm, ym, ysd, c1.against, c1.bounced, c1.short, c1.past,
				c2.beside, c2.shoved, c2.knocked, c2.ontop, c2.apart,
				c3.beside, c3.shoved, c3.knocked, c3.ontop, c3.apart, w2, n, w3, n))
			local bk = best[k]
			if not bk or w3 > bk.w3 or (w3 == bk.w3 and (w2 > bk.w2 or (w2 == bk.w2 and c1.against > bk.a))) then
				best[k] = { o = o, a = c1.against, w2 = w2, w3 = w3, n = n }
			end
		end
	end
	local tops = {}
	for _, k in ipairs(WALL_TAPS) do
		local b = best[k]
		tops[#tops + 1] = fmt("%d tap%s, %.2f m inward: 1st against %d, wall of 2 %d, wall of 3 %d of %d",
			k, k == 1 and "" or "s", b.o, b.a, b.w2, b.w3, b.n)
	end
	print("   best:\n     " .. table.concat(tops, "\n     "))
	print(fmt("   (%d drills, %.1f s)", sims, os.clock() - t0))
end

print()
print(fmt("2. Wall at the stake (%.1f, %.0f): marker o inward of it, rolled toward it", STAKE_X, STAKE_Y))
for _, loft in ipairs(LOFTS) do wallRun(loft) end
if not quick then
	-- a player who sees the wall moves the marker in one kubb width each time
	for _, loft in ipairs(LOFTS) do wallRun(loft, 0.07) end
end
