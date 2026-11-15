-- Compound hits: can one baton take down two or three kubbs? A headless,
-- deterministic experiment on core/world (no randomness in the sweep).
--
--   lua5.4 tools/compound.lua [--quick] [--games 20] [--tilt 0]
--
-- 1. Reach: the launch speed and tumble core/swing gives each power and
--    where core/flight lands the baton at each loft, from the baseline.
-- 2. Sweep: for every power (0.6 to 1.0) and loft (20 to 35), a group of
--    standing kubbs is put where that throw comes down (its front face a
--    little short of the landing point) and the baton is aimed with the
--    swivel across the group, the aim point moved sideways in steps over the
--    group's width plus a margin. Layouts: two and three kubbs side by side
--    (across the throw) and two one behind the other, at face gaps of 3, 7,
--    15 and 30 cm. Reported: throws, hits (the baton touched a kubb of the
--    group), P(>=1 fell | hit), P(>=2 fell | hit), P(3 fell | hit) and
--    P(>=2 | hit) per power, where "fell" is world.result's toppled (what the
--    game scores). "down" also counts a kubb that came to rest more than 45
--    degrees from upright without toppling (lying ramped on a fallen one).
-- 3. Domino: kubb A tipped over its front edge toward kubb B (angular speed
--    about that edge; 4.1 rad/s is the least that tips it), or shoved by a
--    horizontal impulse at a height, and whether B falls.
-- 4. Spacing in matches: physics matches as tools/physmatch.lua plays them
--    (core/match, core/autothrow, core/world; raising by the engine's
--    default policies). At the first baton of every turn, the gap from each
--    standing field kubb to the nearest other standing kubb in that half,
--    and how many baton throws toppled two or more kubbs.
--
-- --quick: coarser aim steps, one depth and fewer games (about 10 s; the
-- full run takes about a minute). --tilt: the swing's tilt for the sweep
-- (degrees; 0 = clean end over end, up to 30 is legal).

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end

import "core/world"
import "core/swing"
import "core/flight"
import "core/rect"
import "core/match"
import "core/autothrow"
import "core/outcome"
local world, swing, flight, rect, match, autothrow = tw.world, tw.swing, tw.flight, tw.rect, tw.match, tw.autothrow
local STANDING_COS = tw.outcome.tune.standingCos

local quick, games, tilt = false, nil, 0
local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--quick" then quick = true
	elseif a == "--games" then games = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--tilt" then tilt = tonumber(arg[i + 1]); i = i + 1
	else error("unknown argument " .. a) end
	i = i + 1
end
games = games or (quick and 4 or 20)

local fmt = string.format
local atan = math.atan
local POWERS = { 0.6, 0.7, 0.8, 0.9, 1.0 }
local LOFTS = { 20, 25, 30, 35 }
local GAPS = { 0.03, 0.07, 0.15, 0.30 }
local SIDE = 0.07                                  -- kubb side (DESIGN 2)
local AIM_STEP = quick and 0.04 or 0.02           -- m between aim points across the group
local AIM_MARGIN = 0.06                            -- m beyond the group's outer faces
local DEPTHS = quick and { 0.15 } or { 0.05, 0.25 } -- m the front face stands short of the landing point

-- The old swing's mapping from power (0..1) to launch speed (4.0 to 9.2 m/s,
-- the sweep this tool measured with), and the plan's tumble for that speed.
local function launch(p)
	local speed = 4.0 + (9.2 - 4.0) * p
	return speed, tw.plan.tumbleFor(speed)
end

-- ---------------------------------------------------------------------------
-- 1. Reach

print("1. Reach: power -> launch m/s, tumble rad/s; landing distance (m) by loft")
for _, p in ipairs(POWERS) do
	local sp, tr = launch(p)
	local parts = {}
	for _, loft in ipairs(LOFTS) do
		local _, ly = flight.predict(0, 0, 0, loft, sp)
		parts[#parts + 1] = fmt("%d deg %.2f", loft, ly)
	end
	print(fmt("  p %.1f  %.2f m/s  %.2f rad/s  | %s", p, sp, tr, table.concat(parts, "  ")))
end

-- ---------------------------------------------------------------------------
-- 2. Sweep

-- Down at rest: toppled, or resting more than 45 degrees from upright.
local function isDown(rb)
	if rb.toppled then return true end
	local r33 = 1 - 2 * (rb.qx * rb.qx + rb.qy * rb.qy)
	return r33 < STANDING_COS and r33 > -STANDING_COS
end

-- Kubb centers for a layout at front face y0, group centered on x = 0.
local function layout(kind, gap, y0)
	local pieces, pitchStep = {}, SIDE + gap
	local n = (kind == "triple") and 3 or 2
	for k = 1, n do
		local x, y
		if kind == "inline" then
			x, y = 0, y0 + SIDE / 2 + (k - 1) * pitchStep
		else
			x, y = (k - (n + 1) / 2) * pitchStep, y0 + SIDE / 2
		end
		pieces[k] = { id = "k" .. k, kind = "kubb", x = x, y = y, yaw = 0 }
	end
	local half = (kind == "inline") and SIDE / 2 or (n * SIDE + (n - 1) * gap) / 2
	return pieces, n, half
end

local LAYOUTS = {
	{ kind = "pair", label = "2 side by side" },
	{ kind = "triple", label = "3 side by side" },
	{ kind = "inline", label = "2 one behind the other" },
}

local t0 = os.clock()
local sims = 0
print()
print(fmt("2. Sweep: aim step %.0f cm, depths %s m short of landing, %d powers x %d lofts, tilt %g",
	AIM_STEP * 100, table.concat(DEPTHS, "/"), #POWERS, #LOFTS, tilt))
print("                                         toppled (scored)     | down          | toppled P>=2 by power")
print("  layout                  gap  throws  hit  P>=1   P>=2   P3   | P>=2   P3     | 0.6    0.7    0.8    0.9    1.0")
for _, L in ipairs(LAYOUTS) do
	for _, gap in ipairs(GAPS) do
		local thrown, hit, f1, f2, f3, d2, d3 = 0, 0, 0, 0, 0, 0, 0
		local hp, f2p = {}, {}
		for pi, p in ipairs(POWERS) do
			hp[pi], f2p[pi] = 0, 0
			local sp, tr = launch(p)
			for _, loft in ipairs(LOFTS) do
				local _, D = flight.predict(0, 0, 0, loft, sp)
				for _, depth in ipairs(DEPTHS) do
					local y0 = D - depth
					local pieces, n, half = layout(L.kind, gap, y0)
					local reach = half + AIM_MARGIN
					local o = -reach
					while o <= reach + 1e-9 do
						local w = world.new { surface = "grass", pieces = pieces }
						world.launchBaton(w, 0, 0, atan(o, y0 + SIDE / 2), loft, sp, tr, tilt)
						world.run(w)
						sims = sims + 1
						local r = world.result(w)
						thrown = thrown + 1
						local fh = r.firstHit
						if fh and fh.with:sub(1, 1) == "k" then
							hit, hp[pi] = hit + 1, hp[pi] + 1
							local fell = #r.toppled
							if fell >= 1 then f1 = f1 + 1 end
							if fell >= 2 then f2, f2p[pi] = f2 + 1, f2p[pi] + 1 end
							if fell >= 3 then f3 = f3 + 1 end
							local down = 0
							for k = 1, n do if isDown(r.bodies["k" .. k]) then down = down + 1 end end
							if down >= 2 then d2 = d2 + 1 end
							if down >= 3 then d3 = d3 + 1 end
						end
						o = o + AIM_STEP
					end
				end
			end
		end
		local function pct(a, b) return b > 0 and fmt("%5.1f%%", 100 * a / b) or "    - " end
		local byP = {}
		for pi = 1, #POWERS do byP[pi] = pct(f2p[pi], hp[pi]) end
		local tri = L.kind == "triple"
		print(fmt("  %-22s %3.0fcm %5d %5d %s %s %s | %s %s | %s", L.label, gap * 100, thrown, hit,
			pct(f1, hit), pct(f2, hit), tri and pct(f3, hit) or "    - ",
			pct(d2, hit), tri and pct(d3, hit) or "    - ", table.concat(byP, " ")))
	end
end
print(fmt("  (%d throws, %.1f s)", sims, os.clock() - t0))

-- ---------------------------------------------------------------------------
-- 3. Domino

-- Two kubbs on the y axis away from the stakes; A gets the motion, B is gap behind.
local function domino(gap, setA)
	local w = world.new { surface = "grass", pieces = {
		{ id = "A", kind = "kubb", x = 0, y = 2.0 },
		{ id = "B", kind = "kubb", x = 0, y = 2.0 + SIDE + gap },
	} }
	local a = w.byId.A
	world.wake(a)
	setA(a)
	world.run(w)
	local r = world.result(w)
	local function mark(id)
		local rb = r.bodies[id]
		return rb.toppled and "T" or (isDown(rb) and "d" or "-")
	end
	return mark("A"), mark("B")
end

-- Tipped about its bottom front edge (toward B) at om rad/s (as the
-- domino test in tests/lua/test_physics.lua).
local function tip(om)
	return function(a) a.wx, a.vy, a.vz = -om, om * a.hz, om * a.hy end
end
-- A horizontal impulse toward B at height h above the ground, giving the
-- center speed v.
local function shove(v, h)
	return function(a)
		local J = v * a.m
		local rz = h - a.hz
		a.vy = v
		local tx = -rz * J           -- (r x J).x with r = (0, -hy, rz), J = (0, J, 0)
		a.wx, a.wy, a.wz = a.i11 * tx, a.i12 * tx, a.i13 * tx
	end
end

print()
print("3. Domino: does B (gap behind A) fall? A/B: T toppled, d down (rests over 45 deg, not toppled), - standing")
local hdr = "  push                        "
for _, gap in ipairs({ 0.03, 0.07, 0.15 }) do hdr = hdr .. fmt("  %2.0f cm", gap * 100) end
print(hdr)
local function row(label, setA)
	local s = fmt("  %-28s", label)
	for _, gap in ipairs({ 0.03, 0.07, 0.15 }) do
		local fa, fb = domino(gap, setA)
		s = s .. fmt("  %s/%s ", fa, fb)
	end
	print(s)
end
for _, om in ipairs({ 4.5, 6, 9, 12 }) do row(fmt("tip %.1f rad/s", om), tip(om)) end
for _, h in ipairs({ 0.075, 0.13 }) do
	for _, v in ipairs({ 0.5, 1.0, 2.0, 3.0 }) do row(fmt("shove %.1f m/s at %.0f cm", v, h * 100), shove(v, h)) end
end

-- ---------------------------------------------------------------------------
-- 4. Spacing in physics matches

local function standingKubbs(g, half)
	local out = {}
	for _, k in ipairs(g:onPitch()) do
		if k.half == half and k.pose.standing and not k.pose.onTop then out[#out + 1] = k end
	end
	return out
end

local BUCKETS = { 0.005, 0.03, 0.07, 0.15, 0.30 }
local hist, nSamples = {}, 0
for b = 1, #BUCKETS + 1 do hist[b] = 0 end
local minGap = math.huge
local batons, doubles, fieldDoubles = 0, 0, 0
t0 = os.clock()
for gi = 1, games do
	local m = match.new { start = { year = 2026, month = 11, day = 20, hour = 9, min = 0 }, first = (gi % 2 == 0) and "B" or "A" }
	local r = autothrow.rng(7919 + gi)
	local lastTurn = -1
	while not match.over(m) and m.game.turn <= 40 do
		local s = match.setup(m)
		if not s then break end
		local g = m.game
		if s.kind == "baton" and not s.kingShot and g.turn ~= lastTurn then
			lastTurn = g.turn
			local half = (s.side == "A") and "B" or "A"
			local ks = standingKubbs(g, half)
			for _, k in ipairs(ks) do
				if k.kind == "field" then
					local rk = tw.raising.kubbRect(k.pose)
					local best = math.huge
					for _, o in ipairs(ks) do
						if o ~= k then
							local d = rect.distance(rk, tw.raising.kubbRect(o.pose))
							if d < best then best = d end
						end
					end
					if best < math.huge then
						local b = 1
						while b <= #BUCKETS and best >= BUCKETS[b] do b = b + 1 end
						hist[b] = hist[b] + 1
						nSamples = nSamples + 1
						if best < minGap then minGap = best end
					end
				end
			end
		end
		local a = autothrow.choose(s, r)
		local pieces = match.worldPieces and match.worldPieces(s) or s.pieces
		local w = world.new { surface = "grass", pieces = pieces }

		autothrow.launch(w, s, a)
		world.run(w)
		local res = world.result(w)
		if s.kind == "baton" then
			batons = batons + 1
			local fieldDown = 0
			for _, id in ipairs(res.toppled) do
				local k = g.kubbs[id]
				if k and k.kind == "field" then fieldDown = fieldDown + 1 end
			end
			if #res.toppled >= 2 then doubles = doubles + 1 end
			if fieldDown >= 2 then fieldDoubles = fieldDoubles + 1 end
		end
		match.resolve(m, res, not a.legal)
	end
end
print()
print(fmt("4. Spacing in %d physics matches (%.1f s): standing field kubb -> nearest standing kubb in its half,", games, os.clock() - t0))
print("   sampled at the first baton of each turn")
local labels = { "touching (<0.5 cm)", "0.5-3 cm", "3-7 cm", "7-15 cm", "15-30 cm", ">=30 cm" }
for b = 1, #BUCKETS + 1 do
	print(fmt("  %-20s %5d  %5.1f%%", labels[b], hist[b], nSamples > 0 and 100 * hist[b] / nSamples or 0))
end
print(fmt("  samples %d, smallest gap %.1f cm", nSamples, minGap < math.huge and minGap * 100 or -1))
print(fmt("  baton throws %d: >=2 kubbs toppled %d (%.1f%%), >=2 field kubbs %d", batons, doubles,
	batons > 0 and 100 * doubles / batons or 0, fieldDoubles))
