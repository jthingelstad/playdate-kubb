-- The device performance check (docs/notes/performance.md, "The performance
-- check"): when a file named `perfbench` is in the game's Data folder at
-- launch, the game deletes it, runs this (several minutes, nobody pressing
-- anything), appends every figure to perf.txt in the Data folder and then
-- carries on into the normal game. A developer's tool, never a player's: no
-- menu item reaches it.
--
-- The same fixed scenes every run, each repeated `perf.tune.reps` times, so a
-- build can be compared with the last one and the spread told from the
-- change. Everything is deterministic but the device's own clock (the
-- playback paces the shown physics by real frame time, so frame counts move
-- a little from run to run).
--
--   throws   a baton into a close cluster of six field kubbs from 5 m, from a
--            step away (1 m: the short throw) and from 1.5 m (engine 0.16: the
--            default there is the drive), a full 8 m baton at a
--            base kubb, and a drilled kubb thrown in among the field and
--            settling (core/bench's match setup). Each is the plan's clean
--            throw played through the throw scene as in a match. Per throw:
--            release to rest (s), the flight's frames and their real frame
--            time (mean, sd, max), the scene's update and draw per frame
--            (mean, max), starved frames, physics steps and ms per step, and
--            the most memory seen. Then over the repeats: median, min, max.
--   aim      30 frames of the aim view with the circle moving every frame (the
--            plan solved again each frame) onto a kubb 1 m away and one 6 m
--            away: frame update and draw (mean, max).
--   aim d-pad the same two circles moved by a scripted d-pad through the scene's
--            update (the plan every other frame under halfRateM, then every
--            frame): update and draw (mean, max) and how many frames solved.
--   plan     plan.solve for a baton at 1, 1.5, 3 and 8 m and a drill, in ms.
--   computer autothrow.choose (the Playdate's throw, chosen in one frame) at
--            each level for a baseline baton, a kubb toss and a field kubb
--            baton from a real match's setups, in ms.
--   decide   the computer's decisions where they cost most (engine 0.12 and
--            0.13: raising by the attacker's batons, field.line, inkast.depth;
--            each row is skipped on an engine that has no such call): one raise
--            decision with eight kubbs lying in a tight group (apart, par, and
--            cpu.raise at each level), the whole settle of those eight in one
--            call (match.settle: the frame the scene makes it in) with the
--            Playdate defending at each level and with a person defending (the
--            engine's advice), and autothrow.choose at each level with eight
--            field kubbs standing in a tight group and for a toss onto four
--            lying; in ms.
--   cpu turn the same through the match scene, VS PLAYDATE: the transition
--            frame (the scene made on a resume, so the settle runs as at the
--            end of a turn) with the Playdate raising the eight, and with the
--            person's eight raised by RAISING: AUTOMATIC; then every frame of
--            the Playdate's first baton at the eight field kubbs (its choose,
--            its aim, the swing, the flight to rest): the slowest frame
--            (update + draw), the choose frame and the flight's mean, in ms.
--   kid      (engine 0.15) a person's plan.solve on the Kid meter from the Kid line
--            at 2, 3 and 6 m and a drill, the Kid computer's autothrow.choose in a
--            Kid match's own setups, and raising.fairSpot (where a kubb out twice
--            is stood) with eight kubbs lying in the half; Kid also joins the
--            per-level rows above.
--   drive    (engine 0.16, docs/notes/throw.md "The drive") plan.solve for a drive at
--            the throw's floor at 1.5 and 3 m (the bisection) and plan.arcFloor at 1.5
--            and 3 m, in ms; a kept drive raised to a new floor at 1.5 and 3 m (core
--            1.0: release 0 with the stance walking back, then the circle moving
--            away, 4 mm a solve: mean and max); then the aim at a kubb 1.5 m in front of an advantage
--            line through the scene's own update: 30 frames with nothing pressed, 30
--            with B held (the frame B goes down works out the floor), 30 with B held
--            and down tapped to the floor and back: update and draw (mean, max) and
--            how many plan.solve calls each part made (nothing pressed: none).
--   start    a new VS PLAYDATE match (the scene made, its first frame drawn)
--            and a resume (a saved match read from the datastore, unpacked
--            and its scene made), in ms. The save is the check's own key
--            (perfbench-match), deleted after: a player's "match" is never
--            read or written.
--
-- The crank recorder and the frame-time log are off while it runs and put
-- back after, so traces.jsonl and frames.jsonl are untouched; auto-lock is
-- off for the run.
import "CoreLibs/graphics"
import "core/tw"
import "core/bench"
import "core/match"
import "core/save"
import "core/autothrow"
import "core/throwplan"
import "core/quat"
import "core/raising"
import "input"
import "scenes/throw"
import "scenes/match"
import "render/world"

local gfx <const> = playdate.graphics
local throw, plan, autothrow, cmatch = tw.scenes.throw, tw.plan, tw.autothrow, tw.match
-- Two clocks. The input provider (input.device) resets playdate's elapsed
-- time at the start of every frame (its advance), so within a frame
-- clock() is seconds since that frame began: a frame's update is clock() read
-- just after it. Anything spanning an advance (a match made and its first
-- frame) is timed with msNow (whole milliseconds).
local clock = playdate.getElapsedTime
local msNow = playdate.getCurrentTimeMilliseconds

local perf = {}
perf.flag = "perfbench"
perf.tune = { reps = 5, aimFrames = 30, solveReps = 20, chooseReps = 10, startReps = 5, decideReps = 10, turnReps = 3 }

local function out(lines)
	local f = playdate.file.open("perf.txt", playdate.file.kFileAppend)
	if not f then return end
	for _, l in ipairs(lines) do f:write(l .. "\n") end
	f:close()
end

local function kb() return collectgarbage("count") end

-- median, min and max of a list of numbers
local function spread(xs)
	local c = {}
	for i, x in ipairs(xs) do c[i] = x end
	table.sort(c)
	local n = #c
	if n == 0 then return 0, 0, 0 end
	local med = (n % 2 == 1) and c[(n + 1) / 2] or 0.5 * (c[n / 2] + c[n / 2 + 1])
	return med, c[1], c[n]
end
local function fmtSpread(xs, f)
	local med, lo, hi = spread(xs)
	f = f or "%.1f"
	return string.format(f .. " [" .. f .. "-" .. f .. "]", med, lo, hi)
end

local function standing(id, kind, x, y, yaw, role)
	local qw, qx, qy, qz = tw.quat.fromAxisAngle(0, 0, 1, yaw or 0)
	return { id = id, kind = kind, x = x, y = y, qw = qw, qx = qx, qy = qy, qz = qz, toppled = false, role = role }
end

-- Five base kubbs on the far baseline and the king, as in a match (view frame).
local function basePieces()
	local p = {}
	for i, x in ipairs { -2, -1, 0, 1, 2 } do p[i] = standing("b" .. i, "kubb", x, 8, 0, "base") end
	p[#p + 1] = standing("king", "king", 0, 4, 0, "king")
	return p
end

-- A close cluster of six field kubbs at x = 1, its front kubb at y = 5.
local CLUSTER = {
	{ 1.00, 5.00, 0.1 }, { 1.18, 5.12, -0.2 }, { 0.83, 5.10, 0.3 },
	{ 1.05, 5.28, 0.0 }, { 0.80, 5.32, -0.4 }, { 1.24, 5.36, 0.2 },
}
local function clusterSetup(forwardY)
	local p, targets = basePieces(), {}
	for i, c in ipairs(CLUSTER) do
		p[#p + 1] = standing("f" .. i, "kubb", c[1], c[2], c[3], "field")
		targets[i] = "f" .. i
	end
	return { kind = "baton", side = "A", projectile = "baton", batonId = "baton1", pieces = p, debris = {},
		lineY = 0, forwardY = forwardY or 0, targets = targets, label = "perf", n = 1, of = 6 }
end

local function baseSetup()
	local p = basePieces()
	p[#p + 1] = standing("f1", "kubb", 0.8, 5.0, 0.2, "field")
	p[#p + 1] = standing("f2", "kubb", -0.9, 5.6, -0.3, "field")
	return { kind = "baton", side = "A", projectile = "baton", batonId = "baton1", pieces = p, debris = {},
		lineY = 0, forwardY = 0, targets = { "b1", "b2", "b3", "b4", "b5" }, label = "perf", n = 1, of = 6 }
end

-- The plan's clean throw at (tx, ty) from (px, py): an action for
-- throw.autoLaunch, with its plan (so the throw leaves the plan's hand).
local CLEAN = { back = 0, releaseAngle = 0, flickFrac = 1, smoothness = 1, shake = 0, pull = 1, how = "stopped" }
local function cleanBaton(s, tx, ty, px, py)
	throw.aimAt(s, tx, ty)
	throw.setStance(s, px, py)
	local sol = s.sol
	CLEAN.back, CLEAN.releaseAngle = sol.back, sol.release
	local _, lv = throw.planBy(s)   -- a person's: the meter's (no level), engine 0.13
	local L = plan.launch(sol, CLEAN, { projectile = "baton", tilt = 0, spin = 0, level = lv }, {})
	return { x = s.playerX, y = s.playerY, swivel = L.swivel, loftDeg = L.loft, speed = L.speed,
		tumbleRate = L.tumble, tilt = L.tilt or 0, legal = L.legal, plan = sol }
end

perf.throws = {
	{ name = "cluster 5m", setup = function() return clusterSetup(0) end,
		action = function(s) return cleanBaton(s, 1.0, 5.0, 1.0, 0) end },
	{ name = "cluster 1m", setup = function() return clusterSetup(4.0) end,
		action = function(s) return cleanBaton(s, 1.0, 5.0, 1.0, 4.0) end },
	-- (engine 0.16) the default at a cluster 1.5 m from an advantage line: the drive
	{ name = "drive 1.5m", setup = function() return clusterSetup(3.5) end,
		action = function(s) return cleanBaton(s, 1.0, 5.0, 1.0, 3.5) end },
	{ name = "8m base", setup = baseSetup,
		action = function(s) return cleanBaton(s, 0, 8, 0, 0) end },
	{ name = "drill", setup = function() return tw.bench.matchSetup("kubb") end,
		action = function() return { drill = { markerX = -0.5, markerY = 6.4 } } end },
}

-- One throw through the throw scene on the device's clock. Returns a table
-- of figures.
local function runThrow(y, case)
	local fl = tw.framelog
	local write = fl.write
	local got = {}
	fl.write = function(t, info) got.t, got.info = t, info end
	local r = {}
	local ok, err = pcall(function()
		local s = throw.new(tw.input.device())
		s.sceneName = "match"
		s.nerves = false
		throw.enter()
		throw.prepare(s, case.setup())
		local a = case.action(s)
		for _ = 1, 3 do throw.draw(s); y() end
		collectgarbage("collect")
		local m0, mMax = kb(), kb()
		s.input:advance()
		throw.autoLaunch(s, a)
		local n, wall, rest, tailN = 0, 0, false, 0
		local nf, sum, sum2, mx = 0, 0, 0, 0
		local upS, upM, drS, drM = 0, 0, 0, 0
		local prevLive = false
		while s.mode ~= "done" and n < 3000 do
			local flying = s.mode == "flight"
			throw.update(s)
			local t1 = clock()   -- the update: since advance reset the clock
			throw.draw(s)
			local t2 = clock()
			-- this frame's dt (raw) is the previous frame's length
			local raw = s.input.raw or 0
			if n > 0 and not rest then wall = wall + raw end
			if s.mode == "rest" then rest = true end
			if prevLive then
				nf, sum, sum2 = nf + 1, sum + raw, sum2 + raw * raw
				if raw > mx then mx = raw end
			end
			-- live flight frames: in flight and not the calm tail (where the
			-- picture holds and frames are tailPeriod long by design)
			local pb = s.pb
			local tail = pb and pb.calmFrom and s.showTime >= pb.calmFrom * pb.frameDt
			prevLive = flying and s.mode == "flight" and not tail
			if flying and tail then tailN = tailN + 1 end
			if prevLive then
				upS, drS = upS + t1, drS + (t2 - t1)
				if t1 > upM then upM = t1 end
				if t2 - t1 > drM then drM = t2 - t1 end
			end
			local m = kb()
			if m > mMax then mMax = m end
			y()
			n = n + 1
		end
		local mean = nf > 0 and sum / nf or 0
		r.rest, r.frames = wall, nf
		r.mean, r.sd, r.max = mean * 1000, (nf > 1 and math.sqrt(math.max(0, sum2 / nf - mean * mean)) or 0) * 1000, mx * 1000
		r.up, r.upMax = nf > 0 and upS * 1000 / nf or 0, upM * 1000
		r.dr, r.drMax = nf > 0 and drS * 1000 / nf or 0, drM * 1000
		r.tail = tailN
		r.mem, r.memMax = m0, mMax
		local res = s.result
		r.toppled = res and #res.toppled or -1
		if got.t then
			r.starved, r.steps, r.phys = got.t.starved, got.info.steps, got.info.phys * 1000
			r.msStep = got.info.steps > 0 and r.phys / got.info.steps or 0
		end
	end)
	fl.write = write
	tw.render.world.invalidate()
	if not ok then r.err = tostring(err) end
	return r
end

local function throwLines(y)
	local lines = { string.format("throws (%d each after one not counted; median [min-max]):", perf.tune.reps) }
	for _, case in ipairs(perf.throws) do
		local R = {}
		-- one throw first, not counted (the first of a kind loads and warms up)
		runThrow(y, case)
		y()
		for i = 1, perf.tune.reps do
			R[i] = runThrow(y, case)
			y()
		end
		if R[1].err then
			lines[#lines + 1] = "  " .. case.name .. ": error " .. R[1].err
		else
			local function col(k) local c = {}; for i, r in ipairs(R) do c[i] = r[k] or 0 end; return c end
			lines[#lines + 1] = string.format("  %-10s toppled %s; rest %s s; live flight frames %s (calm tail %s); frame ms mean %s sd %s max %s",
				case.name, fmtSpread(col("toppled"), "%d"), fmtSpread(col("rest"), "%.2f"), fmtSpread(col("frames"), "%d"),
				fmtSpread(col("tail"), "%d"),
				fmtSpread(col("mean")), fmtSpread(col("sd")), fmtSpread(col("max")))
			lines[#lines + 1] = string.format("  %-10s update ms mean %s max %s; draw ms mean %s max %s; starved %s; steps %s at %s ms; memory KB %s, max %s",
				"", fmtSpread(col("up")), fmtSpread(col("upMax")), fmtSpread(col("dr")), fmtSpread(col("drMax")),
				fmtSpread(col("starved"), "%d"), fmtSpread(col("steps"), "%d"), fmtSpread(col("msStep"), "%.2f"),
				fmtSpread(col("mem"), "%.0f"), fmtSpread(col("memMax"), "%.0f"))
		end
	end
	return lines
end

-- The aim view, the circle moving every frame by a hair around (tx, ty) from
-- (px, py): the plan is solved again each frame, as while the d-pad moves it.
local function aimLines(y)
	local lines = { "aim with the circle moving (plan solved every frame):" }
	for _, c in ipairs { { "kubb 1m", 4.0, 1.0, 5.0 }, { "kubb 6m", 0, 0.8, 6.0 } } do
		local s = throw.new(tw.input.device())
		throw.enter()
		throw.prepare(s, clusterSetup(c[2]))
		throw.setStance(s, 1.0, c[2])
		local upS, upM, drS, drM = 0, 0, 0, 0
		local n = perf.tune.aimFrames
		for i = 1, n do
			s.input:advance()
			local t0 = clock()
			-- what aimInput does when the circle moves: the marker, then a replan
			s.markerX = c[3] + 0.002 * (i % 2)
			s.markerY = c[4]
			throw.replan(s)
			local t1 = clock()
			throw.draw(s)
			local t2 = clock()
			upS, drS = upS + (t1 - t0), drS + (t2 - t1)
			if t1 - t0 > upM then upM = t1 - t0 end
			if t2 - t1 > drM then drM = t2 - t1 end
			y()
		end
		lines[#lines + 1] = string.format("  %-8s %d frames: update (replan) %.2f ms (max %.2f), draw %.1f ms (max %.1f)",
			c[1], n, upS * 1000 / n, upM * 1000, drS * 1000 / n, drM * 1000)
	end
	return lines
end

-- The aim view driven as a player drives it: the d-pad held (right and left on
-- alternate frames, so the circle stays by the kubb) through the scene's own
-- update, whose plan solves at most every other frame within halfRateM of the
-- stance; then the same with that off (halfRateM 0: a solve every frame).
local function dpadLines(y)
	local lines = { "aim d-pad (scene update with the d-pad held; every other frame / every frame):" }
	local t = throw.tune
	local keep = t.halfRateM
	for _, c in ipairs { { "kubb 1m", 4.0, 1.0, 5.0 }, { "kubb 6m", 0, 0.8, 6.0 } } do
		local parts = {}
		for _, r in ipairs { keep, 0 } do
			t.halfRateM = r
			local n = perf.tune.aimFrames
			local steps = { { n = 1 } }   -- an idle first frame: the circle still, one plan
			for i = 1, n do steps[i + 1] = { hold = { (i % 2 == 1) and "right" or "left" } } end
			local s = throw.new(tw.input.scripted(steps, 1 / 50))
			throw.enter()
			throw.prepare(s, clusterSetup(c[2]))
			throw.setStance(s, 1.0, c[2])
			throw.aimAt(s, c[3], c[4])
			throw.update(s)
			throw.draw(s)
			y()
			local upS, upM, drS, drM, skipped = 0, 0, 0, 0, 0
			for _ = 1, n do
				local t0 = clock()
				throw.update(s)
				local t1 = clock()
				throw.draw(s)
				local t2 = clock()
				if s.planSkipped then skipped = skipped + 1 end
				upS, drS = upS + (t1 - t0), drS + (t2 - t1)
				if t1 - t0 > upM then upM = t1 - t0 end
				if t2 - t1 > drM then drM = t2 - t1 end
				y()
			end
			parts[#parts + 1] = string.format("%s: update %.2f ms (max %.2f), draw %.1f ms (max %.1f), %d of %d solved",
				r > 0 and "every other" or "every", upS * 1000 / n, upM * 1000, drS * 1000 / n, drM * 1000, n - skipped, n)
		end
		t.halfRateM = keep
		lines[#lines + 1] = string.format("  %-8s %s", c[1], table.concat(parts, "; "))
	end
	return lines
end

local function solveLines(y)
	local lines = { string.format("plan.solve (ms, %d each):", perf.tune.solveReps) }
	local parts = {}
	local out = {}
	local kubbZ = plan.aimZFor("kubb")
	for _, d in ipairs { 1.0, 1.5, 3.0, 8.0, "drill" } do
		-- a person's plan: the meter and the default arc for the distance (engine 0.13, 0.10)
		local q = { projectile = "baton", px = 0, py = 0, tx = 0, ty = d,
			release = plan.arcFor("baton", type(d) == "number" and d or nil),
			meter = plan.meter(), surface = "grass", spin = 0, aimZ = kubbZ }
		if d == "drill" then
			q.projectile, q.ty, q.release, q.aimZ = "kubb", 6.0, plan.arcFor("drill"), 0
		end
		local t0 = clock()
		for _ = 1, perf.tune.solveReps do plan.solve(q, out) end
		parts[#parts + 1] = string.format("%s %.2f", d == "drill" and "drill 6m" or (d .. "m"), (clock() - t0) * 1000 / perf.tune.solveReps)
		y()
	end
	lines[#lines + 1] = "  " .. table.concat(parts, ", ")
	return lines
end

-- Setups from a real match: the first baton (from the baseline at the base
-- kubbs), a kubb toss, and a field kubb baton once the tossed kubbs stand.
local function matchSetups()
	local m = cmatch.new { start = { year = 2026, month = 11, day = 20, hour = 12, min = 0 } }
	local g = m.game
	local MISS = {}
	local S = {}
	S.base = cmatch.setup(m)
	-- turn 1 (2-4-6): two batons, the second toppling b1, which B tosses in
	g:throwBaton(MISS); g:throwBaton({ toppled = { "b1" } })
	S.toss = cmatch.setup(m)
	for _ = 1, 4 do
		if g.phase ~= "toss" then break end
		local ok = pcall(function() g:toss({ rest = { x = 0.5, y = 2.4, standing = false, angle = 0.4 }, moved = {} }) end)
		if not ok then break end
	end
	pcall(function() g:raiseAll() end)
	S.field = cmatch.setup(m)
	if S.field and S.field.kind ~= "baton" then S.field = nil end
	return S
end

local function chooseLines(y)
	local lines = { string.format("computer: autothrow.choose (ms, %d each; median [min-max]):", perf.tune.chooseReps) }
	local ok, S = pcall(matchSetups)
	if not ok then return { "computer: setup error " .. tostring(S) } end
	for _, lv in ipairs(tw.plan.levels.kid and { "kid", "beginner", "club", "pro" } or { "beginner", "club", "pro" }) do
		local parts = {}
		for _, k in ipairs { "base", "toss", "field" } do
			local st = S[k]
			if st then
				local xs = {}
				local r = autothrow.rng(1234)
				for i = 1, perf.tune.chooseReps do
					local t0 = clock()
					autothrow.choose(st, r, 1, lv)
					xs[i] = (clock() - t0) * 1000
					y()
				end
				parts[#parts + 1] = string.format("%s (%s) %s", k, st.kind, fmtSpread(xs, "%.2f"))
			end
		end
		lines[#lines + 1] = "  " .. lv .. ": " .. table.concat(parts, "; ")
	end
	return lines
end

-- ---------- the computer's decisions at their costliest (engine 0.12, 0.13) ----------

local START = { year = 2026, month = 11, day = 20, hour = 12, min = 0 }
local MISS = {}
local function lyingAt(x, yy, a) return { rest = { x = x, y = yy, standing = false, angle = a }, moved = {} } end
local function teamsAt(level)
	return { A = { name = "You", players = { { name = "You" } } },
		B = { name = "Playdate", players = { { name = "Playdate", level = level } } } }
end
-- the kubbs tossed in lying in a tight group: two rows of four, 0.39 m apart
-- across and 0.45 m in depth from y0 (dir: +1 toward B's baseline, -1 toward A's)
local function tossGrid(g, y0, dir)
	local xs, i = { -0.45, -0.15, 0.15, 0.45 }, 0
	while g.phase == "toss" do
		i = i + 1
		local row = (i - 1) // 4
		g:toss(lyingAt(0.6 + xs[(i - 1) % 4 + 1] * 1.3, y0 + dir * row * 0.45, 1.57 + 0.05 * i))
	end
end
local function standingField(g)
	local fk = {}
	for id, k in pairs(g.kubbs) do
		if k.kind == "field" and k.pose.standing and k.where ~= "out" then fk[#fk + 1] = id end
	end
	table.sort(fk)
	return fk
end
-- VS PLAYDATE (the Playdate at `level`), turn 2: B to raise eight kubbs lying in
-- a tight group in its half. Every raise on the way is the game's own (apart), so
-- the position is the same on every engine.
local function stateB8(level)
	local m = cmatch.new { start = START, mode = "Vs Playdate", teams = teamsAt(level), cpu = { "B" } }
	local g = m.game
	g:throwBaton({ toppled = { "b1", "b2", "b3" } }); g:throwBaton({ toppled = { "b4", "b5" } })
	local i = 0
	while g.phase == "toss" do i = i + 1; g:toss(lyingAt(-0.6 + 0.3 * i, 2.6, 0.2 * i)) end
	while g:need().kind == "raise" do g:raise(nil) end
	local fk = standingField(g)
	g:throwBaton({ toppled = { fk[1], fk[2], fk[3] } }); g:throwBaton({ toppled = { fk[4], fk[5] } })
	g:throwBaton({ toppled = { "a1", "a2" } }); g:throwBaton({ toppled = { "a3" } })
	while g.phase ~= "toss" do g:throwBaton(MISS) end
	tossGrid(g, 5.3, 1)
	return m
end
-- the same match on to turn 3's end: A (the person) to raise eight lying in a
-- tight group in its half, after which the Playdate attacks eight field kubbs
local function stateA8(level)
	local m = stateB8(level)
	local g = m.game
	while g:need().kind == "raise" do g:raise(nil) end
	local fk = standingField(g)
	g:throwBaton({ toppled = { fk[1], fk[2], fk[3], fk[4] } }); g:throwBaton({ toppled = { fk[5], fk[6], fk[7], fk[8] } })
	while g.phase ~= "toss" do g:throwBaton(MISS) end
	tossGrid(g, 2.7, -1)
	return m
end

-- (Kid since engine 0.15: its rows are new, the others compare with older builds)
local LEVELS = tw.plan.levels.kid and { "kid", "beginner", "club", "pro" } or { "beginner", "club", "pro" }
local function decideLines(y)
	local R = perf.tune.decideReps
	local lines = {}
	local function emit(l) out { l } end   -- each line as it is measured (a long section)
	emit(string.format("computer decisions (ms, %d each; median [min-max]):", R))
	local ok, err = pcall(function()
		local raising, cpu = tw.raising, tw.cpu
		-- one raise decision: B's first of the eight
		local m = stateB8("pro")
		local g = m.game
		local n = g:need()
		local ctx = g:context(n.side, n.kubb)
		local parts = {}
		local function timeIt(label, f)
			local xs = {}
			for i = 1, R do
				local t0 = clock()
				f()
				xs[i] = (clock() - t0) * 1000
				y()
			end
			parts[#parts + 1] = label .. " " .. fmtSpread(xs, "%.2f")
		end
		timeIt("apart", function() raising.choose(n.decision, ctx, "apart") end)
		if raising.policies.par then timeIt("par", function() raising.choose(n.decision, ctx, "par") end) end
		if cpu and cpu.raise then
			for _, lv in ipairs(LEVELS) do timeIt("cpu " .. lv, function() cpu.raise(n.decision, ctx, lv) end) end
		end
		emit(string.format("  one raise, 8 lying (%d ends): %s", #n.decision.choices, table.concat(parts, "; ")))
		-- the whole settle of the eight in one call, as the scene makes it in a frame
		parts = {}
		local cases = { { "Playdate beginner", "beginner", { "B" } }, { "club", "club", { "B" } }, { "pro", "pro", { "B" } },
			{ "a person (advice)", "club", {} } }
		if tw.plan.levels.kid then table.insert(cases, 1, { "Playdate kid", "kid", { "B" } }) end
		for _, c in ipairs(cases) do
			local xs = {}
			for i = 1, R do
				local mm = stateB8(c[2])
				mm.cpu = c[3]
				y()
				collectgarbage("collect")
				local t0 = clock()
				cmatch.settle(mm)
				xs[i] = (clock() - t0) * 1000
				y()
			end
			parts[#parts + 1] = c[1] .. " " .. fmtSpread(xs, "%.1f")
		end
		emit("  settle of the 8 (match.settle): " .. table.concat(parts, "; "))
		-- choose: eight field kubbs standing in a tight group (turn 4, B attacking)
		local mf = stateA8("pro")
		cmatch.settle(mf)
		local field = cmatch.setup(mf)
		-- a toss onto four kubbs already lying by the basket (turn 2)
		local mt = cmatch.new { start = START, mode = "Vs Playdate" }
		local gt = mt.game
		gt:throwBaton({ toppled = { "b1", "b2", "b3" } }); gt:throwBaton({ toppled = { "b4", "b5" } })
		for i = 1, 4 do gt:toss(lyingAt(1.2 + 0.08 * i, 2.0, 0.3)) end
		local toss = cmatch.setup(mt)
		for _, lv in ipairs(LEVELS) do
			parts = {}
			for _, c in ipairs { { "8 field (" .. #standingField(mf.game) .. ")", field }, { "toss onto 4", toss } } do
				local xs = {}
				local r = autothrow.rng(1234)
				for i = 1, R do
					local t0 = clock()
					autothrow.choose(c[2], r, 1, lv)
					xs[i] = (clock() - t0) * 1000
					y()
				end
				local play = cpu and cpu.last and cpu.last.why and cpu.last.why.play
				parts[#parts + 1] = string.format("%s %s%s", c[1], fmtSpread(xs, "%.2f"), play and (" " .. play) or "")
			end
			emit("  choose " .. lv .. ": " .. table.concat(parts, "; "))
		end
	end)
	if not ok then emit("  error: " .. tostring(err)) end
	return lines
end

-- The Playdate's turn through the match scene (VS PLAYDATE, noSave, noFile).
local function turnLines(y)
	local scene = tw.scenes.match
	local lines = {}
	local function emit(l) out { l } end
	emit(string.format("computer turn through the match scene (ms, %d each; median [min-max]):", perf.tune.turnReps))
	local ok, err = pcall(function()
		-- the transition with the Playdate raising the eight (club apart, pro par)
		local parts = {}
		for _, lv in ipairs { "club", "pro" } do
			local xs = {}
			for i = 1, perf.tune.turnReps do
				local m = stateB8(lv)
				y()
				collectgarbage("collect")
				local t0 = msNow()
				local s = scene.new(tw.input.device(), { vs = "B", resume = m, noSave = true, noFile = true, cpuSeed = 7 })
				xs[i] = msNow() - t0
				scene.enter()
				scene.draw(s)
				y()
			end
			parts[#parts + 1] = "Playdate " .. lv .. " raising 8 " .. fmtSpread(xs, "%d")
		end
		emit("  transition (scene made on the resume, its settle and setup): " .. table.concat(parts, "; "))
		-- the person's eight raised by RAISING: AUTOMATIC, then the Playdate's first
		-- baton at the eight field kubbs, frame by frame
		local tr, worst, chooseF, flight, nflight = {}, {}, {}, {}, {}
		for i = 1, perf.tune.turnReps do
			local m = stateA8("pro")
			y()
			collectgarbage("collect")
			local t0 = msNow()
			local s = scene.new(tw.input.device(), { vs = "B", resume = m, noSave = true, noFile = true, cpuSeed = 7,
				autoSettle = true })
			tr[i] = msNow() - t0
			scene.enter()
			scene.draw(s)
			y()
			local mx, ch, fs, fn, nfr = 0, 0, 0, 0, 0
			while nfr < 3000 do
				local had = s.cpuAim
				scene.update(s)
				scene.draw(s)
				local ms = clock() * 1000   -- update + draw: the input's advance reset the clock
				if ms > mx then mx = ms end
				if not had and s.cpuAim then ch = ms end
				if s.ts.mode == "flight" then fs, fn = fs + ms, fn + 1 end
				nfr = nfr + 1
				y()
				if s.cpuThrows >= 1 and s.ts.mode ~= "flight" and s.ts.mode ~= "cpuswing" and s.resolved then break end
			end
			worst[i], chooseF[i], flight[i], nflight[i] = mx, ch, fn > 0 and fs / fn or 0, fn
		end
		emit("  transition with the person's 8 raised automatically (advice) " .. fmtSpread(tr, "%d"))
		emit(string.format("  Playdate pro's first baton at 8 field kubbs: slowest frame %s; choose frame %s; flight frames %s, mean %s",
			fmtSpread(worst), fmtSpread(chooseF), fmtSpread(nflight, "%d"), fmtSpread(flight)))
	end)
	if not ok then emit("  error: " .. tostring(err)) end
	return lines
end

-- ---------- a Kid match (engine 0.15) ----------
-- A person's plan on the Kid meter from the Kid line, the Kid computer's choose in a
-- Kid match's own setups, and the fair spot a kubb out twice is stood at (a scan of the
-- half, made in the still frame where a round of kubbs thrown in is judged).
local function kidLines(y)
	if not tw.plan.levels.kid then return { "kid match: not in this engine" } end
	local R = perf.tune.decideReps
	local lines = {}
	local function emit(l) out { l } end
	emit(string.format("kid match (ms; plan.solve %d each, the rest %d each, median [min-max]):", perf.tune.solveReps, R))
	local ok, err = pcall(function()
		local parts, o = {}, {}
		local kubbZ = plan.aimZFor("kubb")
		for _, d in ipairs { 2.0, 3.0, 6.0, "drill" } do
			local q = { projectile = "baton", px = 0, py = 2, tx = 0, ty = 2 + (type(d) == "number" and d or 0),
				release = plan.arcFor("baton", type(d) == "number" and d or nil),
				meter = plan.meter("kid"), surface = "grass", spin = 0, aimZ = kubbZ }
			if d == "drill" then q.projectile, q.ty, q.release, q.aimZ = "kubb", 6.0, plan.arcFor("drill"), 0 end
			local t0 = clock()
			for _ = 1, perf.tune.solveReps do plan.solve(q, o) end
			parts[#parts + 1] = string.format("%s %.2f", d == "drill" and "drill 4m" or (d .. "m"), (clock() - t0) * 1000 / perf.tune.solveReps)
			y()
		end
		emit("  plan.solve on the Kid meter from the Kid line: " .. table.concat(parts, ", "))
		-- the Kid computer's choose: its first baton, a toss, a field baton in a Kid match
		local m = cmatch.new { start = START, mode = "Vs Playdate", teams = teamsAt("kid"), cpu = { "B" }, rules = "kid" }
		local g = m.game
		local S = { base = cmatch.setup(m) }
		g:throwBaton(MISS); g:throwBaton({ toppled = { "b1" } })
		S.toss = cmatch.setup(m)
		while g.phase == "toss" do g:toss(lyingAt(0.4, 5.2, 0.3)) end
		pcall(function() g:raiseAll() end)
		S.field = cmatch.setup(m)
		parts = {}
		for _, k in ipairs { "base", "toss", "field" } do
			local st = S[k]
			if st then
				local xs, r = {}, autothrow.rng(1234)
				for i = 1, R do
					local t0 = clock()
					autothrow.choose(st, r, 1, "kid")
					xs[i] = (clock() - t0) * 1000
					y()
				end
				parts[#parts + 1] = string.format("%s (%s) %s", k, st.kind, fmtSpread(xs, "%.2f"))
			end
		end
		emit("  choose kid in a Kid match: " .. table.concat(parts, "; "))
		-- the fair spot with eight kubbs lying in the half (the raise need's context)
		local mb = stateB8("kid")
		local gb = mb.game
		local n = gb:need()
		local ctx = gb:context(n.side, n.kubb)
		ctx.half = ctx.half or n.side
		local xs = {}
		for i = 1, R do
			local t0 = clock()
			tw.raising.fairSpot(ctx)
			xs[i] = (clock() - t0) * 1000
			y()
		end
		emit("  raising.fairSpot, 8 lying in the half: " .. fmtSpread(xs, "%.1f"))
	end)
	if not ok then emit("  error: " .. tostring(err)) end
	return lines
end

local KEY = "perfbench-match"
local function startLines(y)
	local lines = { string.format("match start (ms, %d each; median [min-max]):", perf.tune.startReps) }
	local scene = tw.scenes.match
	local fresh, saveW, resume = {}, {}, {}
	local ok, err = pcall(function()
		for i = 1, perf.tune.startReps do
			collectgarbage("collect")
			local t0 = msNow()
			local s = scene.new(tw.input.device(), { vs = "B", noSave = true, noFile = true, cpuSeed = 7 })
			scene.enter()
			scene.update(s)
			scene.draw(s)
			fresh[i] = msNow() - t0
			y()
			-- a match at turn 3 (the setups' match), saved and resumed
			local m = cmatch.new { start = { year = 2026, month = 11, day = 20, hour = 12, min = 0 }, mode = "Vs Playdate" }
			local g = m.game
			g:throwBaton({}); g:throwBaton({ toppled = { "b1" } })
			cmatch.setup(m)
			local t1 = msNow()
			tw.save.write(m, { vs = "B" }, function(d) playdate.datastore.write(d, KEY) end)
			saveW[i] = msNow() - t1
			y()
			collectgarbage("collect")
			local t2 = msNow()
			local back = playdate.datastore.read(KEY)
			local rm, opts = tw.save.unpack(back)
			assert(rm, "unpack failed")
			local rs = scene.new(tw.input.device(), { vs = opts.vs, resume = rm, noSave = true, noFile = true })
			scene.enter()
			scene.update(rs)
			scene.draw(rs)
			resume[i] = msNow() - t2
			y()
		end
	end)
	playdate.datastore.delete(KEY)
	if not ok then return { "match start error: " .. tostring(err) } end
	lines[#lines + 1] = "  new match " .. fmtSpread(fresh, "%d") .. "; save " .. fmtSpread(saveW, "%d") .. "; resume (read, unpack, scene) " .. fmtSpread(resume, "%d")
	return lines
end

-- The drive (engine 0.16): what a plan under the knee costs. A drive's plan.solve at
-- the floor bisects (24 carries) and plan.arcFloor is one more solve; the scene
-- works the floor out only when ARC is stepped or B goes down (throw.arcFloor) and
-- solves only on a frame where something it reads changed, so with nothing
-- pressed an aim frame at a close kubb solves nothing.
local function driveLines(y)
	local lines = { string.format("drive (ms, %d each; the aim parts through the scene's update):", perf.tune.solveReps) }
	local parts = {}
	local out = {}
	local kubbZ = plan.aimZFor("kubb")
	for _, d in ipairs { 1.5, 3.0 } do
		local q = { projectile = "baton", px = 0, py = 0, tx = 0, ty = d, release = 0, meter = plan.meter(),
			surface = "grass", spin = 0, aimZ = kubbZ }
		local t0 = clock()
		for _ = 1, perf.tune.solveReps do plan.solve(q, out) end
		local tSolve = (clock() - t0) * 1000 / perf.tune.solveReps
		y()
		t0 = clock()
		local f
		for _ = 1, perf.tune.solveReps do f = plan.arcFloor(q) end
		local tFloor = (clock() - t0) * 1000 / perf.tune.solveReps
		parts[#parts + 1] = string.format("%gm solve at the floor (%.1f) %.2f, arcFloor %.2f", d, f, tSolve, tFloor)
		y()
	end
	lines[#lines + 1] = "  " .. table.concat(parts, "; ")
	-- (core 1.0) a kept drive raised to a new floor: release 0 (under the knee) with the
	-- stance walking back 4 mm a solve, then the circle moving away 4 mm a solve, so no
	-- solve repeats a geometry the engine has seen (what the scene's guard holds back while
	-- the circle or the stance moves, docs/notes/throw.md "The drive"): mean and max a solve
	parts = {}
	for _, d in ipairs { 1.5, 3.0 } do
		local res = {}
		for _, moving in ipairs { "stance", "circle" } do
			local q = { projectile = "baton", px = 0, py = 0, tx = 0, ty = d, release = 0, meter = plan.meter(),
				surface = "grass", spin = 0, aimZ = kubbZ }
			local sum, worst = 0, 0
			for i = 1, perf.tune.solveReps do
				if moving == "stance" then q.py = -i * 0.004 else q.ty = d + i * 0.004 end
				local t0 = clock()
				plan.solve(q, out)
				local t = clock() - t0
				sum = sum + t
				if t > worst then worst = t end
			end
			res[#res + 1] = string.format("%s %.2f (max %.2f)", moving == "stance" and "walking" or "circle",
				sum * 1000 / perf.tune.solveReps, worst * 1000)
			y()
		end
		parts[#parts + 1] = string.format("%gm %s", d, table.concat(res, ", "))
	end
	lines[#lines + 1] = "  a kept drive raised to a new floor: " .. table.concat(parts, "; ")
	-- the aim at a kubb 1.5 m from the advantage line 3.5 m up
	local solve = plan.solve
	local count = 0
	plan.solve = function(q, o) count = count + 1; return solve(q, o) end
	local ok, err = pcall(function()
		local B = { "b" }
		local n = perf.tune.aimFrames
		local steps = { { n = 1 }, { n = n }, { n = n, hold = B } }
		local tapPart = {}
		for i = 1, n do
			-- down five times (to the floor and past it), then up twice
			local key = (i % 3 == 1) and ((i <= 15) and "down" or (i <= 21 and "up" or nil)) or nil
			tapPart[i] = key and { hold = B, press = { key } } or { hold = B }
		end
		for i = 1, n do steps[#steps + 1] = tapPart[i] end
		local s = throw.new(tw.input.scripted(steps, 1 / 50))
		throw.enter()
		throw.prepare(s, clusterSetup(3.5))
		throw.setStance(s, 1.0, 3.5)
		throw.aimAt(s, 1.0, 5.0)
		throw.update(s)
		throw.draw(s)
		y()
		for _, label in ipairs { "nothing pressed", "B held", "B held, down and up" } do
			count = 0
			local floors = throw.floorSolves or 0
			local upS, upM, drS, drM = 0, 0, 0, 0
			for _ = 1, n do
				local t0 = clock()
				throw.update(s)
				local t1 = clock()
				throw.draw(s)
				local t2 = clock()
				upS, drS = upS + (t1 - t0), drS + (t2 - t1)
				if t1 - t0 > upM then upM = t1 - t0 end
				if t2 - t1 > drM then drM = t2 - t1 end
				y()
			end
			lines[#lines + 1] = string.format("  aim 1.5m %-20s %d frames: update %.2f ms (max %.2f), draw %.1f ms (max %.1f), plan.solve calls %d (floor %d), release %.1f",
				label, n, upS * 1000 / n, upM * 1000, drS * 1000 / n, drM * 1000, count, (throw.floorSolves or 0) - floors,
				s.sol.release)
		end
	end)
	plan.solve = solve
	if not ok then lines[#lines + 1] = "  drive aim error: " .. tostring(err) end
	return lines
end

local function body()
	local y = coroutine.yield
	local t = playdate.getTime()
	local v = tw.version or {}
	out { string.format("perfbench %04d-%02d-%02d %02d:%02d; version %s; build %s; memory %.0f KB",
		t.year, t.month, t.day, t.hour, t.minute, v.text or "?", tostring(v.build or "?"), kb()) }
	y()
	out(startLines(y))
	y()
	out(solveLines(y))
	y()
	out(chooseLines(y))
	y()
	out(decideLines(y))
	y()
	out(turnLines(y))
	y()
	out(kidLines(y))
	y()
	out(aimLines(y))
	y()
	out(dpadLines(y))
	y()
	out(driveLines(y))
	y()
	out(throwLines(y))
	y()
	collectgarbage("collect")
	out { string.format("memory after a full collection %.0f KB", kb()), "perfbench done", "" }
end

function perf.start()
	playdate.file.delete(perf.flag)
	local rec = tw.recorder
	local a = { co = coroutine.create(body), recOn = rec.on, logOn = tw.framelog.on }
	rec.on = false
	rec.clear()
	tw.framelog.on = false
	playdate.setAutoLockDisabled(true)
	return a
end

local function finish(a)
	local rec = tw.recorder
	rec.clear()
	rec.on = a.recOn
	tw.framelog.on = a.logOn
	playdate.setAutoLockDisabled(tw.noLock and true or false)
	return true
end

-- One frame. Returns true when finished.
function perf.update(a)
	local ok, err = coroutine.resume(a.co)
	if not ok then
		out { "perfbench error: " .. tostring(err) }
		return finish(a)
	end
	if coroutine.status(a.co) == "dead" then return finish(a) end
	return false
end

tw.perfbench = perf
