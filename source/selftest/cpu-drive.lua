-- Scenario "cpu-drive": the computer's drive (Kubb Engine 0.18: at club and pro it plans
-- every baton but the king shot on a person's default line, plan.arcFor, which is a drive
-- close in; docs/notes/throw.md "The computer's drive"). VS PLAYDATE with the Playdate at
-- club, resumed (as a saved match is) at turn 4: the person left a field kubb standing in
-- the Playdate's half, so it throws from that advantage line at a group of field kubbs
-- about 1.7 to 2.2 m away (the perf check's eight-kubb position, perfbench stateA8, nearer).
-- Every throw is shown at rest at once until the Playdate's first baton planned under
-- the knee (half past 5, plan.tune.driveKneeDeg); that throw is played out as a player
-- sees it: its aim held for cpuThink (WATCH, its bars on the clock), its arm on the clock,
-- the flight and the rest. Checks:
--   the computer's plan is the person's default line (plan.arcFor by the distance) and
--     under the knee, and a baton it plans in the no-turn part of the drive (a release
--     loft of -4 or under, plan.tune.driveTurnToDeg) leaves with no end over end turn:
--     its axis stays up (z 0.5 or more) until it touches anything
--   the throw comes to rest and the engine rules on it, as for any baton
-- It times every autothrow.choose the scene makes (the Playdate plans on the device: the
-- frame its aim is shown). The Simulator's times are the Mac's, for the shape only.
-- Frames: 1 the Playdate's aim at the drive (WATCH), 2 its arm on the clock, 3 the drive
-- in flight, 4 at rest.
import "selftest/_match"
import "core/autothrow"
import "core/match"

local st = tw.selftest
local plan, autothrow, cmatch = tw.plan, tw.autothrow, tw.match
local fmt, abs = string.format, math.abs

-- The position (made when the scenario starts, never at import): VS PLAYDATE, the
-- Playdate at club. Turn 1 and 2 as the perf check's stateB8; in turn 3 the person
-- fells seven of the eight field kubbs, leaving one for the Playdate's advantage line,
-- and its kubbs are tossed in lying in a tight group (two rows of four) 3.6 m out.
local MISS = {}
local function lyingAt(x, y, a) return { rest = { x = x, y = y, standing = false, angle = a }, moved = {} } end
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
local function position()
	local m = cmatch.new { start = { year = 2026, month = 11, day = 22, hour = 12, min = 0 }, mode = "Vs Playdate",
		teams = { A = { name = "You", players = { { name = "You" } } },
			B = { name = "Playdate", players = { { name = "Playdate", level = "club" } } } },
		cpu = { "B" } }
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
	while g:need().kind == "raise" do g:raise(nil) end
	fk = standingField(g)
	g:throwBaton({ toppled = { fk[1], fk[2], fk[3], fk[4] } }); g:throwBaton({ toppled = { fk[5], fk[6], fk[7] } })
	while g.phase ~= "toss" do g:throwBaton(MISS) end
	tossGrid(g, 3.6, 1)
	return m
end

local times = { all = {}, drive = {} }
local choose = nil

local function worst(xs)
	local w = 0
	for _, x in ipairs(xs) do if x > w then w = x end end
	return w
end

local def   -- (the step reads def.ms: declared before the table)
def = {
	opts = { vs = "B", seed = 5, cpuSeed = 7, instant = true, maxTurns = 30, cpuThink = 0.6, noSave = true },
	refreshRate = 0,
	maxFrames = 30000,
	step = function(ms, ctx, h)
		def.ms = ms
		local ok, err = pcall(function()
			local s, ts = ms.setup, ms.ts
			if ms.phase == "handoff" then
				if s and s.side == "B" then error("a hand-off card before the Playdate's turn") end
				if h.idle() then h.pressA() end
			end
			local a = ms.cpuAim
			if not ctx.drive and a and s.projectile == "baton" and a.plan
				and a.plan.release < plan.tune.driveKneeDeg then
				-- the Playdate's first drive: play it out as a player sees it
				local P = a.plan
				local d = P.dist or 0
				local want = plan.arcFor("baton", d)
				if a.on ~= "king" and abs(P.release - want) > 0.05 and P.release < want then
					error(fmt("the computer's drive at %.2f m: release %.2f under the line's %.2f", d, P.release, want))
				end
				ctx.drive = { release = P.release, loft = P.loft, dist = d, tumble = a.tumbleRate, on = a.on }
				ctx.minAz, ctx.flightFrames = 1, 0
				ts.instant = false
			end
			local D = ctx.drive
			if D and not D.done then
				if not D.shotAim and ts.mode == "aim" and ms.cpuWait > 0.3 then
					D.shotAim = true
					if ts.promptText ~= "WATCH" then error("the Playdate's aim says " .. tostring(ts.promptText)) end
					ctx:capture()                                                             -- 1
				elseif not D.shotSwing and ts.mode == "cpuswing" and ts.cpuPhase == "swinging" then
					D.shotSwing = true
					ctx:capture()                                                             -- 2
				elseif ts.mode == "flight" then
					D.flew = true
					ctx.flightFrames = ctx.flightFrames + 1
					if (st.sinceContact(ts) or -1) < 0 then
						local az = abs(ts.baton.az or 1)
						if az < ctx.minAz then ctx.minAz = az end
						if not D.shotFlight and ts.showTime > 0.06 and st.batonOnScreen(ts) then
							D.shotFlight = true
							ctx:capture()                                                     -- 3
						end
					end
				elseif D.flew and (ts.mode == "rest" or ts.mode == "done") then
					D.restN = (D.restN or 0) + 1
					if D.restN == 20 or ts.mode == "done" then
						if not D.shotFlight then ctx:capture() end
						ctx:capture()                                                         -- 4
						D.done = true
						if not D.shotAim or not D.shotSwing then error("the drive's aim or swing was not shown") end
						local L = ts.last
						if plan.loftFor(D.release) <= plan.tune.driveTurnToDeg and ctx.minAz < 0.5 then
							error(fmt("the computer's drive turned in the air: axis z down to %.2f", ctx.minAz))
						end
						ctx.found = fmt("drive at %.2f m on %s: release %.2f loft %.1f, launched loft %.1f v %.2f tumble %.2f, minAz %.2f, %d flight frames",
							D.dist, tostring(D.on), D.release, D.loft, L and L.launchLoft or 0, L and L.launchSpeed or 0,
							D.tumble or 0, ctx.minAz, ctx.flightFrames)
					end
				end
			end
		end)
		if not ok then
			autothrow.choose = choose
			error(err, 0)
		end
		if ctx.drive and ctx.drive.done then
			autothrow.choose = choose
			ctx.note = ctx.note .. fmt(" %s; choose (Mac ms): %d made, worst %.2f; %d under the knee, worst %.2f; turn %d",
				ctx.found, #times.all, worst(times.all), #times.drive, worst(times.drive), ms.m.game.turn)
			return true
		end
		if ms.phase == "over" then
			autothrow.choose = choose
			error("the match ended with no drive from the Playdate (" .. #times.all .. " throws chosen)")
		end
		return false
	end,
}
local inner = st.matchScenario(def)
st.scenarios["cpu-drive"] = {
	step = function(ctx)
		if not def.opts.resume then
			def.opts.resume = position()
			-- time every choose the match scene makes, from its first frame
			choose = autothrow.choose
			autothrow.choose = function(...)
				local t0 = playdate.getElapsedTime()
				local a = choose(...)
				local dt = (playdate.getElapsedTime() - t0) * 1000
				-- the Playdate's throws only (the person's here are scripted by autothrow too;
				-- the first frame's, before def.ms is known, is the Playdate's)
				local ms = def.ms
				if ms and not (ms.setup and ms.setup.side == "B") then return a end
				times.all[#times.all + 1] = dt
				if a and a.plan and a.plan.release and a.plan.release < plan.tune.driveKneeDeg then
					times.drive[#times.drive + 1] = dt
				end
				return a
			end
		end
		return inner.step(ctx)
	end,
}
