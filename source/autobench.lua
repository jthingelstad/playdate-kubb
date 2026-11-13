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
		each("panel", function() hud.panel(s.loftDeg, ft.loftMinDeg, ft.loftMaxDeg, nil, 0.8) end),
		each("gauge", function() hud.swingGauge("idle", 0, 0, tw.swing.tune.fullBackswingDeg, false, nil, nil, 0) end),
		each("gauge thrown", function() hud.swingGauge("idle", 0, 0, tw.swing.tune.fullBackswingDeg, true, true, 0.8, 0) end),
		each("readout", function() hud.readout("P 0.80  S 0.90  tilt 3  LEGAL  7.10 m  down 1") end),
	}, ", ")
	-- primitives
	local img = gfx.image.new(400, 240, gfx.kColorWhite)
	local txt = "*crank back past the bottom*"
	local tw_, th_ = gfx.getTextSize(txt)
	local timg = gfx.image.new(tw_, th_, gfx.kColorClear)
	gfx.pushContext(timg); gfx.drawText(txt, 0, 0); gfx.popContext()
	local pat = render.tune.outsidePattern
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

-- The bench's scripted throws are not real swings: the crank recorder is
-- off while it runs and put back afterwards (auto.update), error or not.
function auto.start()
	playdate.file.delete(auto.flag)
	local rec = tw.recorder
	local a = { co = coroutine.create(body), recOn = rec.on }
	rec.on = false
	rec.clear()
	return a
end

local function finish(a)
	local rec = tw.recorder
	rec.clear()
	rec.on = a.recOn
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
