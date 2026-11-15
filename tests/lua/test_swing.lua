import "core/swing"
import "core/trace"
local swing = tw.swing
local trace = tw.trace

local DT = 1 / 50
local FWD = swing.tune.forwardSign

-- Build a flat {dt, delta, ...} trace from forward-degree steps per frame
-- (negative = back). Raw deltas carry the crank sign.
local function samples(parts)
	local out = {}
	for _, p in ipairs(parts) do
		for _ = 1, (p.n or 1) do
			out[#out + 1] = p.dt or DT
			out[#out + 1] = p.d * FWD
		end
	end
	return out
end

local function windup(deg, frames)
	return { d = -deg / frames, n = frames }
end

local function run(parts)
	return swing.replay(samples(parts))
end

-- Feed parts into state s; returns the events in order.
local function feed(s, parts)
	local t, evs = samples(parts), {}
	for i = 1, #t, 2 do
		local ev = swing.update(s, t[i + 1], t[i])
		if ev then evs[#evs + 1] = ev end
	end
	return evs
end

-- a wind-up of `back` (120), a pause, the forward steps, then the crank stopped
local function flick(steps, back)
	local parts = { windup(back or 120, 30), { d = 0, n = 5 } }
	for _, d in ipairs(steps) do parts[#parts + 1] = { d = d } end
	parts[#parts + 1] = { d = 0, n = 3 }
	return parts
end

local function sum(steps)
	local a = 0
	for _, d in ipairs(steps) do a = a + d end
	return a
end

test("forward is anti-clockwise, and the sign is one constant", function()
	expect.eq(swing.tune.forwardSign, -1)
	-- with the sign flipped, the same raw trace mirrored still throws the same
	local raw = samples(flick { 6, 12, 18, 22, 24, 24, 24, 24, 24, 24, 24 })
	local _, r0 = swing.replay(raw)
	local angle0 = r0.releaseAngle
	local old = swing.tune.forwardSign
	swing.tune.forwardSign = -old
	for i = 2, #raw, 2 do raw[i] = -raw[i] end
	local ev, r = swing.replay(raw)
	swing.tune.forwardSign = old
	expect.eq(ev, "release")
	expect.near(r.releaseAngle, angle0, 1e-9)
end)

test("dead zone: back less than startBackDeg, then forward, does nothing", function()
	local s = swing.new()
	expect.eq(#feed(s, { windup(25, 5), { d = 6, n = 10 } }), 0)
	expect.eq(s.phase, "idle")
	expect.eq(s.pending, 0)
	-- just short of 7 o'clock is still idle; crossing it starts the wind-up
	feed(s, { windup(swing.tune.startBackDeg - 1, 5) })
	expect.eq(s.phase, "idle")
	feed(s, { { d = -2 } })
	expect.eq(s.phase, "winding")
	expect.near(s.arm, -(swing.tune.startBackDeg + 1), 1e-9)
	expect.near(s.back, swing.tune.startBackDeg + 1, 1e-9)
end)

test("in the dead zone the arm's position counts, not the back motion alone", function()
	-- 20 back, 5 forward (the arm at -15), 15 back: at -30, the wind-up starts
	local s = swing.new()
	feed(s, { { d = -20 }, { d = 5 }, { d = -14 } })
	expect.eq(s.phase, "idle")
	feed(s, { { d = -1 } })
	expect.eq(s.phase, "winding")
	expect.near(s.arm, -30, 1e-9)
end)

test("a little crank jitter while idle does not start a wind-up", function()
	local s = swing.new()
	feed(s, { { d = -2 }, { d = 2 }, { d = -3 }, { d = 1 }, { d = -2 } })
	expect.eq(s.phase, "idle")
end)

test("wind-up alone is no throw; back is the farthest back", function()
	local s = swing.new()
	expect.eq(#feed(s, { windup(100, 25), { d = 0, n = 50 } }), 0)
	expect.eq(s.phase, "winding")
	expect.near(s.back, 100, 1e-9)
	-- let down slowly a little: the arm comes forward, back stays the farthest
	feed(s, { { d = 2, n = 10 } })
	expect.eq(s.phase, "winding")
	expect.near(s.arm, -80, 1e-9)
	expect.near(s.back, 100, 1e-9)
end)

test("letdown: slow forward back past the bottom", function()
	local s = swing.new()
	local evs = feed(s, { windup(90, 20), { d = 2, n = 60 } })
	expect.eq(evs[1], "letdown")
	expect.eq(#evs, 1)
	expect.eq(s.phase, "idle")
end)

test("letdown: a flick that stops short of the bottom throws nothing", function()
	-- 120 back, 100 forward at speed, then stopped at -20 (8 o'clock)
	local s = swing.new()
	local evs = feed(s, flick { 10, 20, 30, 30, 10 })
	expect.eq(evs[1], "letdown")
	expect.eq(#evs, 1)
	expect.eq(s.phase, "idle", "no cooldown after a letdown")
	-- stopped exactly at the bottom is not past it
	expect.eq(run(flick { 20, 30, 30, 30, 10 }), "letdown")
end)

test("the throw leaves where the crank stops: releaseAngle", function()
	-- wound 120 back, 210 forward: stopped 90 past the bottom (3 o'clock)
	local steps = { 10, 20, 30, 30, 30, 30, 30, 20, 10 }
	expect.near(sum(steps), 210, 1e-9)
	local ev, r = run(flick(steps))
	expect.eq(ev, "release")
	expect.eq(r.how, "stopped")
	expect.near(r.releaseAngle, 90, 1e-6)
	expect.near(r.back, 120, 1e-9)
	expect.eq(r.frames, #steps)
end)

test("the release angle is the farthest forward, not where the crank settles", function()
	-- stopped 30 past the bottom, then the hand lets the crank fall back a little
	local ev, r = run { windup(120, 30), { d = 10 }, { d = 30, n = 4 }, { d = 20 },
		{ d = -2 }, { d = -3 }, { d = 0, n = 3 } }
	expect.eq(ev, "release")
	expect.near(r.releaseAngle, 30, 1e-6)
end)

test("still turning is not a stop: a flick that slows but keeps going", function()
	-- Jamie's swing of 13:33:44 (2026-11-14): 16 then 8 then 15 degrees a frame,
	-- still turning at 300 deg/s, released by an older rule 27 short of the bottom
	local steps = { 5, 10, 14, 16, 8, 15, 13, 8, 6, 6, 5, 4, 2, 1 }
	local ev, r = run(flick(steps, 100))
	expect.eq(ev, "release")
	expect.eq(r.how, "stopped")
	-- the stop comes in the last frames: every degree before it counts
	expect.near(r.releaseAngle, sum(steps) - 100, 1e-6)
	expect.eq(r.frames, 12, "flick frames down to the last at releaseStopDps or over")
end)

test("the stop is the speed window: one slow frame in a jittery flick does not stop it", function()
	-- a 2 degree frame (100 deg/s) between fast ones: averaged over two frames it is still moving
	local ev, r = run(flick { 20, 30, 2, 30, 30, 30, 30, 20 })
	expect.eq(ev, "release")
	expect.near(r.releaseAngle, 192 - 120, 1e-6)
end)

test("back is the farthest back, capped at backswingMaxDeg; the arm is never capped", function()
	-- wound 250 back (back counts 200), 280 forward: stopped 30 past the bottom
	local ev, r = run { windup(250, 30), { d = 0, n = 5 }, { d = 10 }, { d = 30, n = 9 }, { d = 0, n = 3 } }
	expect.eq(ev, "release")
	expect.near(r.back, swing.tune.backswingMaxDeg, 1e-9)
	expect.near(r.releaseAngle, 30, 1e-6)
	-- let down partway before the flick: back is still the farthest
	local ev2, r2 = run { windup(140, 20), { d = 2, n = 10 }, { d = 20, n = 10 }, { d = 0, n = 3 } }
	expect.eq(ev2, "release")
	expect.near(r2.back, 140, 1e-9)
	expect.near(r2.releaseAngle, 80, 1e-6)
end)

test("sky: an arm past 12 o'clock is released at once", function()
	local s = swing.new()
	local t = samples { windup(120, 30), { d = 0, n = 5 }, { d = 24, n = 40 } }
	local ev, frames = nil, 0
	for i = 1, #t, 2 do
		frames = frames + 1
		ev = swing.update(s, t[i + 1], t[i])
		if ev then break end
	end
	expect.eq(ev, "release")
	local r = s.result
	expect.eq(r.how, "sky")
	expect.truthy(r.releaseAngle >= swing.tune.skyDeg and r.releaseAngle < swing.tune.skyDeg + 24,
		"released where it passed 12: " .. r.releaseAngle)
	-- 120 back + 180 forward = 300 degrees at 24 a frame: the 13th flick frame
	expect.eq(r.frames, 13)
	expect.eq(frames, 35 + 13)
end)

test("cooldown: after a release the crank is ignored for cooldownS, then idle", function()
	local s = swing.new()
	-- released on the second stopped frame
	local evs = feed(s, { windup(120, 30), { d = 10 }, { d = 30, n = 5 }, { d = 20 }, { d = 0, n = 2 } })
	expect.eq(evs[1], "release")
	expect.eq(s.phase, "cooldown")
	expect.near(s.cool, swing.tune.cooldownS, 1e-12)
	-- the crank swings back hard right after the throw: ignored
	local n = math.floor(swing.tune.cooldownS / DT + 0.5)
	expect.eq(#feed(s, { { d = -40, n = n - 1 } }), 0)
	expect.eq(s.phase, "cooldown")
	expect.eq(s.pending, 0)
	feed(s, { { d = -40 } })
	expect.eq(s.phase, "idle", "cooldown over after cooldownS of frame time")
	expect.eq(s.pending, 0, "nothing carried over from the cooldown")
	-- and then a wind-up works again
	feed(s, { windup(60, 6) })
	expect.eq(s.phase, "winding")
	feed(s, { { d = 0, n = 2 }, { d = 30, n = 4 }, { d = 0, n = 3 } })
	expect.eq(s.phase, "cooldown")
	-- swing.reset skips the cooldown
	swing.reset(s)
	expect.eq(s.phase, "idle")
end)

test("flickFrac: minFlickFrac at swingStartDps, 1 at fullFlickDps, linear between", function()
	local t = swing.tune
	local function frac(dps)
		-- a steady flick from 40 back to about 60 past the bottom
		local d = dps * DT
		local steps = {}
		for i = 1, math.ceil(100 / d) do steps[i] = d end
		local ev, r = run(flick(steps, 40))
		expect.eq(ev, "release")
		expect.near(r.flickDps, dps, 1e-6)
		return r.flickFrac
	end
	expect.near(frac(500), t.minFlickFrac + (1 - t.minFlickFrac) * (500 - t.swingStartDps)
		/ (t.fullFlickDps - t.swingStartDps), 1e-9)
	expect.near(frac(t.swingStartDps + 1), t.minFlickFrac, 0.002)
	expect.near(frac(t.fullFlickDps), 1, 1e-9)
	expect.near(frac(1500), 1, 1e-9)
	expect.near(frac(250), 0.25, 1e-9)
end)

test("flickDps is the peak speedWindow average, not one fast frame", function()
	-- one 60 degree frame (3000 deg/s) among 20s: the peak window is (20 + 60) / 2
	local ev, r = run(flick { 20, 20, 60, 20, 20, 20, 20, 20, 20, 10 })
	expect.eq(ev, "release")
	expect.near(r.flickDps, 40 / DT, 1e-6)
end)

test("pull: +1 still speeding up into the stop, -1 falling off before it", function()
	local ev, r = run(flick { 6, 12, 18, 24, 30, 36, 40 })
	expect.eq(ev, "release")
	expect.eq(r.pull, 1)
	-- the fastest frame one before the last is still +1 (pullFrames 2)
	local _, r2 = run(flick { 6, 12, 18, 24, 40, 36 })
	expect.eq(r2.pull, 1)
	-- peaked early, easing off into the stop
	local _, r3 = run(flick { 30, 40, 36, 30, 24, 18, 12, 8, 6, 5 })
	expect.eq(r3.pull, -1)
end)

test("smoothness and shake: an even flick is steady, a stuttered one shaky", function()
	local _, r = run(flick { 6, 12, 18, 22, 24, 24, 24, 24, 24, 24 })
	expect.truthy(r.smoothness >= 0.9, "smoothness " .. r.smoothness)
	expect.near(r.shake, 1 - r.smoothness, 1e-12)
	local ev2, r2 = run(flick { 40, 2, 40, 2, 40, 2, 40, 2, 40, 20 })
	expect.eq(ev2, "release")
	expect.truthy(r2.smoothness < 2 / 3, "stuttered smoothness " .. r2.smoothness)
	expect.near(r2.shake, 1 - r2.smoothness, 1e-12)
end)

test("uneven but honest flick stays steady (hardware sampling jitter)", function()
	-- speeds from a recorded hardware flick at 41 ms frames: 391, 1454, 775, 798, 1244 deg/s
	local dt = 0.041
	local ev, r = swing.replay(samples {
		{ d = -10, n = 12, dt = dt }, { d = 0, dt = dt }, { d = 16, dt = dt }, { d = 60, dt = dt },
		{ d = 32, dt = dt }, { d = 33, dt = dt }, { d = 51, dt = dt }, { d = 0, n = 3, dt = dt } })
	expect.eq(ev, "release")
	expect.truthy(r.smoothness >= 2 / 3, "smoothness " .. r.smoothness)
end)

test("a zero frame time is ignored", function()
	local s = swing.new()
	expect.eq(swing.update(s, -90 * FWD, 0), nil)
	expect.eq(s.phase, "idle")
	expect.eq(s.pending, 0)
end)

test("replay is deterministic, and the state reuses its tables", function()
	local parts = flick { 6, 12, 18, 22, 24, 24, 24, 24, 24, 24 }
	local _, a = run(parts)
	local copy = {}
	for k, v in pairs(a) do copy[k] = v end
	local _, b = run(parts)
	for k, v in pairs(copy) do expect.eq(b[k], v, k) end
	-- one state, two throws: the same result and speeds tables, the same numbers
	local s = swing.new()
	local result, speeds = s.result, s.speeds
	feed(s, parts)
	feed(s, { { d = 0, n = 20 } })   -- through the cooldown
	expect.eq(s.phase, "idle")
	feed(s, parts)
	expect.truthy(s.result == result and s.speeds == speeds, "tables reused")
	for k, v in pairs(copy) do expect.eq(s.result[k], v, "second throw " .. k) end
end)

test("the arm angle is measured from the bottom of the turn", function()
	local f = swing.tune.forwardSign
	expect.near(swing.armAngle(180), 0, 1e-9)
	expect.near(swing.armAngle(180 - 30 * f), -30, 1e-9, "30 degrees back")
	expect.near(swing.armAngle(180 + 45 * f), 45, 1e-9, "45 degrees forward")
	expect.near(math.abs(swing.armAngle(0)), 180, 1e-9, "straight up")
end)

test("the throw arms only when the crank crosses the bottom going back", function()
	expect.truthy(swing.crossedBack(5, -4))
	expect.truthy(swing.crossedBack(0, -10))
	expect.truthy(not swing.crossedBack(-20, -40), "already behind the bottom")
	expect.truthy(not swing.crossedBack(170, -170), "across the top of the turn")
	expect.truthy(not swing.crossedBack(nil, -10), "first frame")
	expect.truthy(not swing.crossedBack(-5, 5), "going forward")
end)

test("recorded hardware traces replay through the new swing without errors", function()
	local here = arg[0]:match("^(.*)/[^/]*$") or "."
	local root = here .. "/../.."
	local files = {}
	local p = io.popen('ls "' .. root .. '/telemetry"/*/traces.jsonl 2>/dev/null')
	for f in p:lines() do files[#files + 1] = f end
	p:close()
	files[#files + 1] = root .. "/tests/fixtures/traces/sample.jsonl"
	expect.truthy(#files >= 2, "telemetry traces found")
	local lines, seen = 0, { release = 0, letdown = 0, none = 0 }
	for _, path in ipairs(files) do
		for l in io.lines(path) do
			if l:match("%S") then
				lines = lines + 1
				local t = trace.decode(l)
				local ev, r = trace.replay(t)
				seen[ev or "none"] = seen[ev or "none"] + 1
				if ev == "release" then
					expect.truthy(r.how == "stopped" or r.how == "sky", "how " .. tostring(r.how))
					expect.truthy(r.releaseAngle > 0, "released past the bottom")
					expect.truthy(r.back >= swing.tune.startBackDeg and r.back <= swing.tune.backswingMaxDeg)
					expect.truthy(r.flickFrac >= swing.tune.minFlickFrac and r.flickFrac <= 1)
					expect.truthy(r.smoothness >= 0 and r.smoothness <= 1)
					expect.truthy(r.pull == 1 or r.pull == -1)
					expect.truthy(r.frames >= 1)
				end
			end
		end
	end
	expect.truthy(lines >= 400, "lines " .. lines)
	-- older lines end at the old release, so most end mid-swing under the new
	-- rules, and old releases short of the bottom are letdowns now
	expect.truthy(seen.letdown >= 1 and seen.none >= 1, "covers letdowns and mid-swing ends")
end)
