-- Tilted batons into groups of field kubbs: does tilting the baton's spin
-- axis a few degrees steer what happens after it hits the first kubb? A
-- headless, deterministic experiment on core/world (no randomness: every
-- throw's ground texture seed is fixed, so the same aim at two tilts meets
-- the same ground and only the tilt differs).
--
--   lua5.4 tools/tiltgroups.lua [--quick]
--
-- Groups as tools/compound.lua lays them out: two and three kubbs side by
-- side (across the throw), two one behind the other, and a cluster of five
-- (three side by side, two behind them in the gaps), at face gaps of 3, 7 and
-- 15 cm, centred on x = 0. The baton is thrown from y = 0 at loft 25 or 35
-- with the speed that lands its center D = 4 m (an advantage line) or 8 m (the
-- baseline) out, the group's front face `depth` short of that point, tumble
-- from core/swing's power for that speed. The aim (swivel) sweeps across the
-- group's width plus 6 cm either side. Every aim is thrown at each tilt
-- (world.launchBaton's tiltDeg: + tilts the top of the turning plane to the
-- right) and twice more at tilt 0 as controls: on another ground seed, and
-- aimed 5 mm to the right. Reported per tilt, over all groups and aims:
--   hit     share of throws whose first contact with a body was a kubb of the group
--   fell    kubbs toppled per hit (world.result's toppled: what the game scores)
--   P>=2, P>=3  share of hits that toppled two, three or more (P>=3 over the
--           triple and the cluster only)
--   defl    the baton's direction after the first hit against its direction
--           before it, degrees, + = right (from where it was 0.1 s after the hit)
--   batX    the baton's rest x minus where its line in would put it (m, + right)
--   kubX    mean x of the toppled kubbs, cm (+ = the right-hand side of the group)
--   chg     share of aims whose set of toppled kubbs differs from tilt 0's at the
--           same aim (among aims where either hit); the controls give the noise
--           floor: how often the outcome changes for reasons that are not tilt
--
-- --quick: one loft, one depth, coarser aim steps (about 10 s; the full run
-- about 1.5 min).

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
import "core/autothrow"
local world, swing, flight, autothrow = tw.world, tw.swing, tw.flight, tw.autothrow

local quick = false
for _, a in ipairs(arg) do
	if a == "--quick" then quick = true else error("unknown argument " .. a) end
end

local fmt = string.format
local atan, sqrt, deg, max, min, abs = math.atan, math.sqrt, math.deg, math.max, math.min, math.abs
local SIDE = 0.07
local TILTS = { -10, -7.5, -5, -2.5, 0, 2.5, 5, 7.5, 10 }
local DISTS = { 4, 8 }
local LOFTS = quick and { 30 } or { 25, 35 }
local DEPTHS = quick and { 0.15 } or { 0.05, 0.25 }
local GAPS = { 0.03, 0.07, 0.15 }
local AIM_STEP = quick and 0.04 or 0.02
local AIM_MARGIN = 0.06

-- Launch speed for a landing distance and the tumble the swing gives that power.
local function launch(D, loft)
	local sp = autothrow.speedFor(D, loft)
	local t = swing.tune
	local p = (sp / flight.loftBoost(loft, t.launchMax) - t.launchMin) / (t.launchMax - t.launchMin)
	p = max(0, min(1, p))
	return sp, t.tumbleMin + (t.tumbleMax - t.tumbleMin) * p
end

-- Kubb centers for a layout with its front face at y0; half = half width.
local function layout(kind, gap, y0)
	local P, pieces = SIDE + gap, {}
	local function add(x, y) pieces[#pieces + 1] = { id = "k" .. (#pieces + 1), kind = "kubb", x = x, y = y, yaw = 0 } end
	local yc = y0 + SIDE / 2
	if kind == "pair" then add(-P / 2, yc); add(P / 2, yc)
	elseif kind == "triple" then add(-P, yc); add(0, yc); add(P, yc)
	elseif kind == "inline" then add(0, yc); add(0, yc + P)
	elseif kind == "cluster" then add(-P, yc); add(0, yc); add(P, yc); add(-P / 2, yc + P); add(P / 2, yc + P)
	end
	local half = (kind == "inline") and SIDE / 2 or ((kind == "pair") and (P / 2 + SIDE / 2) or (P + SIDE / 2))
	return pieces, half
end

local LAYOUTS = {
	{ kind = "pair", label = "2 side by side" },
	{ kind = "triple", label = "3 side by side" },
	{ kind = "inline", label = "2 one behind" },
	{ kind = "cluster", label = "5 cluster (3+2)" },
}

-- One throw. Returns a record: hit, fell, set, defl, batX, kubX (nil when nothing fell).
local function throw(pieces, swivel, loft, sp, tr, tilt, seed)
	local w = world.new { surface = "grass", pieces = pieces, groundSeed = seed }
	local b = world.launchBaton(w, 0, 0, swivel, loft, sp, tr, tilt)
	local pvx, pvy = b.vx, b.vy
	local inH, hx, hy, hitT, defl
	while not world.isAtRest(w) do
		if not hitT then pvx, pvy = b.vx, b.vy end
		world.step(w)
		if not hitT and w.firstHit then
			hitT, inH, hx, hy = w.time, atan(pvx, pvy), b.x, b.y
		elseif hitT and not defl and w.time >= hitT + 0.1 then
			local dx, dy = b.x - hx, b.y - hy
			if dx * dx + dy * dy > 1e-6 then
				local d = atan(dx, dy) - inH
				if d > math.pi then d = d - 2 * math.pi elseif d < -math.pi then d = d + 2 * math.pi end
				defl = deg(d)
			else
				defl = 0
			end
		end
	end
	local r = world.result(w)
	local rec = { hit = r.firstHit ~= nil and r.firstHit.with:sub(1, 1) == "k" }
	local fell, xs, set = 0, 0, {}
	for _, id in ipairs(r.toppled) do
		fell = fell + 1
		xs = xs + r.bodies[id].x
		set[#set + 1] = id
	end
	table.sort(set)
	rec.fell, rec.set = fell, table.concat(set, ",")
	rec.kubX = fell > 0 and xs / fell or nil
	if rec.hit then
		rec.defl = defl
		-- rest x against the line in (the line through the hit point along the heading in)
		local s, c = math.sin(inH), math.cos(inH)
		local ex, ey = b.x - hx, b.y - hy
		rec.batX = ex * c - ey * s
	end
	return rec
end

local function newAcc()
	return { n = 0, hit = 0, fell = 0, f2 = 0, f3 = 0, n3 = 0, defl = 0, defl2 = 0, nd = 0, batX = 0,
		kubX = 0, nk = 0, chg = 0, nchg = 0 }
end

local function add(acc, rec, base, many)
	acc.n = acc.n + 1
	if rec.hit then
		acc.hit = acc.hit + 1
		acc.fell = acc.fell + rec.fell
		if rec.fell >= 2 then acc.f2 = acc.f2 + 1 end
		if many then
			acc.n3 = acc.n3 + 1
			if rec.fell >= 3 then acc.f3 = acc.f3 + 1 end
		end
		if rec.defl then
			acc.defl, acc.defl2, acc.nd = acc.defl + rec.defl, acc.defl2 + rec.defl * rec.defl, acc.nd + 1
		end
		acc.batX = acc.batX + (rec.batX or 0)
		if rec.kubX then acc.kubX, acc.nk = acc.kubX + rec.kubX, acc.nk + 1 end
	end
	if base and (rec.hit or base.hit) then
		acc.nchg = acc.nchg + 1
		if rec.set ~= base.set then acc.chg = acc.chg + 1 end
	end
end

local function pct(a, b) return b > 0 and fmt("%5.1f%%", 100 * a / b) or "    - " end

local function row(label, a)
	local dm = a.nd > 0 and a.defl / a.nd or 0
	local dsd = a.nd > 0 and sqrt(max(0, a.defl2 / a.nd - dm * dm)) or 0
	return fmt("  %-14s %6d %s  %4.2f %s %s  %+6.2f (%5.2f)  %+6.3f  %+5.2f  %s",
		label, a.n, pct(a.hit, a.n), a.hit > 0 and a.fell / a.hit or 0, pct(a.f2, a.hit), pct(a.f3, a.n3),
		dm, dsd, a.hit > 0 and a.batX / a.hit or 0, a.nk > 0 and 100 * a.kubX / a.nk or 0, pct(a.chg, a.nchg))
end

local t0, sims = os.clock(), 0
local byLayout = {}   -- [dist][layout label][gap][tilt] = acc
for _, D in ipairs(DISTS) do
	local accs, ctlSeed, ctlAim = {}, newAcc(), newAcc()
	for ti = 1, #TILTS do accs[ti] = newAcc() end
	byLayout[D] = {}
	-- paired slope sums: deflection and kubX against tilt
	local sx, sy, sxx, sxy, ns = 0, 0, 0, 0, 0
	local kx, ky, kxx, kxy, nk = 0, 0, 0, 0, 0
	local seedBase = 0
	for _, loft in ipairs(LOFTS) do
		local sp, tr = launch(D, loft)
		for _, depth in ipairs(DEPTHS) do
			for _, L in ipairs(LAYOUTS) do
				byLayout[D][L.label] = byLayout[D][L.label] or {}
				local many = L.kind == "triple" or L.kind == "cluster"
				for _, gap in ipairs(GAPS) do
					local cell = byLayout[D][L.label][gap] or {}
					byLayout[D][L.label][gap] = cell
					local y0 = D - depth
					local pieces, half = layout(L.kind, gap, y0)
					local reach = half + AIM_MARGIN
					local o = -reach
					while o <= reach + 1e-9 do
						seedBase = seedBase + 1
						local seed = 1000 + seedBase
						local ty = y0 + SIDE / 2
						local swivel = atan(o, ty)
						local recs = {}
						for ti, tilt in ipairs(TILTS) do
							recs[ti] = throw(pieces, swivel, loft, sp, tr, tilt, seed)
							sims = sims + 1
						end
						local base = recs[5]   -- tilt 0
						for ti, tilt in ipairs(TILTS) do
							local rec = recs[ti]
							add(accs[ti], rec, ti ~= 5 and base or nil, many)
							cell[ti] = cell[ti] or newAcc()
							add(cell[ti], rec, nil, many)
							if rec.hit and rec.defl then
								sx, sy, sxx, sxy, ns = sx + tilt, sy + rec.defl, sxx + tilt * tilt, sxy + tilt * rec.defl, ns + 1
							end
							if rec.hit and rec.kubX and L.kind ~= "inline" then
								kx, ky, kxx, kxy, nk = kx + tilt, ky + rec.kubX, kxx + tilt * tilt, kxy + tilt * rec.kubX, nk + 1
							end
						end
						add(ctlSeed, throw(pieces, swivel, loft, sp, tr, 0, seed + 500000), base, many)
						add(ctlAim, throw(pieces, atan(o + 0.005, ty), loft, sp, tr, 0, seed), base, many)
						sims = sims + 2
						o = o + AIM_STEP
					end
				end
			end
		end
	end
	print(fmt("Throwing line %d m out (lofts %s, depths %s m, aim step %.0f cm)", D, table.concat(LOFTS, "/"),
		table.concat(DEPTHS, "/"), AIM_STEP * 100))
	print("  tilt deg       throws   hit   fell  P>=2   P>=3    defl deg (sd)   batX m   kubX cm  chg vs 0")
	for ti, tilt in ipairs(TILTS) do print(row(fmt("%+5.1f", tilt), accs[ti])) end
	print(row("0, other grnd", ctlSeed))
	print(row("0, aim +5 mm", ctlAim))
	local slope = ns > 1 and (ns * sxy - sx * sy) / (ns * sxx - sx * sx) or 0
	local kslope = nk > 1 and (nk * kxy - kx * ky) / (nk * kxx - kx * kx) or 0
	print(fmt("  least squares over hits: defl %+.3f deg per deg of tilt; toppled kubbs' x %+.3f cm per deg (side-by-side and cluster)",
		slope, kslope * 100))
	print()
end

print("P(>=2 toppled | hit) by group and tilt (all lofts, depths and aims)")
local SHOW = { 1, 3, 5, 7, 9 }
local hdr = "  line  group             gap  "
for _, ti in ipairs(SHOW) do hdr = hdr .. fmt("  %+5.1f ", TILTS[ti]) end
print(hdr .. "   hits/tilt")
for _, D in ipairs(DISTS) do
	for _, L in ipairs(LAYOUTS) do
		for _, gap in ipairs(GAPS) do
			local cell = byLayout[D][L.label][gap]
			local s = fmt("  %2d m  %-16s %3.0fcm ", D, L.label, gap * 100)
			for _, ti in ipairs(SHOW) do s = s .. " " .. pct(cell[ti].f2, cell[ti].hit) .. " " end
			print(s .. fmt("   %d", cell[5].hit))
		end
	end
end
print(fmt("(%d throws, %.1f s)", sims, os.clock() - t0))
