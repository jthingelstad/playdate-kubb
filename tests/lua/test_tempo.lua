-- The tempo rule (core/swing, s.tempo): the wind-up picks the distance, the
-- flick's release speed against the tempo adds the error.
import "core/swing"
import "core/trace"
import "core/drill"
local swing, trace, drill = tw.swing, tw.trace, tw.drill

local DT = 1 / 50
local FWD = swing.tune.forwardSign

-- a wind-up of `back` degrees over 30 frames, a pause, then a steady flick at
-- `dps` until well past the bottom; flat {dt, raw delta, ...}
local function samples(back, dps)
	local out = {}
	local function add(d, n) for _ = 1, n do out[#out + 1] = DT; out[#out + 1] = d * FWD end end
	add(-back / 30, 30)
	add(0, 5)
	add(dps * DT, math.ceil((back + 60) / (dps * DT)))
	return out
end

local function throwAt(back, dps)
	local ev, r = swing.replay(samples(back, dps), false, true)
	return ev, r
end

-- keep the tune as the tests found it
local function withGain(g, fn)
	local t = swing.tune
	local old, oldRule = t.tempoGain, t.rule
	t.tempoGain = g
	local ok, err = pcall(fn)
	t.tempoGain, t.rule = old, oldRule
	if not ok then error(err, 0) end
end

test("tempo: released as the arm passes the bottom, at the wind-up's power", function()
	local ev, r = throwAt(120, swing.tune.tempoDps)
	expect.eq(ev, "release")
	expect.eq(r.how, "passed")
	expect.eq(r.rule, "tempo")
	expect.near(r.power, 1, 1e-6)
	expect.near(r.tempoMps, 0, 0.02)
	expect.near(r.launchSpeed, swing.tune.launchMax, 0.02)
	-- half the wind-up, half the power, on tempo
	ev, r = throwAt(60, swing.tune.tempoDps)
	expect.near(r.power, 60 / swing.tune.fullBackswingDeg, 0.02)
	local t = swing.tune
	expect.near(r.launchSpeed, t.launchMin + (t.launchMax - t.launchMin) * r.power, 0.03)
end)

test("tempo: a fast flick goes long, a slow one short, by the gain", function()
	withGain(0.10, function()
		local _, r = throwAt(120, swing.tune.tempoDps + 200)
		expect.near(r.tempoMps, 0.20, 0.02)
		expect.eq(swing.tempoMiss(r.tempoMps), 1)
		_, r = throwAt(120, swing.tune.tempoDps - 200)
		expect.near(r.tempoMps, -0.20, 0.02)
		expect.eq(swing.tempoMiss(r.tempoMps), -1)
		-- on tempo within tempoOnMps
		expect.eq(swing.tempoMiss(0.1), 0)
	end)
	withGain(0.20, function()
		local _, r = throwAt(120, swing.tune.tempoDps + 200)
		expect.near(r.tempoMps, 0.40, 0.03)
	end)
end)

test("tempo: beyond the knee each 100 deg/s costs the far gain, never under the floor", function()
	withGain(0.10, function()
		local t = swing.tune
		local v = swing.tempoMps(t.tempoDps - t.tempoKneeDps - 100)
		expect.near(v, -(0.10 * t.tempoKneeDps / 100 + t.tempoFarGain), 1e-6)
		-- the slowest swing still starts and leaves at least launchFloor
		local _, r = throwAt(10, t.swingStartDps + 10)
		expect.truthy(r.launchSpeed >= t.launchFloor - 1e-9)
	end)
end)

test("tempo: a trace line says release tempo and replays the same", function()
	local raw = samples(100, 1000)
	local ev, r = swing.replay(raw, false, true)
	local n = #raw // 2
	local line = trace.encode(raw, n, ev, r, swing.tune.forwardSign, "2026-11-14 18:00:00")
	expect.truthy(line:find('"release":"tempo"', 1, true))
	expect.truthy(line:find('"tempoDev":', 1, true))
	local t = trace.decode(line)
	local ev2, r2 = trace.replay(t)
	expect.eq(ev2, "release")
	expect.near(r2.launchSpeed, r.launchSpeed, 1e-4)
	expect.near(r2.power, r.power, 1e-4)
end)

test("tempo: the stop rule is untouched without it", function()
	local s = swing.new()
	expect.truthy(swing.stops(s))
	s.tempo = true
	expect.truthy(not swing.stops(s))
end)

test("tempo: presets set the rule and the gain", function()
	local t = swing.tune
	local oldRule, oldGain = t.rule, t.tempoGain
	swing.setPreset("hard")
	expect.eq(t.rule, "tempo"); expect.eq(t.tempoGain, swing.presets.hard)
	swing.setPreset("stop")
	expect.eq(t.rule, "stop")
	t.rule, t.tempoGain = oldRule, oldGain
end)

test("tempo: a drill's power is the wind-up's plus the tempo's", function()
	local sol = { band = 0.5, speed = 7, swivel = 0, loft = 28 }
	local on = drill.launch(sol, { power = 0.5, smoothness = 1, tilt = 0, how = "passed" }, 0, {})
	local fast = drill.launch(sol, { power = 0.5, tempoPower = 0.3, smoothness = 1, tilt = 0, how = "passed" }, 0, {})
	expect.truthy(fast.speed > on.speed)
end)
