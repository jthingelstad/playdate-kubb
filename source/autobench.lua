-- The device autobench: when a file named `autobench` is in the game's Data
-- folder at launch, the game deletes it, runs this, appends every figure to
-- bench.txt in the Data folder and then carries on into the normal game.
-- Nobody needs to press anything, so a build can be measured on the device
-- over USB (AGENTS.md, "Measuring on the device").
--
-- Sections: the micro benchmarks of core/microbench, the core/bench physics
-- scenario (garbage made with the collector stopped, the plain timing line,
-- the per-phase profile), draw timings of the throw scene by frame type
-- (aim with the camera still, swivelling, walking, a full throw split into
-- flight, impact and rest) and a few drawing primitives.
import "CoreLibs/graphics"
import "core/tw"
import "core/bench"
import "core/microbench"
import "core/world"
import "input"
import "scenes/throw"
import "render/world"
import "render/hud"
import "core/save"
import "core/match"
import "render/burst"

local gfx <const> = playdate.graphics
local bench, throw, render, hud = tw.bench, tw.scenes.throw, tw.render.world, tw.render.hud
local clock = playdate.getElapsedTime

local auto = {}
auto.flag = "autobench"

local function out(lines)
	local f = playdate.file.open("bench.txt", playdate.file.kFileAppend)
	if not f then return end
	for _, l in ipairs(lines) do f:write(l .. "\n") end
	f:close()
end

local function kb() return collectgarbage("count") end

local function stats()
	local s = playdate.getStats and playdate.getStats()
	if not s then return "stats n/a" end
	local parts = {}
	for k, v in pairs(s) do parts[#parts + 1] = string.format("%s %.0f%%", k, v) end
	table.sort(parts)
	return table.concat(parts, ", ")
end

-- A frame-timing accumulator: avg and max of update and draw per class.
local function newTimes() return {} end
local function add(T, class, up, dr)
	local r = T[class]
	if not r then r = { n = 0, up = 0, dr = 0, upMax = 0, drMax = 0, totMax = 0 }; T[class] = r end
	r.n = r.n + 1
	r.up, r.dr = r.up + up, r.dr + dr
	if up > r.upMax then r.upMax = up end
	if dr > r.drMax then r.drMax = dr end
	if up + dr > r.totMax then r.totMax = up + dr end
end
local function timesLines(T, order)
	local l = {}
	for _, class in ipairs(order) do
		local r = T[class]
		if r then
			local avg = (r.up + r.dr) * 1000 / r.n
			l[#l + 1] = string.format("  %-14s %3d frames: update %.1f ms (max %.1f), draw %.1f ms (max %.1f), total %.1f ms (max %.1f) = %.1f fps",
				class, r.n, r.up * 1000 / r.n, r.upMax * 1000, r.dr * 1000 / r.n, r.drMax * 1000, avg,
				r.totMax * 1000, math.min(50, 1000 / avg))
		end
	end
	return l
end

local function profLines(P, frames, title)
	local keys = {}
	for k, v in pairs(P) do if type(v) == "number" then keys[#keys + 1] = k end end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = string.format("%s %.2f", k, P[k] * 1000 / frames) end
	return "  " .. title .. " (ms/frame): " .. table.concat(parts, ", ")
end

-- The hit throw of the self-tests: center of the baseline, loft 30, onto b3.
local function hitScript()
	local sign = tw.swing.tune.forwardSign
	local flick = {}
	for i, d in ipairs { 6, 12, 18, 22, 24, 24, 24 } do flick[i] = sign * d end
	return {
		{ n = 5 },
		{ crank = -sign * 120 / 30, n = 30 },
		{ n = 5 },
		{ cranks = flick },
		{ n = 400 },
	}
end

-- The match case: core/bench's match setup (a turn in progress: field kubbs,
-- the turn's debris) and its throws (a baton that hits, one that misses and
-- rolls on, a drilled kubb), each played through the throw scene as in a
-- match, on the device's own clock (input.device: nobody presses anything).
-- Each throw's figures are the frame-time log's (frames.jsonl), captured
-- here instead of written; frames.jsonl is not touched. One summary line per
-- throw: shown frames, seconds, mean and max frame ms, starved frames and the
-- longest stall, steps, physics ms, and the shown speed (simulated seconds
-- over shown seconds; 1 = real time), then the raw log line.
-- label names the run; tune ({field = value} for throw.tune, render.world
-- .tune and playback.paceTune) is applied for the run and then restored.
-- Besides the log's figures each throw reports the flight frames' dt spread
-- (sd), the calm frames held, the lowest pace, the frames drawn from the
-- layer, the cache or from scratch, and the seconds from release to rest.
--
-- prof (optional) also splits every flight frame's cost: the draw's mean and
-- max and its parts (render/world by its own laps and the HUD functions), the display (from the end of the draw to the next frame), and
-- the scene's estimate of the two (drawEst + postEst), which is what the
-- physics loses from each 40 ms frame. Timing these costs a few clock calls a
-- frame, so a profiled run is a little slower than a plain one.
local function wrapTimed(D, list)
	local saved, depth = {}, 0
	for _, w in ipairs(list) do
		local T, k, slot = w[1], w[2], w[3]
		local f = T[k]
		saved[#saved + 1] = { T, k, f }
		T[k] = function(...)
			if depth > 0 or not D.on then return f(...) end
			depth = 1
			local t0 = clock()
			local a, b, c = f(...)
			D[slot] = D[slot] + clock() - t0
			depth = 0
			return a, b, c
		end
	end
	return function()
		for i = #saved, 1, -1 do local e = saved[i]; e[1][e[2]] = e[3] end
	end
end

function auto.matchCase(y, label, tune, prof)
	local fl, ft = tw.framelog, tw.frametel
	local write = fl.write
	local got = {}
	fl.write = function(t, info)
		got.t, got.info = t, info
		info.time = "autobench"
		got.line = ft.encode(t, info)
	end
	local lines = { "match case " .. (label or "") .. " (per throw: shown frames, s, mean/max frame ms, starved, stall ms, steps, phys ms, shown speed x real time):" }
	local saved = {}
	local tables = { throw.tune, render.tune, tw.playback.paceTune, tw.render.burst.tune }
	for k, v in pairs(tune or {}) do
		for _, T in ipairs(tables) do
			if T[k] ~= nil then saved[#saved + 1] = { T, k, T[k] }; T[k] = v end
		end
	end
	render.invalidate()
	-- the profiled run's per-frame split (flight frames only)
	local D = { on = false }
	local unwrap
	if prof then
		local list = { { render, "draw", "world" }, { tw.render.burst, "draw", "burst" } }
		for k, v in pairs(hud) do
			if type(v) == "function" and k ~= "short" and k ~= "readoutText" and k ~= "drillReadoutText" then
				list[#list + 1] = { hud, k, "hud" }
			end
		end
		unwrap = wrapTimed(D, list)
	end
	local ok, err = pcall(function()
		local s = throw.new(tw.input.device())
		s.sceneName = "match"
		throw.enter()
		local tot = { frames = 0, secs = 0, starved = 0, steps = 0, phys = 0, sim = 0, max = 0 }
		for _, t in ipairs(bench.matchThrows) do
			collectgarbage("collect")
			throw.prepare(s, bench.matchSetup(t.projectile))
			for _ = 1, 3 do throw.draw(s); y() end
			s.input:advance()
			throw.autoLaunch(s, bench.matchThrow(t))
			got.line = nil
			local n = 0
			local C = render.count
			C.cached, C.layer, C.built, C.full = 0, 0, 0, 0
			local sum, sum2, nf, minPace, wall, restAt = 0, 0, 0, 1, 0, nil
			D.world, D.burst, D.hud, D.n, D.draw, D.drawMax, D.post, D.postMax, D.np, D.est =
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0
			local RPm = prof and { clock = clock } or nil
			local lastEnd, lastFlying = nil, false
			while s.mode ~= "done" and n < 3000 do
				local flying = s.mode == "flight"
				throw.update(s)
				local raw = s.input.raw or 0
				if n > 0 and not restAt then wall = wall + raw end
				if flying then
					nf, sum, sum2 = nf + 1, sum + raw, sum2 + raw * raw
					if s.pb and s.pb.v < minPace then minPace = s.pb.v end
				end
				if prof and lastFlying and lastEnd then
					local post = raw - lastEnd
					if post < 0 then post = 0 end
					D.np, D.post = D.np + 1, D.post + post
					if post > D.postMax then D.postMax = post end
				end
				if s.mode == "rest" and not restAt then restAt = n end
				local profThis = prof and flying and s.mode == "flight"
				if profThis then
					D.est = D.est + s.drawEst + s.postEst
					D.on = true
					render.prof = RPm
				end
				throw.draw(s)
				render.prof = nil
				D.on = false
				if profThis then
					local d = (s.drawEnd or 0) - (s.drawStart or 0)
					D.n, D.draw = D.n + 1, D.draw + d
					if d > D.drawMax then D.drawMax = d end
				end
				lastEnd, lastFlying = s.drawEnd, profThis
				y()
				n = n + 1
			end
			local held = s.held
			local counts = string.format("cached %d layer %d (built %d) full %d", C.cached, C.layer, C.built, C.full)
			local T, I = got.t, got.info
			if not got.line then
				lines[#lines + 1] = "  " .. t.name .. ": no log line (" .. s.mode .. ")"
			else
				local frames = T.n1 + T.n2 + T.n3
				local secs = T.s1 + T.s2 + T.s3
				local mx = math.max(T.m1, T.m2, T.m3)
				local sim = I.steps * tw.world.tune.dt
				lines[#lines + 1] = string.format("  %-5s %4d frames %5.2f s  mean %5.1f ms  max %5.1f ms  starved %4d  stall %6.0f ms  steps %4d  phys %6.0f ms (%.2f ms/step)  speed %.2f",
					t.name, frames, secs, secs * 1000 / frames, mx * 1000, T.starved, T.stall * 1000, I.steps,
					I.phys * 1000, I.phys * 1000 / I.steps, sim / secs)
				local mean = nf > 0 and sum / nf or 0
				local sd = nf > 1 and math.sqrt(math.max(0, sum2 / nf - mean * mean)) or 0
				lines[#lines + 1] = string.format("    release to rest %.2f s; flight frames %d, dt sd %.1f ms; held %d; min pace %.2f; draws: %s",
					wall, nf, sd * 1000, held, minPace, counts)
				lines[#lines + 1] = "    " .. got.line
				if prof and D.n > 0 then
					local k = 1000 / D.n
					lines[#lines + 1] = string.format("    flight frames %d: draw mean %.1f ms (max %.1f) = world %.1f + burst %.2f + hud %.1f + other %.1f; display mean %.1f ms (max %.1f); estimate taken from the physics mean %.1f ms",
						D.n, D.draw * k, D.drawMax * 1000, D.world * k, D.burst * k, D.hud * k,
						(D.draw - D.world - D.burst - D.hud) * k, D.np > 0 and D.post * 1000 / D.np or 0,
						D.postMax * 1000, D.est * k)
					lines[#lines + 1] = profLines(RPm, D.n, "  render/world")
				end
				tot.frames, tot.secs, tot.starved = tot.frames + frames, tot.secs + secs, tot.starved + T.starved
				tot.steps, tot.phys, tot.sim = tot.steps + I.steps, tot.phys + I.phys, tot.sim + sim
				if mx > tot.max then tot.max = mx end
			end
		end
		if tot.frames > 0 then
			lines[#lines + 1] = string.format("  all   %4d frames %5.2f s  mean %5.1f ms  max %5.1f ms  starved %4d  steps %4d  phys %6.0f ms (%.2f ms/step)  speed %.2f",
				tot.frames, tot.secs, tot.secs * 1000 / tot.frames, tot.max * 1000, tot.starved, tot.steps,
				tot.phys * 1000, tot.phys * 1000 / tot.steps, tot.sim / tot.secs)
		end
	end)
	fl.write = write
	render.prof = nil
	if unwrap then unwrap() end
	for i = #saved, 1, -1 do local e = saved[i]; e[1][e[2]] = e[3] end
	render.invalidate()
	if not ok then lines[#lines + 1] = "  match case error: " .. tostring(err) end
	return lines
end

local function body()
	local y = coroutine.yield
	local t = playdate.getTime()
	out { string.format("autobench %04d-%02d-%02d %02d:%02d; memory %.0f KB", t.year, t.month, t.day,
		t.hour, t.minute, kb()) }
	if playdate.setStatsInterval then playdate.setStatsInterval(0.5) end
	y()

	-- micro benchmarks
	local mb = tw.microbench.run(clock, 4000)
	local l = { "micro (ns per iteration, empty loop removed):" }
	for _, s in ipairs(tw.microbench.lines(mb)) do l[#l + 1] = s end
	out(l)
	y()

	-- the resume save (core/save, playdate.datastore): a match at turn 5 with
	-- kubbs thrown in, packed and written, then read and unpacked, as the
	-- match scene does before every throw
	do
		local m = tw.match.new { start = { year = 2026, month = 11, day = 13, hour = 21, min = 0 } }
		local g = m.game
		local MISS = {}
		g:throwBaton(MISS); g:throwBaton(MISS)
		g:throwBaton({ toppled = { "a1" } }); g:throwBaton({ toppled = { "a2" } }); g:throwBaton(MISS); g:throwBaton(MISS)
		g:toss({ rest = { x = 0.5, y = 6.0, standing = false, angle = 0.4 }, moved = {} })
		g:toss({ rest = { x = -0.8, y = 5.5, standing = false, angle = 1.2 }, moved = {} })
		g:raiseAll()
		for _ = 1, 6 do if g.phase == "batons" then g:throwBaton(MISS) end end
		local t0 = clock()
		local t1 = t0
		tw.save.write(m, { names = { A = "Ash", B = "Birch" } }, function(d)
			t1 = clock()
			playdate.datastore.write(d, "benchsave")
		end)
		local t2 = clock()
		local back = playdate.datastore.read("benchsave")
		local t3 = clock()
		local ok = tw.save.unpack(back) ~= nil
		local t4 = clock()
		playdate.datastore.delete("benchsave")
		out { string.format("resume save (turn %d): pack %.1f ms, write %.1f ms, read %.1f ms, unpack %.1f ms%s",
			g.turn, (t1 - t0) * 1000, (t2 - t1) * 1000, (t3 - t2) * 1000, (t4 - t3) * 1000, ok and "" or " (unpack failed)") }
		y()
	end
	-- garbage made by the physics: the collector stopped for the run
	collectgarbage("collect")
	playdate.setCollectsGarbage(false)
	collectgarbage("stop")
	local k0 = kb()
	local r0 = bench.run(clock, 24, function() y() end)
	local k1 = kb()
	collectgarbage("restart")
	playdate.setCollectsGarbage(true)
	out { string.format("gc stopped: %.1f KB made in %d steps (%.3f KB/step); %.3f ms/step, collision %.3f ms/step",
		k1 - k0, r0.steps, (k1 - k0) / r0.steps, r0.msPerStep, r0.hotMsPerStep) }
	collectgarbage("collect")
	y()

	-- the plain bench line (as the System Menu bench writes it)
	local r = bench.run(clock, 24, function() y() end)
	out { bench.line(r, "device") .. "; " .. stats() }
	y()
	-- the same throw with a full turn's debris lying on the pitch (asleep)
	local rd = bench.run(clock, 24, function() y() end, true)
	out { bench.line(rd, "device with debris") }
	y()

	-- the match case
	out(auto.matchCase(y, "(defaults)"))
	y()
	out(auto.matchCase(y, "(framePeriod 50 ms)", { framePeriod = 0.050 }))
	y()
	out(auto.matchCase(y, "(framePeriod 33 ms)", { framePeriod = 0.033 }))
	y()
	out(auto.matchCase(y, "(no layer)", { layer = false }))
	y()
	out(auto.matchCase(y, "(camera holds on the impact: frameRadius 0)", { frameRadius = 0 }))
	y()
	-- where the draw goes, and what each part of the Woodcut ground costs in
	-- shown speed (each variant switches one part off)
	out(auto.matchCase(y, "(defaults, profiled)", nil, true))
	y()
	out(auto.matchCase(y, "(no bursts)", { on = false }))
	y()
	out(auto.matchCase(y, "(no rough)", { rough = false }))
	y()
	out(auto.matchCase(y, "(estimates jump to the slowest frame)", { estRise = 1 }))
	y()
	out(auto.matchCase(y, "(1 px pitch lines and outlines)", { lineWidth = 1, stakeWidth = 1, thickFrom = 100000 }))
	y()
	-- its physics alone, with the lone flight off and on
	local lone = tw.world.loneFlight
	for _, on in ipairs { false, true } do
		tw.world.loneFlight = on
		collectgarbage("collect")
		out { bench.matchPhysics(clock, function() y() end) }
		y()
	end
	tw.world.loneFlight = lone

	-- per-phase profile
	local pl = bench.profile(clock, 24, function() y() end)
	table.insert(pl, 1, "physics profile (ms per step by phase; clock overhead included):")
	out(pl)
	y()

	-- drawing: the aim view with the camera still
	local s = throw.new(tw.input.scripted({ { n = 100000 } }))
	throw.enter()
	throw.update(s)
	local T = newTimes()
	local RP = { clock = clock }
	render.prof = RP
	local frames = 30
	for _ = 1, frames do
		local t0 = clock()
		throw.update(s)
		local t1 = clock()
		throw.draw(s)
		add(T, "aim still", t1 - t0, clock() - t1)
		y()
	end
	render.prof = nil
	l = timesLines(T, { "aim still" })
	l[#l + 1] = profLines(RP, frames, "aim still render/world")
	-- the HUD parts one by one
	local hs = s.hudState
	local function each(name, fn)
		local t0 = clock()
		for _ = 1, 10 do fn() end
		return string.format("%s %.2f", name, (clock() - t0) * 100)
	end
	local ft = tw.flight.tune
	l[#l + 1] = "  hud (ms): " .. table.concat({
		each("minimap", function() hud.minimap(hs) end),
		each("rail", function() hud.rail("PRACTICE", "baton", 2, 6, "FIELD 2", "BASE 5") end),
		each("plaque", function() hud.plaque(s.loftDeg, nil) end),
		each("gauge", function() hud.gauge("idle", 0, 0, tw.swing.tune.fullBackswingDeg, 0) end),
		each("chip", function() hud.chip(0.8) end),
		each("readout", function() hud.readout("P 0.80  S 0.90  tilt 3  LEGAL  7.10 m  down 1") end),
	}, ", ")
	-- primitives
	local img = gfx.image.new(400, 240, gfx.kColorWhite)
	local txt = "*crank back past the bottom*"
	local tw_, th_ = gfx.getTextSize(txt)
	local timg = gfx.image.new(tw_, th_, gfx.kColorClear)
	gfx.pushContext(timg); gfx.drawText(txt, 0, 0); gfx.popContext()
	local pat = render.tune.roughPattern
	local tuft = gfx.image.new(15, 11, gfx.kColorClear)
	gfx.pushContext(tuft); gfx.setLineWidth(2); gfx.drawLine(7, 10, 3, 3); gfx.drawLine(7, 10, 7, 1); gfx.drawLine(7, 10, 11, 3); gfx.setLineWidth(1); gfx.popContext()
	l[#l + 1] = "  primitives (ms): " .. table.concat({
		each("clear", function() gfx.clear(gfx.kColorWhite) end),
		each("image 400x240 draw", function() img:draw(0, 0) end),
		each("fillRect 400x240 pattern", function() gfx.setPattern(pat); gfx.fillRect(0, 0, 400, 240); gfx.setColor(gfx.kColorBlack) end),
		each("fillRect 400x120 pattern", function() gfx.setPattern(pat); gfx.fillRect(0, 120, 400, 120); gfx.setColor(gfx.kColorBlack) end),
		each("fillPolygon 400x120 pattern", function() gfx.setPattern(pat); gfx.fillPolygon(0, 120, 400, 120, 400, 240, 0, 240); gfx.setColor(gfx.kColorBlack) end),
		each("fillPolygon 400x120 black", function() gfx.fillPolygon(0, 120, 400, 120, 400, 240, 0, 240) end),
		each("drawText label", function() gfx.drawText(txt, 100, 100) end),
		each("label image draw", function() timg:draw(100, 100) end),
		each("100 setDitherPattern", function() for _ = 1, 100 do gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2) end; gfx.setColor(gfx.kColorBlack) end),
		each("100 setPattern", function() for _ = 1, 100 do gfx.setPattern(pat) end; gfx.setColor(gfx.kColorBlack) end),
		each("100 fillPolygon 8px quad", function() for i = 1, 100 do gfx.fillPolygon(i, 50, i + 8, 50, i + 8, 58, i, 58) end end),
		each("100 drawPolygon 8px quad", function() for i = 1, 100 do gfx.drawPolygon(i, 50, i + 8, 50, i + 8, 58, i, 58) end end),
		each("100 fillRect 8px", function() for i = 1, 100 do gfx.fillRect(i, 50, 8, 8) end end),
		each("100 drawLine", function() for i = 1, 100 do gfx.drawLine(i, 50, i + 30, 80) end end),
		each("100 drawLine 2px", function() gfx.setLineWidth(2); for i = 1, 100 do gfx.drawLine(i, 50, i + 30, 80) end; gfx.setLineWidth(1) end),
		each("100 drawPolygon 8px quad 2px", function() gfx.setLineWidth(2); for i = 1, 100 do gfx.drawPolygon(i, 50, i + 8, 50, i + 8, 58, i, 58) end; gfx.setLineWidth(1) end),
		each("100 drawPolygon 30px quad 2px", function() gfx.setLineWidth(2); for i = 1, 100 do gfx.drawPolygon(i, 50, i + 12, 48, i + 14, 80, i, 82) end; gfx.setLineWidth(1) end),
		each("100 drawPolygon 30px quad", function() for i = 1, 100 do gfx.drawPolygon(i, 50, i + 12, 48, i + 14, 80, i, 82) end end),
		each("100 image 15x11 draw", function() for i = 1, 100 do tuft:draw(i, 60) end end),
	}, ", ")
	out(l)
	y()

	-- swivelling and walking
	local sign = tw.swing.tune.forwardSign
	for _, case in ipairs {
		{ "aim swivel", { { n = 60, hold = { "b" }, crank = -2 * sign } } },
		{ "aim walk", { { n = 60, hold = { "right" } } } },
	} do
		s = throw.new(tw.input.scripted(case[2]))
		throw.enter()
		RP = { clock = clock }
		render.prof = RP
		for _ = 1, 50 do
			local t0 = clock()
			throw.update(s)
			local t1 = clock()
			throw.draw(s)
			add(T, case[1], t1 - t0, clock() - t1)
			y()
		end
		render.prof = nil
		out { timesLines(T, { case[1] })[1], profLines(RP, 50, case[1] .. " render/world") }
	end

	-- a full throw: the hit of the self-tests
	collectgarbage("collect")
	local m0 = kb()
	s = throw.new(tw.input.scripted(hitScript()))
	s.loftDeg = 30
	throw.enter()
	local mMax, frames2, thrown = m0, 0, false
	local RPf, RPi = { clock = clock }, { clock = clock }
	local nf, ni = 0, 0
	while frames2 < 700 do
		frames2 = frames2 + 1
		local t0 = clock()
		throw.update(s)
		local t1 = clock()
		local class = s.mode
		if s.mode == "flight" then
			thrown = true
			local hit = s.pb and s.pb.w.firstHit
			class = (hit and s.showTime >= hit.t - 0.1) and "impact" or "flight"
		elseif s.mode == "aim" then
			if thrown then break end
			class = "aim (windup)"
		end
		if class == "flight" then render.prof = RPf; nf = nf + 1
		elseif class == "impact" then render.prof = RPi; ni = ni + 1
		else render.prof = nil end
		throw.draw(s)
		render.prof = nil
		add(T, class, t1 - t0, clock() - t1)
		local m = kb()
		if m > mMax then mMax = m end
		y()
	end
	local pb = s.pb
	l = timesLines(T, { "aim (windup)", "flight", "impact", "rest" })
	if nf > 0 then l[#l + 1] = profLines(RPf, nf, "flight render/world") end
	if ni > 0 then l[#l + 1] = profLines(RPi, ni, "impact render/world") end
	local res = s.result
	l[#l + 1] = string.format("  throw: %d frames, first hit %s, toppled %d; memory %.0f KB before, max %.0f KB; %s",
		frames2, tostring(res and res.firstHit and res.firstHit.with), res and #res.toppled or -1, m0, mMax, stats())
	out(l)
	out { "autobench done", "" }
end

-- The bench's scripted throws are not real swings: the crank recorder and
-- the frame-time log are off while it runs and put back afterwards
-- (auto.update), error or not. Auto-lock is off for the run, on again after.
function auto.start()
	playdate.file.delete(auto.flag)
	local rec = tw.recorder
	local a = { co = coroutine.create(body), recOn = rec.on, logOn = tw.framelog.on }
	rec.on = false
	rec.clear()
	tw.framelog.on = false
	-- a bench run is minutes with nobody pressing anything: no auto-lock
	-- until it is done (finish turns it back on)
	playdate.setAutoLockDisabled(true)
	return a
end

local function finish(a)
	local rec = tw.recorder
	rec.clear()
	rec.on = a.recOn
	tw.framelog.on = a.logOn
	playdate.setAutoLockDisabled(tw.noLock and true or false)   -- main.lua's "nolock"
	return true
end

-- One frame. Returns true when finished.
function auto.update(a)
	local ok, err = coroutine.resume(a.co)
	if not ok then
		out { "autobench error: " .. tostring(err) }
		return finish(a)
	end
	if coroutine.status(a.co) == "dead" then return finish(a) end
	return false
end

tw.autobench = auto
