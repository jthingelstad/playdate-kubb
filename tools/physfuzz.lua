-- The physics defect finder (AGENTS.md "Physics fuzz"). Each iteration draws
-- one seeded throw the game could make, runs it to rest through the game's
-- own path (core/autothrow's choose and launch, core/world) and checks the
-- invariants of tools/physcheck.lua after every step; then the same throw
-- mirrored, and at half the time step. Failures are grouped into clusters and
-- ranked by how often a realistic throw meets them, each with a repro.
--
--   lua5.4 tools/physfuzz.lua [--n 2000] [--seed 1] [--surface Grass|Sand|Snow]
--     [--only energy,penetration,rest,finite,mirror,dt,aim] [--kind baton|kubb] [-v]
--   lua5.4 tools/physfuzz.lua --repro <seed>:<i> [--surface ...] [--dump file] [--every 1] [--case]
--   lua5.4 tools/physfuzz.lua --selftest [--n 40]
--   lua5.4 tools/physfuzz.lua --grid drill|tilt [--seeds 24] [--surface ...]
--   --set world.name=value (or collide., check., drill., plan.) tries a tunable;
--   --dist prints the distribution of each check's worst value a throw (set
--   the check's thresholds to 0 to see every throw's)
--
-- --repro re-runs iteration i of seed's run verbosely (the throw is the same
-- whatever --n, --only or --kind were). --dump writes its trace in
-- tools/physdump.lua's format, every --every steps. --case prints it as a
-- pinned case for tests/lua/physcases/. --selftest checks that the monitor
-- and the replayed launch leave every throw bit for bit the same.
--
-- What a throw is: a realism class (clean: no mistakes; real: the computer at
-- club, scale 1; loose: beginner; wild: beginner at 2.5 times the mistakes and
-- a random tilt, tumble and speed), a projectile (a baton at field kubbs, at
-- base kubbs or at the king, or a drilled kubb), a layout of the far half (a
-- lone field kubb, rows along or across the throw at gaps of 0 to 7 cm, a
-- cluster with some lying, a kubb leaning on a lying one, lying debris and
-- batons), the computer's stance and arc, varied, and the B + left/right
-- control as the throw scene sets it (a drill's spin taps uniform over
-- -spinSteps..+spinSteps; a baton's tilt 0 half the time, else up to
-- tiltMaxDeg either way), passed to plan.solve and plan.launch as in play.
-- Clusters keep spun drills and tilted batons on rows of their own. Layouts with anything
-- lying or leaning are run to rest first, so the pitch is a settled one.
-- An aim iteration instead throws the plan's clean baton at a lone kubb from
-- 3, 5.27 or 8 m (tools/aimsweep.lua's set-up) for the claimed hit rates.
--
-- --grid sweeps a control exhaustively instead (doGrid below): every spin
-- tap (drill) or tilt (baton at a lone kubb), at a few releases and
-- distances, on each surface, --seeds throws a cell; each check per cell,
-- and per step the run-on, its sideways part and the rest from the mark
-- (drillscatter 3's measures), with whether the sideways part is monotonic
-- in the control and mirrored left against right.

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end

import "core/tw"
import "core/world"
import "core/autothrow"
import "core/throwplan"
import "core/outcome"
import "core/quat"
local world, autothrow, plan, outcome, quat, body = tw.world, tw.autothrow, tw.plan, tw.outcome, tw.quat, tw.body
local physcheck = assert(loadfile(here .. "/physcheck.lua"))()
local fmt, sqrt, pi = string.format, math.sqrt, math.pi

local n, seed, surface, verbose = 2000, 1, "grass", false
local only, kindOnly, repro, dumpPath, every, asCase, selftest = nil, nil, nil, nil, 1, false, false
local top = 20
local sets = {}
local dist = false
local grid, gridSeeds, surfaceGiven = nil, 24, false
do
	local i = 1
	while i <= #arg do
		local a = arg[i]
		if a == "--n" then n = tonumber(arg[i + 1]); i = i + 1
		elseif a == "--seed" then seed = tonumber(arg[i + 1]); i = i + 1
		elseif a == "--surface" then surface, surfaceGiven = string.lower(arg[i + 1]), true; i = i + 1
		elseif a == "--only" then
			only = {}
			for c in arg[i + 1]:gmatch("[^,]+") do only[c] = true end
			i = i + 1
		elseif a == "--kind" then kindOnly = arg[i + 1]; i = i + 1
		elseif a == "--repro" then repro = arg[i + 1]; i = i + 1
		elseif a == "--dump" then dumpPath = arg[i + 1]; i = i + 1
		elseif a == "--every" then every = tonumber(arg[i + 1]); i = i + 1
		elseif a == "--top" then top = tonumber(arg[i + 1]); i = i + 1
		elseif a == "--set" then sets[#sets + 1] = arg[i + 1]; i = i + 1
		elseif a == "--dist" then dist = true
		elseif a == "--grid" then grid = arg[i + 1]; i = i + 1
		elseif a == "--seeds" then gridSeeds = tonumber(arg[i + 1]); i = i + 1
		elseif a == "--case" then asCase = true
		elseif a == "--selftest" then selftest = true
		elseif a == "-v" then verbose = true
		else error("unknown argument " .. a) end
		i = i + 1
	end
end
assert(world.surfaces[surface], "unknown surface " .. surface)
-- --set world.name=value, collide.name=value or check.name=value: try a tunable
for _, kv in ipairs(sets) do
	local mod, key, val = kv:match("^(%a+)%.([%w_]+)=(.+)$")
	local tabs = { world = world.tune, collide = tw.collide.tune, check = physcheck.tune, drill = tw.drill.tune,
		plan = plan.tune }
	assert(mod and tabs[mod] and tabs[mod][key] ~= nil, "--set world|collide|check|drill|plan.name=value: " .. kv)
	tabs[mod][key] = tonumber(val)
end
local function on(check) return not only or only[check] end
local withControls

-- ---------- the draw ----------

local CLASSES = {
	{ name = "clean", p = 0.15, weight = 1, scale = 0, level = "club" },
	{ name = "real", p = 0.55, weight = 1, scale = 1, level = "club" },
	{ name = "loose", p = 0.15, weight = 0.5, scale = 1, level = "beginner" },
	{ name = "wild", p = 0.15, weight = 0.1, scale = 2.5, level = "beginner", wild = true },
}
local AIM_SHARE = 0.06
local AIM_D = { 3, 5.27, 8 }
local AIM_CLAIM = { [3] = nil, [5.27] = 1.0, [8] = 0.98 }   -- AGENTS.md "Aimed through the piece"
local AIM_TUMBLE = { 0.8, 0.9, 1.0, 1.1, 1.2 }
local GAPS = { 0, 0.005, 0.01, 0.03, 0.07 }

local function pick(r, list)
	local u, acc = r.next(), 0
	for _, c in ipairs(list) do
		acc = acc + c.p
		if u < acc then return c end
	end
	return list[#list]
end

local function standingQ(yaw) return math.cos(yaw / 2), 0, 0, math.sin(yaw / 2) end
local function lyingQ(angle) return outcome.quatOf { standing = false, angle = angle } end
local function batonQ(yaw)
	local qw, qx, qy, qz = quat.fromAxisAngle(0, 0, 1, yaw)
	local tw_, tx, ty, tz = quat.fromAxisAngle(1, 0, 0, -pi / 2)
	return quat.mul(qw, qx, qy, qz, tw_, tx, ty, tz)
end

-- A layout of the far half (Team B's, y 4 to 8) for projectile `proj`.
-- Pieces carry the world's pose (qw..qz, z when settled) and the setup's
-- fields (role, half, toppled, pose.angle).
local function drawLayout(r, proj)
	local L = { pieces = {}, kind = "none", lying = false }
	local placed = {}
	local function free(x, y, rad)
		if x < -2.3 or x > 2.3 or y < 4.1 or y > 7.6 then return false end
		for _, q in ipairs(placed) do
			local dx, dy = x - q.x, y - q.y
			if dx * dx + dy * dy < (rad + q.rad) ^ 2 then return false end
		end
		return true
	end
	local function add(p, rad)
		L.pieces[#L.pieces + 1] = p
		if rad then placed[#placed + 1] = { x = p.x, y = p.y, rad = rad } end
		return p
	end
	local function standing(id, role, x, y, yaw)
		local qw, qx, qy, qz = standingQ(yaw or 0)
		return add({ id = id, kind = "kubb", role = role, half = "B", x = x, y = y, qw = qw, qx = qx, qy = qy,
			qz = qz, toppled = false, pose = { x = x, y = y, standing = true, angle = yaw or 0 } }, nil)
	end
	local function lying(id, role, x, y, angle)
		local qw, qx, qy, qz = lyingQ(angle)
		L.lying = true
		return add({ id = id, kind = "kubb", role = role, half = "B", x = x, y = y, qw = qw, qx = qx, qy = qy,
			qz = qz, toppled = true, pose = { x = x, y = y, standing = false, angle = angle } }, nil)
	end
	local fid = 0
	local function nextF() fid = fid + 1; return "f" .. fid end
	-- base kubbs, each gone (knocked down earlier) one time in five
	if proj ~= "king" then
		local any = false
		for j = 1, 5 do
			if r.next() >= 0.2 or (j == 5 and not any) then
				any = true
				standing("b" .. j, "base", j - 3, 8, 0)
				placed[#placed + 1] = { x = j - 3, y = 8, rad = 0.06 }
			end
		end
	end
	standing("king", "king", 0, 4, 0).kind = "king"
	placed[#placed + 1] = { x = 0, y = 4, rad = 0.09 }
	if proj == "field" or proj == "toss" then
		local u = r.next()
		if proj == "toss" then
			-- the turn's group by a basket, lying, and now and then a standing
			-- field kubb from an earlier turn
			local side = r.next() < 0.5 and -1 or 1
			local bx, by = side * autothrow.tune.basketX, autothrow.tune.basketY
			local k = (u < 0.3) and 0 or math.floor(1 + r.next() * 4)
			L.kind = k == 0 and "empty" or ("group " .. k)
			for _ = 1, k do
				for _ = 1, 30 do
					local x, y = bx + r.uniform(-0.35, 0.35), by + r.uniform(-0.3, 0.4)
					if free(x, y, 0.085) then
						placed[#placed + 1] = { x = x, y = y, rad = 0.085 }
						lying(nextF(), "field", x, y, r.uniform(0, pi))
						break
					end
				end
			end
			if r.next() < 0.3 then
				for _ = 1, 30 do
					local x, y = r.uniform(-2, 2), r.uniform(4.3, 7)
					if free(x, y, 0.06) then
						placed[#placed + 1] = { x = x, y = y, rad = 0.06 }
						standing(nextF(), "field", x, y, r.uniform(0, pi / 2))
						L.kind = L.kind .. " + standing"
						break
					end
				end
			end
		elseif u < 0.3 then
			L.kind = "lone"
			local x, y = r.uniform(-2, 2), r.uniform(4.3, 7.2)
			placed[#placed + 1] = { x = x, y = y, rad = 0.06 }
			standing(nextF(), "field", x, y, r.uniform(0, pi / 2))
		elseif u < 0.5 or u < 0.65 then
			-- a row: along the throw (end on) or across it, square, at one gap
			local along = u < 0.5
			local k = math.floor(2 + r.next() * 3)
			local gap = GAPS[math.floor(1 + r.next() * #GAPS)]
			L.kind = fmt("row %s %d gap %.0f mm", along and "along" or "across", k, gap * 1000)
			local x0, y0 = r.uniform(-1.8, 1.8), r.uniform(4.4, 6.6)
			for j = 1, k do
				local x, y = x0, y0
				if along then y = y0 + (j - 1) * (0.07 + gap) else x = x0 + (j - 1) * (0.07 + gap) end
				placed[#placed + 1] = { x = x, y = y, rad = 0.06 }
				standing(nextF(), "field", x, y, 0)
			end
		elseif u < 0.85 then
			-- a cluster of 3 to 6, some lying
			local k = math.floor(3 + r.next() * 4)
			L.kind = "cluster " .. k
			local cx, cy = r.uniform(-1.6, 1.6), r.uniform(4.6, 6.8)
			for _ = 1, k do
				for _ = 1, 40 do
					local lie = r.next() < 0.3
					local rad = lie and 0.085 or 0.05
					local x, y = cx + r.uniform(-0.3, 0.3), cy + r.uniform(-0.3, 0.3)
					if free(x, y, rad) then
						placed[#placed + 1] = { x = x, y = y, rad = rad }
						if lie then lying(nextF(), "field", x, y, r.uniform(0, pi))
						else standing(nextF(), "field", x, y, r.uniform(0, pi / 2)) end
						break
					end
				end
			end
		else
			-- a standing kubb leaning on a lying one (along the throw)
			L.kind = "leaning"
			local x, y = r.uniform(-1.8, 1.8), r.uniform(4.8, 7)
			placed[#placed + 1] = { x = x, y = y - 0.08, rad = 0.2 }
			lying(nextF(), "field", x, y, 0)
			local th = math.rad(r.uniform(8, 22))
			local hy, hz = 0.035, 0.075
			local yf = y - 0.035 - 0.07 * math.tan(th)
			local yc = yf - hy * math.cos(th) + hz * math.sin(th)
			local zc = hy * math.sin(th) + hz * math.cos(th)
			local id = nextF()
			add({ id = id, kind = "kubb", role = "field", half = "B", x = x, y = yc, z = zc,
				qw = math.cos(-th / 2), qx = math.sin(-th / 2), qy = 0, qz = 0, toppled = false,
				pose = { x = x, y = yc, standing = true, angle = 0 } })
			L.lying = true
			if r.next() < 0.5 then
				-- and a second standing in line behind the lying one
				local x2, y2 = x, y + 0.13 + r.uniform(0, 0.1)
				if free(x2, y2, 0.05) then
					placed[#placed + 1] = { x = x2, y = y2, rad = 0.05 }
					standing(nextF(), "field", x2, y2, 0)
				end
			end
		end
	else
		L.kind = proj == "king" and "king" or "base"
	end
	-- debris: lying kubbs and batons from earlier throws
	local nd = math.floor(r.next() * 4)
	for j = 1, nd do
		for _ = 1, 30 do
			local x, y = r.uniform(-2.2, 2.2), r.uniform(4.2, 7.8)
			if free(x, y, 0.16) then
				placed[#placed + 1] = { x = x, y = y, rad = 0.16 }
				if r.next() < 0.3 then
					local qw, qx, qy, qz = batonQ(r.uniform(0, pi))
					add({ id = "x" .. j, kind = "baton", role = "debris", x = x, y = y, qw = qw, qx = qx, qy = qy, qz = qz })
				else
					lying("d" .. j, "debris", x, y, r.uniform(0, pi))
				end
				L.lying = true
				break
			end
		end
	end
	return L
end

-- Run every piece of a layout with something lying or leaning to rest, so
-- the throw meets a settled pitch. Returns false when it does not settle.
local function settle(L)
	if not L.lying then return true end
	local w = physcheck.newWorld(surface, L.pieces, { texture = false, stakes = false })
	for i = 1, w.n do world.wake(w.bodies[i]) end
	world.run(w)
	if not world.isAtRest(w) then return false end -- (world.run stops just short of maxTime)
	for _, p in ipairs(L.pieces) do
		local b = w.byId[p.id]
		p.x, p.y, p.z, p.qw, p.qx, p.qy, p.qz = b.x, b.y, b.z, b.qw, b.qx, b.qy, b.qz
		if p.kind ~= "baton" then
			p.toppled = b.toppled
			p.pose = { x = b.x, y = b.y, standing = not b.toppled, angle = math.atan(b.r23, b.r13) }
		end
	end
	return true
end

-- Call fn(...) with the throw scene's B + left/right control set as in play:
-- core/autothrow plans and launches with none, so plan.solve gets q.spin (a
-- drill's taps: drill.solveAt and drill.slideFor see it) and plan.launch
-- opts.spin and opts.tilt, exactly as scenes/throw.lua passes s.spin and
-- s.tilt. Returns pcall's results.
function withControls(spin, tilt, fn, ...)
	local solve0, launch0 = plan.solve, plan.launch
	plan.solve = function(q, out)
		q.spin = q.projectile == "kubb" and spin or 0
		return solve0(q, out)
	end
	plan.launch = function(sol, sw, o, out)
		local kubb = o.projectile == "kubb"
		o.spin, o.tilt = kubb and spin or 0, kubb and 0 or tilt
		return launch0(sol, sw, o, out)
	end
	local res = table.pack(pcall(fn, ...))
	plan.solve, plan.launch = solve0, launch0
	return table.unpack(res, 1, res.n)
end

-- Iteration i of the run: everything about the throw, drawn from its own
-- stream, so --repro seed:i redraws it alone.
local function drawThrow(i)
	local r = plan.rng(seed * 1000003 + i)
	local T = { i = i, rng = r }
	if r.next() < AIM_SHARE then
		T.aim = true
		T.cls = CLASSES[1]
		T.proj, T.projectile = "aim", "baton"
		T.d = AIM_D[math.floor(1 + r.next() * #AIM_D)]
		T.tumble = AIM_TUMBLE[math.floor(1 + r.next() * #AIM_TUMBLE)]
		T.groundSeed = math.floor(1 + r.next() * 1e6)
		T.layoutKind = fmt("aim %.2f m", T.d)
		T.pieces = { { id = "k", kind = "kubb", x = 0, y = T.d } }
		T.stakes = false
		local st = physcheck.planState({ px = 0, py = 0, tx = 0, ty = T.d, release = plan.tune.arc.field,
			level = "club", aimZ = plan.aimZFor("kubb") }, T.tumble)
		st.groundSeed = T.groundSeed
		T.state = st
		return T
	end
	T.cls = pick(r, CLASSES)
	local u = r.next()
	T.proj = (u < 0.2) and "toss" or ((u < 0.6) and "field" or ((u < 0.88) and "base" or "king"))
	T.projectile = T.proj == "toss" and "kubb" or "baton"
	local L = drawLayout(r, T.proj)
	if not settle(L) then
		T.unsettled = true
		return T
	end
	T.layoutKind, T.pieces, T.stakes = L.kind, L.pieces, true
	-- the setup core/autothrow reads
	local s = { pieces = L.pieces, lineY = 0, side = "A", surface = surface }
	local arcKey
	if T.proj == "toss" then
		s.kind, s.kubb, s.of = "toss", "t1", math.floor(1 + r.next() * 6)
		arcKey = "drill"
	else
		s.kind, s.batonId = "baton", "baton"
		local targets, kingShot = {}, false
		for _, p in ipairs(L.pieces) do
			if p.role == "field" and not p.toppled then targets[#targets + 1] = p.id end
		end
		if #targets == 0 then
			for _, p in ipairs(L.pieces) do
				if p.role == "base" and not p.toppled then targets[#targets + 1] = p.id end
			end
		end
		if #targets == 0 then targets, kingShot = { "king" }, true end
		s.targets, s.kingShot = targets, kingShot
		local near = 8
		for _, id in ipairs(targets) do
			for _, p in ipairs(L.pieces) do if p.id == id and p.y < near then near = p.y end end
		end
		if kingShot then
			s.forwardY, arcKey = 0, "king"
		elseif L.pieces[1] and T.proj == "field" and near < 8 then
			s.forwardY, arcKey = math.max(0, near - r.uniform(2, 5.5)), "field"
			for _, id in ipairs(targets) do if id:sub(1, 1) == "b" then arcKey = "base" end end
		else
			s.forwardY, arcKey = (r.next() < 0.7) and 0 or r.uniform(0, 3), "base"
		end
	end
	T.setup = s
	-- the arc: the default one most of the time, else moved
	local arc0 = plan.tune.arc[arcKey]
	local arc = arc0
	if r.next() < 0.4 then
		local spread = (arcKey == "drill") and 30 or 45
		arc = math.max(plan.tune.releaseMinDeg, math.min(plan.tune.releaseMaxDeg, arc0 + r.uniform(-spread, spread)))
	end
	T.arc = arc
	-- the B + left/right control, from a stream of its own (so the layout and
	-- the swing are the same whatever it is): a drill's spin taps uniform over
	-- -spinSteps..+spinSteps, a baton's tilt 0 half the time, else uniform
	-- over the taps either way up to tiltMaxDeg
	local rc = plan.rng(seed * 7919 + i * 104729 + 17)
	local pt = plan.tune
	if T.proj == "toss" then
		T.spin = math.floor(rc.next() * (2 * pt.spinSteps + 1)) - pt.spinSteps
	elseif rc.next() >= 0.5 then
		local taps = pt.tiltMaxDeg // pt.tiltStepDeg
		local k = 1 + math.floor(rc.next() * taps)
		T.tilt = (rc.next() < 0.5 and -k or k) * pt.tiltStepDeg
	end
	plan.tune.arc[arcKey] = arc
	local ok, a = withControls(T.spin or 0, T.tilt or 0, autothrow.choose, s, r, T.cls.scale, T.cls.level)
	plan.tune.arc[arcKey] = arc0
	if not ok then error(a) end
	if T.cls.wild then
		a.speed = a.speed * r.uniform(0.85, 1.15)
		if not a.drill then
			a.tumbleRate = a.tumbleRate * r.uniform(0.5, 1.6)
			a.tilt = (a.tilt or 0) + r.uniform(-25, 25)
		end
	end
	T.a = a
	return T
end

-- ---------- running one throw ----------

local neighbourhood
local function verdictOf(T, res, w)
	local ids = {}
	for _, id in ipairs(res.toppled) do ids[#ids + 1] = id end
	table.sort(ids)
	local v = table.concat(ids, ",")
	if T.projectile == "kubb" and not T.aim then
		local b = res.bodies.t1
		local inside = b and b.y >= 4 and b.y <= 8 and b.x >= -2.5 and b.x <= 2.5
		v = v .. (inside and " |in" or " |out")
	end
	return v == "" and "-" or v
end

-- Run the reference throw (the game's path) with the monitor.
local function runReference(T, each)
	local w
	if T.aim then
		w = physcheck.newWorld(surface, T.pieces, { groundSeed = T.groundSeed, stakes = false })
		physcheck.launch(w, T.state)
	else
		w = world.new { surface = surface, pieces = T.pieces }
		autothrow.launch(w, T.setup, T.a)
		T.state = physcheck.capture(w)
	end
	local b = w.projectile
	T.v0 = sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
	local res, findings = physcheck.run(w, { launchSpeed = T.v0 }, each)
	return res, findings, w
end

-- The same launch replayed into a fresh world: opts.texture, opts.mirror,
-- opts.scale, opts.dt (the step for this run).
local function runVariant(T, opts)
	local dt0 = world.tune.dt
	if opts.dt then world.tune.dt = opts.dt end
	local w = physcheck.newWorld(surface, T.pieces, { groundSeed = T.state.groundSeed, stakes = T.stakes,
		texture = opts.texture, mirror = opts.mirror })
	physcheck.launch(w, T.state, opts)
	world.run(w)
	world.tune.dt = dt0
	local res = world.result(w)
	return verdictOf(T, res, w), res, w
end

-- The verdict most of a throw's neighbourhood gives (its launch velocity
-- and spin times 1 + k for each k in NEAR) and how many of them give it.
local NEAR = { -3e-3, -1e-3, -1e-4, 0, 1e-4, 1e-3, 3e-3 }
local STABLE = 6
function neighbourhood(T, opts)
	local count, best, bestN = {}, nil, 0
	for _, k in ipairs(NEAR) do
		local o = {}
		for key, v in pairs(opts) do o[key] = v end
		o.scale = 1 + k
		local v = runVariant(T, o)
		count[v] = (count[v] or 0) + 1
		if count[v] > bestN then best, bestN = v, count[v] end
	end
	return best, bestN
end

-- One iteration: { T, findings (check failures), notes (informational) }.
local function iterate(i)
	local T = drawThrow(i)
	if T.unsettled then return { T = T, skipped = true } end
	local out = { T = T, fails = {}, infos = {} }
	local res, findings = runReference(T)
	T.verdict = verdictOf(T, res)
	for _, f in ipairs(findings) do
		if on(f.check) then out.fails[#out.fails + 1] = f end
	end
	-- the time step: a throw whose verdict flips within a 0.3% change of its
	-- launch speed is marginal (fair: it grazes); one that holds its verdict
	-- over that neighbourhood at both steps, and the two differ, depends on
	-- the step
	if on("dt") and not T.aim then
		local v480 = runVariant(T, { dt = 1 / 480 })
		T.v480 = v480
		if v480 ~= T.verdict then
			local m1, s1 = neighbourhood(T, {})
			local m2, s2 = neighbourhood(T, { dt = 1 / 480 })
			local stable = m1 ~= m2 and s1 >= STABLE and s2 >= STABLE
			local f = { check = "dt", sub = stable and "stable" or "marginal", value = s1 + s2,
				detail = fmt("240 Hz %s, 480 Hz %s; over +-0.3%% launch speed 240 Hz %s %d/%d, 480 Hz %s %d/%d",
					T.verdict, v480, m1, s1, #NEAR, m2, s2, #NEAR), dir = v480 }
			if stable then out.fails[#out.fails + 1] = f else out.infos[#out.infos + 1] = f end
		end
	end
	-- the mirror, on flat ground (the texture is hashed from the patch, not symmetric)
	if on("mirror") and not T.aim then
		local vf = runVariant(T, { texture = false })
		local vm = runVariant(T, { texture = false, mirror = true })
		T.vFlat, T.vMirror = vf, vm
		if vf ~= vm then
			local m1, s1 = neighbourhood(T, { texture = false })
			local m2, s2 = neighbourhood(T, { texture = false, mirror = true })
			local stable = m1 ~= m2 and s1 >= STABLE and s2 >= STABLE
			local f = { check = "mirror", sub = stable and "stable" or "marginal", value = s1 + s2,
				detail = fmt("flat %s, mirrored %s; over +-0.3%% launch speed flat %s %d/%d, mirrored %s %d/%d",
					vf, vm, m1, s1, #NEAR, m2, s2, #NEAR) }
			if stable then out.fails[#out.fails + 1] = f else out.infos[#out.infos + 1] = f end
		end
	end
	if T.aim then
		T.hit = res.bodies.k.toppled
		if on("aim") and not T.hit then
			out.infos[#out.infos + 1] = { check = "aim", sub = fmt("missed at %.2f m", T.d), value = 1,
				detail = fmt("tumble x%.1f, baton rests at y %.2f", T.tumble, res.bodies.baton.y) }
		end
	end
	return out
end

-- ---------- reporting ----------

local function reproCmd(i)
	local s = fmt("lua5.4 tools/physfuzz.lua --repro %d:%d", seed, i)
	if surface ~= "grass" then s = s .. " --surface " .. surface end
	return s
end

local function projName(T)
	if T.aim then return "aim" end
	if T.proj == "toss" then return (T.spin or 0) ~= 0 and "drilled kubb with spin" or "drilled kubb" end
	return "baton at " .. T.proj .. (((T.tilt or 0) ~= 0) and ", tilted" or "")
end

local function caseText(T)
	local L = { "-- A pinned physics case (tests/lua/physcases). From " .. reproCmd(T.i) .. ".",
		"-- Set expect to what the throw should do, then say why in a note.",
		"return {", fmt("\tname = %q,", fmt("fuzz %d:%d", seed, T.i)), fmt("\tsurface = %q,", surface),
		fmt("\tstakes = %s,", tostring(T.stakes ~= false)), "\tpieces = {" }
	for _, p in ipairs(T.pieces) do
		L[#L + 1] = fmt("\t\t{ id = %q, kind = %q, x = %.17g, y = %.17g,%s qw = %.17g, qx = %.17g, qy = %.17g, qz = %.17g%s },",
			p.id, p.kind, p.x, p.y, p.z and fmt(" z = %.17g,", p.z) or "", p.qw or 1, p.qx or 0, p.qy or 0, p.qz or 0,
			p.toppled and ", toppled = true" or "")
	end
	L[#L + 1] = "\t},"
	local st = T.state
	local nums = {}
	for k = 1, 13 do nums[k] = fmt("%.17g", st[k]) end
	L[#L + 1] = "\tthrows = {"
	L[#L + 1] = fmt("\t\t{ groundSeed = %d, state = { kind = %q, id = %q, exact = true,%s %s } },", st.groundSeed, st.kind, st.id,
		st.aeroK and fmt(" aeroK = %.17g,", st.aeroK) or "", table.concat(nums, ", "))
	L[#L + 1] = "\t},"
	local top_ = {}
	for id in (T.verdict or ""):gmatch("[^,| ]+") do if id ~= "in" and id ~= "out" and id ~= "-" then top_[#top_ + 1] = fmt("%q", id) end end
	L[#L + 1] = fmt("\texpect = { toppled = { %s }, clean = true },", table.concat(top_, ", "))
	L[#L + 1] = "}"
	return table.concat(L, "\n")
end

local function dumpWorld(fh, name, w)
	local parts = { fmt("%s t=%.17g steps=%d awake=%d contacts=%d", name, w.time, w.steps, w.awakeCount, w.contacts) }
	for k = 1, w.n do
		local b = w.bodies[k]
		parts[#parts + 1] = fmt("  %s %s %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %s %s",
			b.id, tostring(b.awake), b.x, b.y, b.z, b.qw, b.qx, b.qy, b.qz, b.vx, b.vy, b.vz, b.wx, b.wy, b.wz,
			tostring(b.toppled), tostring(b.touched))
	end
	fh:write(table.concat(parts, "\n"), "\n")
end

local function doRepro(spec)
	local s, i = spec:match("^(%d+):(%d+)$")
	assert(s, "--repro <seed>:<i>")
	seed = tonumber(s)
	local it = tonumber(i)
	local T = drawThrow(it)
	if T.unsettled then print("layout did not settle; nothing thrown"); return end
	if asCase then
		local ref = runReference(T)
		T.verdict = verdictOf(T, ref)
		print(caseText(T))
		return
	end
	print(fmt("iteration %d:%d on %s: %s, class %s, layout %s%s", seed, it, surface, projName(T), T.cls.name, T.layoutKind,
		T.spin and fmt(", spin %+d taps", T.spin) or (T.tilt and fmt(", tilt %+d", T.tilt) or "")))
	for _, p in ipairs(T.pieces) do
		print(fmt("  %-6s %-5s %-6s (%.3f, %.3f%s)%s", p.id, p.kind, p.role or "", p.x, p.y,
			p.z and fmt(", z %.4f", p.z) or "", p.toppled and " lying" or ""))
	end
	if T.a then
		local a = T.a
		print(fmt("  throw from (%.2f, %.2f): swivel %.4f loft %.2f speed %.3f tumble %.2f tilt %.1f legal %s arc %.0f",
			a.x, a.y, a.swivel, a.loftDeg, a.speed, a.tumbleRate or 0, a.tilt or 0, tostring(a.legal), T.arc))
		if a.plan then print(fmt("  aimed at (%.2f, %.2f)", a.plan.tx or 0, a.plan.ty or 0)) end
		if a.drill then print(fmt("  drill: spin %.1f rad/s (taps x %d + the wrist's spiral), nose down %.1f, wobble %.1f",
			a.drill.spin, plan.tune.spinPerStep, a.drill.noseDown, a.drill.wobble)) end
	else
		print(fmt("  the plan's clean baton at a lone kubb %.2f m out, tumble x%.1f, ground %d", T.d, T.tumble, T.groundSeed))
	end
	local fh
	if dumpPath then fh = assert(io.open(dumpPath, "w")) end
	local eLast
	local res, findings, w = runReference(T, function(w)
		if fh and w.steps % every == 0 then dumpWorld(fh, "fuzz", w) end
		if verbose then
			local pd, pa, pb, gd, gb = physcheck.deepest(w, true)
			if pd > 0.002 or gd > 0.002 then
				print(fmt("    t=%.4f step %d: deepest %s %.1f mm inside %s; ground %s %.1f mm", w.time, w.steps,
					pa and pa.id or "-", pd * 1000, pb and pb.id or "-", gb and gb.id or "-", gd * 1000))
			end
			local e = world.energy(w)
			if eLast and e - eLast > 1e-4 then print(fmt("    t=%.4f energy +%.5f J", w.time, e - eLast)) end
			eLast = e
		end
	end)
	if fh then dumpWorld(fh, "fuzz rest", w); fh:close(); print("  trace written to " .. dumpPath) end
	T.verdict = verdictOf(T, res)
	print(fmt("  rest at %.2f s, %d steps; first contact %s; toppled: %s", res.time, res.steps,
		res.firstContact and fmt("%.3f s with %s", res.firstContact.t, tostring(res.firstContact.with)) or "none",
		T.verdict))
	if #findings == 0 then print("  checks: all pass") end
	for _, f in ipairs(findings) do
		print(fmt("  FAIL %s / %s at %.3f s: %s", f.check, f.sub, f.t, f.detail))
	end
	if not T.aim then
		print(fmt("  480 Hz: %s", (runVariant(T, { dt = 1 / 480 }))))
		print(fmt("  flat: %s, flat mirrored: %s", (runVariant(T, { texture = false })),
			(runVariant(T, { texture = false, mirror = true }))))
		local row = {}
		for _, k in ipairs { -1e-2, -3e-3, -1e-3, -1e-4, 1e-4, 1e-3, 3e-3, 1e-2 } do
			row[#row + 1] = fmt("%+g %s", k, (runVariant(T, { scale = 1 + k })))
		end
		print("  launch speed x(1 + k), 240 Hz: " .. table.concat(row, "; "))
		row = {}
		for _, k in ipairs { -1e-2, -3e-3, -1e-3, -1e-4, 1e-4, 1e-3, 3e-3, 1e-2 } do
			row[#row + 1] = fmt("%+g %s", k, (runVariant(T, { scale = 1 + k, dt = 1 / 480 })))
		end
		print("  launch speed x(1 + k), 480 Hz: " .. table.concat(row, "; "))
	end
end

-- The monitor and the replayed launch change nothing: every body bit for bit.
local function doSelftest()
	local function state(w)
		local t = {}
		for k = 1, w.n do
			local b = w.bodies[k]
			t[#t + 1] = fmt("%s %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %s", b.id, b.x, b.y, b.z,
				b.qw, b.qx, b.qy, b.qz, b.vx, b.vy, b.vz, tostring(b.toppled))
		end
		return table.concat(t, "\n") .. fmt("\nt=%.17g", w.time)
	end
	local bad, ran = 0, 0
	for i = 1, n do
		local T = drawThrow(i)
		if not T.unsettled and not T.aim then
			ran = ran + 1
			local w0 = world.new { surface = surface, pieces = T.pieces }
			autothrow.launch(w0, T.setup, T.a)
			T.state = physcheck.capture(w0)
			world.run(w0)
			local _, _, w1 = runReference(T)
			local _, _, w2 = runVariant(T, {})
			if state(w0) ~= state(w1) then bad = bad + 1; print(fmt("%d: the monitor changed the throw", i)) end
			if state(w0) ~= state(w2) then bad = bad + 1; print(fmt("%d: the replayed launch changed the throw", i)) end
		end
	end
	print(fmt("selftest: %d throws, %d differences", ran, bad))
	os.exit(bad == 0 and 0 or 1)
end

if selftest then return doSelftest() end
-- ---------- the control grids ----------

-- --grid drill: every spin tap (-spinSteps..+spinSteps) x GRID_RELEASE x
-- GRID_DIST x each surface (or --surface's alone), --seeds throws a cell, a
-- drill into an empty far half the game's way (plan.solve with the taps,
-- autothrow.swing, plan.launch with them, world.launchDrill). Seed k of a
-- cell draws the marker's x, the ground and the swing, the same for every
-- tap, so the taps are compared on the same throws; odd k are clean (no
-- mistakes), even k the computer at club (aim error). Per cell: each
-- check's failures, and (drillscatter 3's measures) the run-on from the
-- first touch to rest, its sideways part and the rest from the mark.
-- --grid tilt: the same for a baton's tilt taps at a lone field kubb from
-- GRID_TILT_DIST, at the field and base arcs: hit rate and the checks.
local GRID_RELEASE = { 105, 135, 165 }
local GRID_DIST = { 4.6, 6.0, 7.5 }
local GRID_TILT_DIST = { 3, 5.27, 8 }
local GRID_TILT_RELEASE = { 60, 90 }

local function gridThrow(kind, surf, rel, dist, ctl, k)
	local r = plan.rng(((seed * 31 + k) * 1009 + math.floor(dist * 100)) * 409 + rel)
	local mx = r.uniform(-1.5, 1.5)
	if kind == "tilt" then mx = r.uniform(-1, 1) end
	local gs = math.floor(1 + r.next() * 1e6)
	local scale = (k % 2 == 1) and 0 or 1
	local st = plan.stance(mx, dist, 0, 0, autothrow.tune.halfWidth, {})
	local q = { level = "club", surface = surf, px = st.x, py = st.y, tx = mx, ty = dist, release = rel }
	local pieces = {}
	if kind == "drill" then
		q.projectile = "kubb"
	else
		q.projectile, q.aimZ = "baton", plan.aimZFor("kubb")
		pieces[1] = { id = "k", kind = "kubb", x = mx, y = dist }
	end
	local w = physcheck.newWorld(surf, pieces, { groundSeed = gs })
	local ok, b = withControls(kind == "drill" and ctl or 0, kind == "tilt" and ctl or 0, function()
		local sol = plan.solve(q, {})
		local sw = autothrow.swing(sol, r, scale * (kind == "drill" and autothrow.tune.drillScale or 1), {})
		local L = plan.launch(sol, sw, { projectile = q.projectile, nerves = scale > 0 and r or nil }, {})
		if kind == "drill" then
			return world.launchDrill(w, "t1", st.x, st.y, L.swivel, L.loft, L.speed, L.noseDown, L.rollLand,
				L.spin, L.wobble)
		end
		return world.launchBaton(w, st.x, st.y, L.swivel, L.loft, L.speed, L.tumble, L.tilt, "baton")
	end)
	if not ok then error(b) end
	local v = sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
	local touch
	local res, findings = physcheck.run(w, { launchSpeed = v }, function(w_)
		if not touch and w_.firstContact then touch = { x = b.x, y = b.y } end
	end)
	touch = touch or { x = b.x, y = b.y }
	local out = { findings = findings, mx = mx }
	if kind == "drill" then
		out.run = sqrt((b.x - touch.x) ^ 2 + (b.y - touch.y) ^ 2)
		out.side = b.x - touch.x
		out.mark = sqrt((b.x - mx) ^ 2 + (b.y - dist) ^ 2)
		out.inside = b.y >= 4 and b.y <= 8 and b.x >= -2.5 and b.x <= 2.5
	else
		out.hit = res.bodies.k and res.bodies.k.toppled or false
		out.side = b.x - mx
	end
	return out
end

local function doGrid(kind)
	local function pct(a, b) return b > 0 and 100 * a / b or 0 end
	assert(kind == "drill" or kind == "tilt", "--grid drill|tilt")
	local pt = plan.tune
	local ctls = {}
	if kind == "drill" then
		for c = -pt.spinSteps, pt.spinSteps do ctls[#ctls + 1] = c end
	else
		for c = -pt.tiltMaxDeg, pt.tiltMaxDeg, pt.tiltStepDeg do ctls[#ctls + 1] = c end
	end
	local surfs = surfaceGiven and { surface } or { "grass", "sand", "snow" }
	local rels = kind == "drill" and GRID_RELEASE or GRID_TILT_RELEASE
	local dists = kind == "drill" and GRID_DIST or GRID_TILT_DIST
	local checks = { "energy", "penetration", "rest", "finite" }
	local t0_ = os.clock()
	local total, fails = 0, {}
	print(fmt("physfuzz --grid %s, seed %d: %d %s x %d releases x %d distances x %d surfaces, %d throws a cell (odd clean, even club)",
		kind, seed, #ctls, kind == "drill" and "spin taps" or "tilts", #rels, #dists, #surfs, gridSeeds))
	local flagged = {}
	for _, surf in ipairs(surfs) do
		print("")
		if kind == "drill" then
			print(fmt("%s: per cell, cm: run-on (from the first touch to rest) mean, its sideways part mean, rest from the mark mean; in = rests in the far half; then failures by check", surf))
			print("| release | dist | taps | run-on | sideways | from mark | in | energy | penetration | rest | finite |")
			print("|---|---|---|---|---|---|---|---|---|---|---|")
		else
			print(fmt("%s: per cell: hit rate, the baton's rest across the line from the kubb (cm, mean); then failures by check", surf))
			print("| release | dist | tilt | hit | across | energy | penetration | rest | finite |")
			print("|---|---|---|---|---|---|---|---|---|")
		end
		local byCtl = {}
		for _, c in ipairs(ctls) do byCtl[c] = { n = 0, run = 0, side = 0, ss = 0, mark = 0, hit = 0, f = {} } end
		local sx, sy, sxx, sxy, sn, syy = 0, 0, 0, 0, 0, 0
		for _, rel in ipairs(rels) do
			for _, dist in ipairs(dists) do
				for _, c in ipairs(ctls) do
					local cell = { n = 0, run = 0, side = 0, mark = 0, inn = 0, hit = 0, f = {} }
					for _, ch in ipairs(checks) do cell.f[ch] = 0 end
					for k = 1, gridSeeds do
						local o = gridThrow(kind, surf, rel, dist, c, k)
						total = total + 1
						byCtl[c].ss = byCtl[c].ss + o.side * o.side
						sx, sy, sxx, sxy, syy, sn = sx + c, sy + o.side, sxx + c * c, sxy + c * o.side, syy + o.side * o.side, sn + 1
						cell.n = cell.n + 1
						cell.side = cell.side + o.side
						if kind == "drill" then
							cell.run, cell.mark = cell.run + o.run, cell.mark + o.mark
							if o.inside then cell.inn = cell.inn + 1 end
						elseif o.hit then cell.hit = cell.hit + 1 end
						local seen = {}
						for _, f in ipairs(o.findings) do
							if not seen[f.check] then
								seen[f.check] = true
								cell.f[f.check] = (cell.f[f.check] or 0) + 1
								fails[f.check] = (fails[f.check] or 0) + 1
								local key = surf .. " / " .. f.check .. " / " .. f.sub
								local fl = flagged[key]
								if not fl then fl = { key = key, n = 0, ex = {} }; flagged[key] = fl; flagged[#flagged + 1] = fl end
								fl.n = fl.n + 1
								if #fl.ex < 3 then
									fl.ex[#fl.ex + 1] = fmt("release %d, %.2f m, %s %+d, throw %d: %s", rel, dist,
										kind == "drill" and "spin" or "tilt", c, k, f.detail)
								end
							end
						end
					end
					local B = byCtl[c]
					B.n, B.side = B.n + cell.n, B.side + cell.side
					B.run, B.mark, B.hit = B.run + cell.run, B.mark + cell.mark, B.hit + cell.hit
					for ch, m in pairs(cell.f) do B.f[ch] = (B.f[ch] or 0) + m end
					local fcol = {}
					for _, ch in ipairs(checks) do fcol[#fcol + 1] = cell.f[ch] > 0 and tostring(cell.f[ch]) or "" end
					if kind == "drill" then
						print(fmt("| %d | %.1f | %+d | %.1f | %+.1f | %.1f | %d/%d | %s |", rel, dist, c,
							100 * cell.run / cell.n, 100 * cell.side / cell.n, 100 * cell.mark / cell.n, cell.inn, cell.n,
							table.concat(fcol, " | ")))
					else
						print(fmt("| %d | %.2f | %+d | %d/%d | %+.1f | %s |", rel, dist, c, cell.hit, cell.n,
							100 * cell.side / cell.n, table.concat(fcol, " | ")))
					end
				end
			end
		end
		-- per control step over every release and distance (drillscatter 3's style)
		for _, c in ipairs(ctls) do
			local B = byCtl[c]
			B.mean = B.side / B.n
			B.se = sqrt(math.max(0, B.ss / B.n - B.mean * B.mean) / math.max(1, B.n - 1))
		end
		print("")
		if kind == "drill" then
			print(fmt("%s, per spin step over every release and distance (cm): run-on, sideways, from mark; failures", surf))
			print("| taps | spin rad/s | throws | run-on | sideways (se) | from mark | energy | penetration | rest | finite |")
			print("|---|---|---|---|---|---|---|---|---|---|")
		else
			print(fmt("%s, per tilt over every release and distance: hit rate, across (cm); failures", surf))
			print("| tilt | throws | hit | across (se) | energy | penetration | rest | finite |")
			print("|---|---|---|---|---|---|---|---|")
		end
		for _, c in ipairs(ctls) do
			local B = byCtl[c]
			local fcol = {}
			for _, ch in ipairs(checks) do fcol[#fcol + 1] = tostring(B.f[ch] or 0) end
			if kind == "drill" then
				print(fmt("| %+d | %+.0f | %d | %.1f | %+.1f (%.1f) | %.1f | %s |", c, c * pt.spinPerStep + tw.drill.tune.spiral, B.n,
					100 * B.run / B.n, 100 * B.mean, 100 * B.se, 100 * B.mark / B.n, table.concat(fcol, " | ")))
			else
				print(fmt("| %+d | %d | %.0f%% | %+.1f (%.1f) | %s |", c, B.n, pct(B.hit, B.n), 100 * B.mean, 100 * B.se,
					table.concat(fcol, " | ")))
			end
		end
		-- monotonic: no step goes the wrong way by more than 2 standard errors
		-- (the slope's sign is the way); mirrored: side(+k) - side(0) against
		-- -(side(-k) - side(0)), the worst gap over its standard error
		local slope = (sn * sxy - sx * sy) / (sn * sxx - sx * sx)
		local icpt = (sy - slope * sx) / sn
		local res2 = (syy - icpt * sy - slope * sxy) / math.max(1, sn - 2)
		local slopeSe = sqrt(math.max(0, res2) / (sxx - sx * sx / sn))
		local wrong = {}
		for j = 2, #ctls do
			local a_, b_ = byCtl[ctls[j - 1]], byCtl[ctls[j]]
			local d = (b_.mean - a_.mean) * (slope >= 0 and 1 or -1)
			local se = sqrt(a_.se * a_.se + b_.se * b_.se)
			if d < -2 * se then wrong[#wrong + 1] = fmt("%+d to %+d", ctls[j - 1], ctls[j]) end
		end
		local mid = (#ctls + 1) // 2
		local z0 = byCtl[ctls[mid]]
		local worstZ, worstK, worstGap = 0, nil, 0
		for j = 1, mid - 1 do
			local P, M = byCtl[ctls[mid + j]], byCtl[ctls[mid - j]]
			local gap = (P.mean - z0.mean) + (M.mean - z0.mean)
			local se = sqrt(P.se * P.se + M.se * M.se + 4 * z0.se * z0.se)
			local z = math.abs(gap) / math.max(se, 1e-9)
			if z > worstZ then worstZ, worstK, worstGap = z, ctls[mid + j], gap end
		end
		print(fmt("%s: sideways %+.2f cm a %s (se %.2f); %s; mirror: worst gap %+.1f cm at +-%d (%.1f se)%s", surf,
			100 * slope, kind == "drill" and "tap" or "degree", 100 * slopeSe,
			#wrong == 0 and "monotonic (no step goes back by more than 2 se)" or ("goes back at " .. table.concat(wrong, ", ")),
			100 * worstGap, math.abs(worstK or 0), worstZ, worstZ > 3 and " NOT MIRRORED" or ""))
	end
	print("")
	print(fmt("%d throws, %.0f s, %.3f s a throw", total, os.clock() - t0_, (os.clock() - t0_) / math.max(1, total)))
	local fl = {}
	for _, ch in ipairs(checks) do fl[#fl + 1] = fmt("%s %d (%.2f%%)", ch, fails[ch] or 0, pct(fails[ch] or 0, total)) end
	print("failures: " .. table.concat(fl, ", "))
	table.sort(flagged, function(a, b) return a.n > b.n end)
	for _, f in ipairs(flagged) do
		print(fmt("  %s: %d", f.key, f.n))
		for _, e in ipairs(f.ex) do print("      " .. e) end
	end
end

if grid then return doGrid(grid) end
if repro then return doRepro(repro) end

-- ---------- the run ----------

local t0 = os.clock()
local CHECKS = { "energy", "penetration", "rest", "finite", "dt", "mirror" }
local tally = { ran = 0, skipped = 0, weight = 0, byClass = {} }
local failsBy, wFailsBy, infosBy = {}, {}, {}
for _, c in ipairs(CHECKS) do failsBy[c], wFailsBy[c], infosBy[c] = 0, 0, 0 end
local clusters, order = {}, {}
local aim = {}
for _, d in ipairs(AIM_D) do aim[d] = { n = 0, hit = 0, misses = {} } end
local anyFailW = 0
local distV = {}

local function addCluster(f, T, info)
	local key = f.check .. " / " .. f.sub .. " / " .. projName(T)
	local c = clusters[key]
	if not c then
		c = { key = key, check = f.check, sub = f.sub, proj = projName(T), n = 0, w = 0, info = info, layouts = {},
			classes = {}, controls = {}, ex = {} }
		clusters[key] = c
		order[#order + 1] = c
	end
	c.n, c.w = c.n + 1, c.w + T.cls.weight
	local lk = T.layoutKind:match("^(%a+)") or T.layoutKind
	c.layouts[lk] = (c.layouts[lk] or 0) + 1
	c.classes[T.cls.name] = (c.classes[T.cls.name] or 0) + 1
	local ctl = T.spin and fmt("spin %+d", T.spin) or (T.tilt and fmt("tilt %+d", T.tilt) or nil)
	if ctl then c.controls[ctl] = (c.controls[ctl] or 0) + 1 end
	c.ex[#c.ex + 1] = { i = T.i, value = f.value, detail = f.detail, layout = T.layoutKind, cls = T.cls.name,
		ctl = ctl }
end

for i = 1, n do
	local T0 = nil
	local res = iterate(i)
	local T = res.T
	if kindOnly and ((kindOnly == "kubb") ~= (T.projectile == "kubb")) then
		-- drawn, not counted
	elseif res.skipped then
		tally.skipped = tally.skipped + 1
	else
		tally.ran = tally.ran + 1
		tally.weight = tally.weight + T.cls.weight
		tally.byClass[T.cls.name] = (tally.byClass[T.cls.name] or 0) + 1
		if T.v480 then
			local function ids(v) local k = 0; for id in v:gmatch("[%w_]+") do if id ~= "in" and id ~= "out" then k = k + 1 end end; return k end
			tally.top240, tally.top480 = (tally.top240 or 0) + ids(T.verdict), (tally.top480 or 0) + ids(T.v480)
			tally.dtThrows = (tally.dtThrows or 0) + 1
		end
		if T.aim then
			local A = aim[T.d]
			A.n = A.n + 1
			if T.hit then A.hit = A.hit + 1 else A.misses[#A.misses + 1] = i end
		end
		local seen = {}
		for _, f in ipairs(res.fails) do
			if dist then
				local k = f.check .. " / " .. f.sub:gsub(" %a+%-%a+$", ""):gsub(" ground %a+$", " ground")
				distV[k] = distV[k] or {}
				table.insert(distV[k], f.value)
			end
			if not seen[f.check] then
				seen[f.check] = true
				failsBy[f.check] = failsBy[f.check] + 1
				wFailsBy[f.check] = wFailsBy[f.check] + T.cls.weight
			end
			addCluster(f, T, false)
		end
		if #res.fails > 0 then anyFailW = anyFailW + T.cls.weight end
		for _, f in ipairs(res.infos) do
			if infosBy[f.check] then infosBy[f.check] = infosBy[f.check] + 1 end
			addCluster(f, T, true)
		end
		if verbose and (#res.fails > 0) then
			for _, f in ipairs(res.fails) do
				print(fmt("%d %s / %s: %s", i, f.check, f.sub, f.detail))
			end
		end
	end
	if i % 200 == 0 then
		io.stderr:write(fmt("  %d of %d, %.0f s\n", i, n, os.clock() - t0))
	end
end
local secs = os.clock() - t0

local function pct(a, b) return b > 0 and 100 * a / b or 0 end
print(fmt("physfuzz seed %d, %d iterations on %s: %d run, %d layouts that did not settle; %.0f s, %.3f s an iteration",
	seed, n, surface, tally.ran, tally.skipped, secs, secs / math.max(1, n)))
local cls = {}
for _, c in ipairs(CLASSES) do cls[#cls + 1] = fmt("%s %d (weight %.1f)", c.name, tally.byClass[c.name] or 0, c.weight) end
print("classes: " .. table.concat(cls, ", "))
print("")
print("| check | failed | rate | realistic rate | marginal (not failures) |")
print("|---|---|---|---|---|")
for _, c in ipairs(CHECKS) do
	if on(c) then
		print(fmt("| %s | %d | %.2f%% | %.2f%% | %s |", c, failsBy[c], pct(failsBy[c], tally.ran),
			pct(wFailsBy[c], tally.weight), (c == "dt" or c == "mirror") and tostring(infosBy[c]) or ""))
	end
end
print(fmt("| any | | | %.2f%% | |", pct(anyFailW, tally.weight)))
if tally.dtThrows then
	print(fmt("pieces toppled over %d throws: %d at 240 Hz, %d at 480 Hz", tally.dtThrows, tally.top240, tally.top480))
end
if on("aim") then
	print("")
	print("| aim (plan's clean baton, lone kubb) | hit | rate | 95% interval | claimed |")
	print("|---|---|---|---|---|")
	for _, d in ipairs(AIM_D) do
		local A = aim[d]
		local p = A.n > 0 and A.hit / A.n or 0
		-- Wilson interval
		local z = 1.96
		local lo, hi = 0, 1
		if A.n > 0 then
			local den = 1 + z * z / A.n
			local c = (p + z * z / (2 * A.n)) / den
			local h = z * sqrt(p * (1 - p) / A.n + z * z / (4 * A.n * A.n)) / den
			lo, hi = c - h, c + h
		end
		local claim = AIM_CLAIM[d]
		print(fmt("| %.2f m | %d of %d | %.0f%% | %.0f to %.0f%% | %s |", d, A.hit, A.n, 100 * p, 100 * lo, 100 * hi,
			(surface == "grass" and claim) and fmt("%.0f%%", 100 * claim) or "none"))
	end
end
if dist then
	print("")
	print("the worst value a throw reached, by check (with --set check.* to 0, every throw's):")
	local keys = {}
	for k in pairs(distV) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local v = distV[k]
		table.sort(v)
		local function q(p) return v[math.max(1, math.ceil(p * #v))] end
		print(fmt("  %-40s n %5d  p50 %.4g  p90 %.4g  p99 %.4g  p99.9 %.4g  max %.4g", k, #v, q(0.5), q(0.9), q(0.99),
			q(0.999), v[#v]))
	end
end
print("")
table.sort(order, function(a, b)
	if a.info ~= b.info then return not a.info end
	if a.w ~= b.w then return a.w > b.w end
	return a.key < b.key
end)
print("clusters, failures first, by realistic rate:")
for k, c in ipairs(order) do
	if k > top then print(fmt("... and %d more", #order - top)); break end
	table.sort(c.ex, function(a, b) return a.value > b.value end)
	local lay, cl = {}, {}
	for name, m in pairs(c.layouts) do lay[#lay + 1] = name .. " " .. m end
	for name, m in pairs(c.classes) do cl[#cl + 1] = name .. " " .. m end
	local ctls = {}
	for name, m in pairs(c.controls) do ctls[#ctls + 1] = name .. " " .. m end
	table.sort(lay); table.sort(cl); table.sort(ctls)
	print(fmt("%2d. %s%s: %d (%.2f%%, realistic %.2f%%); layouts %s; classes %s%s", k, c.key,
		c.info and " [informational]" or "", c.n, pct(c.n, tally.ran), pct(c.w, tally.weight),
		table.concat(lay, ", "), table.concat(cl, ", "), #ctls > 0 and "; " .. table.concat(ctls, ", ") or ""))
	for j = 1, math.min(3, #c.ex) do
		local e = c.ex[j]
		print(fmt("      %s   # %s, %s%s: %s", reproCmd(e.i), e.cls, e.layout, e.ctl and ", " .. e.ctl or "", e.detail))
	end
end
