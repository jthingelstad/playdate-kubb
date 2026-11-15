-- Drill spin: how far the cut rolls a drilled kubb sideways, and whether
-- drills rolled into the centerline stake build a wall. A headless,
-- deterministic experiment on core/world and core/drill (the ground texture
-- seed is fixed per throw, so two spins at the same marker meet the same
-- ground).
--
--   lua5.4 tools/spinwall.lua [--quick] [--lofts low,47] [--sand]
--
-- Every drill is clean (smoothness 1, power on the band, no tilt), launched
-- by world.launchDrill with drill.launch's numbers except the spin, which is
-- set directly (rad/s about the forward long axis; negative rolls right,
-- toward +x, as drill.CUT_A does). Two lofts: "low" is drill.solve's own
-- (26 to 30 degrees by distance); a number is that loft with the speed that
-- carries the same clean drill to the same marker (drill.solve's formula,
-- the same slideAllow), noseDown and rollLand as drill.tune has them.
--
-- 1. Roll: for spins k * drill.tune.cutSpin (k listed below), at
--    markers 4.5 to 7 m out at three x: per spin, over markers and grounds,
--      side    rest x minus the spin-0 drill's rest x (same marker, ground), m
--      roll    rest x minus the center's x at the first touch (the roll after landing)
--      fwd     rest y minus the center's y at the first touch (the forward slide)
--      miss    distance from the rest to the marker
--      hop     highest the center rose after the first touch, above a lying kubb's 0.035 m
--      lying/end/other  how it rests: long axis within 10 degrees of horizontal,
--              within 30 of vertical (on an end), or neither
--      flip    share of drills whose long axis passed 60 degrees from
--              horizontal after landing (went end over end)
--      sd      spread (standard deviation) of side over markers and grounds
--    Spins k = 0, +-0.5, 1, 1.5, 2, 3, 4, 6. The full run also gives sand (fewer
--    markers and spins).
-- 2. Wall: markers short of the stake at (2.5, 4) by o inward along x and at a
--    few y about 4, spins that roll toward it. The first kubb is classed
--      against  rests within 1.5 cm of the stake
--      bounced  touched the stake, rests farther than that
--      short    never touched it, rests inward of it
--      past     never touched it, went by it (beyond in y, or out past x = 2.5)
--    Per cell: gap = the first kubb's mean distance from the stake (m), its rest y
--    mean and spread. Then a second and a third kubb at the same marker and spin, on the same
--    ground, the earlier ones lying where they came to rest (asleep, toppled,
--    as core/debris carries them). Each later kubb is classed
--      beside   rests touching the wall (an earlier kubb or the stake) within
--               1.5 cm, lying, centre within 12 cm of y = 4, and no earlier
--               kubb moved more than 3 cm
--      shoved   as beside, but an earlier kubb moved 3 to 10 cm
--      knocked  an earlier kubb moved more than 10 cm
--      ontop    it rests on another kubb (centre above 6 cm)
--      apart    none of these (stopped short of the wall or went elsewhere)
--    and "wall n" counts series whose final kubbs make a chain of n from the
--    stake (each within 1.5 cm of the one before, centre within 12 cm of y = 4).
--    The full run repeats the wall with the marker moved 7 cm (a kubb's width)
--    inward for each later kubb, as a player who sees the wall would.
--
-- --quick: fewer markers, grounds and wall cells, no sand, no stepped wall
-- (under a second; the full run about 45 s). --sand adds sand to --quick.
-- --lofts: comma list, "low" for drill.solve's loft (default low,47).

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
import "core/flight"
import "core/rect"
import "core/raising"
import "core/pitch"
local world, drill, flight, rect, raising, pitch = tw.world, tw.drill, tw.flight, tw.rect, tw.raising, tw.pitch

local quick, sand, loftArg = false, false, "low,47"
local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--quick" then quick = true
	elseif a == "--sand" then sand = true
	elseif a == "--lofts" then loftArg = arg[i + 1]; i = i + 1
	else error("unknown argument " .. a) end
	i = i + 1
end
local LOFTS = {}
for s in loftArg:gmatch("[^,]+") do LOFTS[#LOFTS + 1] = (s == "low") and "low" or tonumber(s) end

local fmt = string.format
local sqrt, sin, cos, atan, rad, deg, abs, max, min = math.sqrt, math.sin, math.cos, math.atan, math.rad,
	math.deg, math.abs, math.max, math.min
local CUT = drill.tune.cutSpin
local STAKE_X, STAKE_Y, STAKE_R = 2.5, 4, pitch.stakeRadius

-- ---------------------------------------------------------------------------
-- The launch

-- drill.solve, with the loft fixed instead of chosen by distance.
local function solveAt(mx, my, loft)
	local sol = drill.solve(mx, my, 0, {})
	if loft == "low" then return sol end
	local t, ft = drill.tune, flight.tune
	local h0 = ft.handHeight - t.landZ
	local e = rad(loft)
	local R = max(0.5, sol.dist - t.slideAllow)
	local c = cos(e)
	sol.speed = sqrt(ft.g * R * R / (2 * c * c * (R * sin(e) / c + h0)))
	sol.loft = loft
	return sol
end

local CLEAN = { smoothness = 1, tilt = 0, how = "passed" }

-- One clean drill as body `id` into world w at the solution sol with this
-- spin. Steps it to rest and fills `out`: land (center at the first touch),
-- hop, flip, the body.
local function drillInto(w, id, sol, spin, out)
	CLEAN.power = sol.band
	local L = drill.launch(sol, CLEAN, 0)
	local b = world.launchDrill(w, id, sol.x, 0, L.swivel, sol.loft, L.speed, L.noseDown, L.rollLand,
		spin, L.wobble, L.digGain)
	local landX, landY, hop, flip = nil, nil, 0, false
	while not world.isAtRest(w) do
		world.step(w)
		if w.firstContact then
			if not landX then landX, landY = b.x, b.y end
			if b.z - 0.035 > hop then hop = b.z - 0.035 end
			if abs(b.r33) > 0.866 then flip = true end
		end
	end
	out.b, out.landX, out.landY, out.hop, out.flip = b, landX or b.x, landY or b.y, hop, flip
	out.time = w.time
	return out
end

-- How a box rests: "lying", "end" or "other".
local function restKind(b)
	local a = abs(b.r33)
	if a < sin(rad(10)) then return "lying" end
	if a > cos(rad(30)) then return "end" end
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

local function loftName(l) return l == "low" and "low (26-30)" or fmt("%d deg", l) end

-- ---------------------------------------------------------------------------
-- 1. Roll

local MULTS = { 0, 0.5, -0.5, 1, -1, 1.5, -1.5, 2, -2, 3, -3, 4, -4, 6, -6 }
local MARKERS = quick
	and { { -1.2, 4.5 }, { 0, 5.75 }, { 1.2, 7 } }
	or { { -1.2, 4.5 }, { 0, 4.5 }, { 1.2, 4.5 }, { -1.2, 5.25 }, { 0, 5.25 }, { 1.2, 5.25 },
		{ -1.2, 6.25 }, { 0, 6.25 }, { 1.2, 6.25 }, { -1.2, 7 }, { 0, 7 }, { 1.2, 7 } }
local GROUNDS = quick and { 11, 12 } or { 11, 12, 13, 14, 15, 16, 17, 18 }

local function rollTable(surface, loft, mults, markers, grounds)
	local t0, sims = os.clock(), 0
	print(fmt("  %s, loft %s: %d markers x %d grounds per spin", surface, loftName(loft), #markers, #grounds))
	print("   spin rad/s   side m (sd)       roll m   fwd m (sd)      miss m  hop cm  lying end other  flip")
	local base = {}
	local out = {}
	for _, k in ipairs(mults) do
		local spin = -k * CUT   -- k > 0: rolls right (as CUT_A)
		local side, roll, fwd, miss, hop = {}, {}, {}, {}, {}
		local kinds, flips = { lying = 0, ["end"] = 0, other = 0 }, 0
		for mi, m in ipairs(markers) do
			local sol = solveAt(m[1], m[2], loft)
			for gi, g in ipairs(grounds) do
				local w = world.new { surface = surface, groundSeed = g }
				drillInto(w, "d1", sol, spin, out)
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
				if out.flip then flips = flips + 1 end
			end
		end
		local n = #side
		local sm, ss = stats(side)
		local rm = stats(roll)
		local fm, fs = stats(fwd)
		local mm = stats(miss)
		local hm, hs = stats(hop)
		local hmax = 0
		for _, v in ipairs(hop) do if v > hmax then hmax = v end end
		print(fmt("   %+5.1f %+6.0f  %+6.3f (%5.3f)  %+6.3f  %+6.3f (%5.3f)  %5.2f  %4.1f/%4.1f  %3d %3d %3d  %3d%%",
			k, spin, sm, ss, rm, fm, fs, mm, hm * 100, hmax * 100,
			kinds.lying, kinds["end"], kinds.other, math.floor(100 * flips / n + 0.5)))
	end
	print(fmt("   (%d drills, %.1f s; spin k = multiple of cutSpin %g, + rolls right; hop mean/max)", sims, os.clock() - t0, CUT))
end

print("1. Roll: clean drills, spin set directly (side = rest x vs the spin-0 drill on the same ground)")
for _, loft in ipairs(LOFTS) do rollTable("grass", loft, MULTS, MARKERS, GROUNDS) end
if sand or not quick then
	local SM = { 0, 1, -1, 2, -2, 4, -4 }
	local SMK = { { -1.2, 4.5 }, { 0, 5.75 }, { 1.2, 7 } }
	for _, loft in ipairs(LOFTS) do rollTable("sand", loft, SM, SMK, { 11, 12 }) end
end

-- ---------------------------------------------------------------------------
-- 2. Wall

local OFFSETS = quick and { 0.05, 0.1, 0.2 } or { 0.05, 0.08, 0.11, 0.15, 0.2, 0.3, 0.45 }
local YS = quick and { 3.95, 4.05 } or { 3.85, 3.95, 4.05, 4.15, 4.25 }
local WALL_MULTS = quick and { 0, 1, 2 } or { 0, 0.5, 1, 1.5, 2, 3 }
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
	print(fmt("  loft %s, %s: %d y's x %d grounds per cell (marker y %s)", loftName(loft),
		step and fmt("marker stepped %.0f cm inward per kubb", step * 100) or "same marker every kubb",
		#YS, #WALL_GROUNDS, table.concat(YS, "/")))
	print("   spin   off  | gap  rest y/sd | 1st: against bounced short past | 2nd: beside shoved knocked ontop apart"
		.. " | 3rd: beside shoved knocked ontop apart | wall>=2 wall3")
	local best = {}
	for _, k in ipairs(WALL_MULTS) do
		local spin = -k * CUT
		for _, o in ipairs(OFFSETS) do
			local c1 = { against = 0, bounced = 0, short = 0, past = 0 }
			local c2 = { beside = 0, shoved = 0, knocked = 0, ontop = 0, apart = 0 }
			local c3 = { beside = 0, shoved = 0, knocked = 0, ontop = 0, apart = 0 }
			local w2, w3, n = 0, 0, 0
			local gaps, rys = {}, {}
			local w3y, a1y = {}, {}
			for yi, y in ipairs(YS) do
				w3y[yi], a1y[yi] = 0, 0
				local sols = {}
				for throw = 1, 3 do sols[throw] = solveAt(STAKE_X - o - (throw - 1) * (step or 0), y, loft) end
				for _, g in ipairs(WALL_GROUNDS) do
					n = n + 1
					local lying = {}   -- pieces at rest so far
					local fps = {}
					for throw = 1, 3 do
						local w = world.new { surface = "grass", groundSeed = g, pieces = lying }
						local before = {}
						for _, p in ipairs(lying) do before[p.id] = { p.x, p.y } end
						local id = "d" .. throw
						drillInto(w, id, sols[throw], spin, out)
						sims = sims + 1
						local b = out.b
						local res = world.result(w)
						local stakeHit = false
						for _, s in ipairs(res.stakesTouched) do if s == "stake4" then stakeHit = true end end
						if throw == 1 then
							local gap = stakeGap(b)
							gaps[#gaps + 1], rys[#rys + 1] = gap, b.y
							if gap < TOUCH then c1.against, a1y[yi] = c1.against + 1, a1y[yi] + 1
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
					local cl = chainLength(fps)
					if cl >= 3 then w3, w3y[yi] = w3 + 1, w3y[yi] + 1 end
				end
			end
			local gm = stats(gaps)
			local ym, ysd = stats(rys)
			print(fmt("   %+4.1f  %4.2f | %5.2f %5.2f/%4.2f | %7d %7d %5d %4d | %11d %6d %7d %5d %5d | %11d %6d %7d %5d %5d | %4d/%d %3d/%d",
				k, o, gm, ym, ysd, c1.against, c1.bounced, c1.short, c1.past,
				c2.beside, c2.shoved, c2.knocked, c2.ontop, c2.apart,
				c3.beside, c3.shoved, c3.knocked, c3.ontop, c3.apart, w2, n, w3, n))
			best[#best + 1] = { k = k, o = o, a = c1.against, w2 = w2, w3 = w3, n = n,
				w3y = table.concat(w3y, "/"), a1y = table.concat(a1y, "/") }
		end
	end
	table.sort(best, function(p, q)
		if p.w3 ~= q.w3 then return p.w3 > q.w3 end
		if p.w2 ~= q.w2 then return p.w2 > q.w2 end
		return p.a > q.a
	end)
	local tops = {}
	for j = 1, min(4, #best) do
		local b = best[j]
		tops[#tops + 1] = fmt("k %+.1f off %.2f: 1st against %d, wall2 %d, wall3 %d of %d;"
			.. " by marker y: 1st against %s, wall3 %s (of %d)", b.k, b.o, b.a, b.w2, b.w3, b.n, b.a1y, b.w3y, #WALL_GROUNDS)
	end
	print("   best:\n     " .. table.concat(tops, "\n     "))
	print(fmt("   (%d drills, %.1f s)", sims, os.clock() - t0))
end

print()
print(fmt("2. Wall at the stake (%.1f, %.0f): marker o inward of it, spin k * %g rolling toward it", STAKE_X, STAKE_Y, CUT))
for _, loft in ipairs(LOFTS) do wallRun(loft) end
if not quick then
	-- a player who sees the wall moves the marker in one kubb width each time
	for _, loft in ipairs(LOFTS) do wallRun(loft, 0.07) end
end
