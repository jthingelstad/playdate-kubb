import "core/trace"
import "core/swing"
local trace = tw.trace
local swing = tw.swing

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local FIXTURE = here .. "/../fixtures/traces/sample.jsonl"

local function lines(path)
	local out = {}
	for l in assert(io.open(path)):lines() do
		if l:match("%S") then out[#out + 1] = l end
	end
	return out
end

-- A swing in forward degrees per 20 ms frame, as raw deltas (today's sign):
-- 40 back, a flick 124.5 forward (84.5 past the bottom) and the crank stopped.
local function clockSwing()
	local fwd = { -20, -20, 30, 31.5, 33, 30, 0, 0 }
	local flat = {}
	for i, d in ipairs(fwd) do
		flat[2 * i - 1] = (i == 2) and 0.021 or 0.02
		flat[2 * i] = d * swing.tune.forwardSign
	end
	return flat, #fwd
end

test("fixture traces (lines from 2026-11-13) still decode and replay", function()
	local ls = lines(FIXTURE)
	expect.truthy(#ls >= 4, "fixture has traces")
	local seen = { release = 0, letdown = 0 }
	for i, l in ipairs(ls) do
		local t = trace.decode(l)
		expect.eq(t.v, 1)
		expect.eq(t.release, nil, "line " .. i .. ": written before the stop release")
		seen[t.event] = seen[t.event] + 1
		if t.event == "release" then
			-- the old swing's fields are still there to read
			expect.truthy(type(t.result.power) == "number" and type(t.result.legal) == "boolean")
		end
		local ev, r = trace.replay(t)
		if t.event == "letdown" then
			expect.eq(ev, "letdown", "line " .. i)
		else
			-- the samples end where the old swing let go, as the arm passed the
			-- bottom: today's swing is still turning there
			expect.eq(ev, nil, "line " .. i)
			expect.eq(r, nil)
		end
	end
	expect.truthy(seen.release >= 2 and seen.letdown >= 1, "covers the cases")
end)

test("encode then decode round-trips samples and result", function()
	local sign = swing.tune.forwardSign
	local flat, n = clockSwing()
	local ev, r = swing.replay(flat)
	expect.eq(ev, "release")
	expect.near(r.releaseAngle, 84.5, 1e-9)
	local line = trace.encode(flat, n, ev, r, sign, "2026-11-15 10:00:00")
	expect.truthy(not line:find("\n"), "one line")
	local t = trace.decode(line)
	expect.eq(t.v, 1)
	expect.eq(t.release, "clock")
	expect.eq(#t.samples, n)
	expect.near(t.samples[2][1], 0.021, 1e-9)
	expect.near(t.samples[2][2], -20 * sign, 1e-9)
	for _, k in ipairs { "back", "releaseAngle", "flickDps", "flickFrac", "smoothness", "shake" } do
		expect.near(t.result[k], r[k], 1e-3 * math.max(1, math.abs(r[k])), k)
	end
	expect.eq(t.result.pull, r.pull)
	expect.eq(t.result.how, "stopped")
	expect.eq(t.result.frames, r.frames)
	local ev2, r2 = trace.replay(t)
	expect.eq(ev2, ev)
	expect.near(r2.releaseAngle, r.releaseAngle, 1e-4)
	expect.near(r2.flickDps, r.flickDps, 1e-2)
end)

test("the game's own fields after a throw are written too", function()
	local flat, n = clockSwing()
	local _, r = swing.replay(flat)
	r.power, r.tilt, r.legal, r.loft, r.distance = 0.8, 4.5, true, 32, 7.9
	local t = trace.decode(trace.encode(flat, n, "release", r, swing.tune.forwardSign))
	expect.near(t.result.power, 0.8, 1e-6)
	expect.near(t.result.tilt, 4.5, 1e-6)
	expect.eq(t.result.legal, true)
	expect.near(t.result.loft, 32, 1e-6)
	expect.near(t.result.distance, 7.9, 1e-6)
	r.power, r.tilt, r.legal, r.loft, r.distance = nil, nil, nil, nil, nil
end)

test("the nerves' fields round-trip", function()
	local flat, n = clockSwing()
	local _, r = swing.replay(flat)
	r.sideDeg, r.lenShare, r.sideV, r.lenV = -0.46, 0.031, -1, 0
	local t = trace.decode(trace.encode(flat, n, "release", r, swing.tune.forwardSign))
	expect.near(t.result.sideDeg, -0.46, 1e-6)
	expect.near(t.result.lenShare, 0.031, 1e-6)
	expect.eq(t.result.sideV, -1)
	expect.eq(t.result.lenV, 0)
	r.sideDeg, r.lenShare, r.sideV, r.lenV = nil, nil, nil, nil
end)

test("a let-down encodes without a result", function()
	local line = trace.encode({ 0.02, -40, 0.02, 1 }, 2, "letdown", nil, -1)
	local t = trace.decode(line)
	expect.eq(t.result, nil)
	expect.eq(t.event, "letdown")
	expect.eq(t.release, "clock")
end)

test("replay keeps the recorded sign unless told otherwise", function()
	-- a 2026-11-13 line (sign 1, before forwardSign was flipped) with the
	-- crank's stop after it: under today's swing it throws as recorded
	local t = trace.decode(lines(FIXTURE)[1])
	expect.eq(t.sign, -swing.tune.forwardSign)
	for _ = 1, 3 do t.samples[#t.samples + 1] = { 0.02, 0 } end
	local ev, r = trace.replay(t)
	expect.eq(ev, "release", "a trace with the other sign replays as recorded")
	expect.truthy(r.releaseAngle > 0 and r.back > 100)
	local ev2 = trace.replay(t, true)
	expect.truthy(ev2 ~= "release", "with today's sign that trace is not a release")
end)

test("a drill line carries its mode, marker, band, landing and rest; a baton line has none", function()
	local flat, n = clockSwing()
	local _, r = swing.replay(flat)
	local baton = trace.encode(flat, n, "release", r, -1)
	expect.truthy(not baton:find('"mode"') and not baton:find('"marker'), "baton line unchanged")
	r.mode, r.band, r.verdict, r.cut = "drill", 0.6, "on", -1
	r.markerX, r.markerY, r.landX, r.landY, r.restX, r.restY, r.throwerX = 0.5, 6, 0.48, 5.9, 0.4, 6.05, 0.5
	local t = trace.decode(trace.encode(flat, n, "release", r, -1))
	expect.eq(t.result.mode, "drill")
	expect.eq(t.result.verdict, "on")
	expect.eq(t.result.cut, -1)
	expect.near(t.result.band, 0.6, 1e-6)
	expect.near(t.result.markerY, 6, 1e-6)
	expect.near(t.result.landY, 5.9, 1e-6)
	expect.near(t.result.restX, 0.4, 1e-6)
	expect.near(t.result.throwerX, 0.5, 1e-6)
	expect.eq(t.result.back, r.back)
end)

test("lines from every swing replay through today's", function()
	-- the same samples under each "release": none, "stop" (2026-11-14), "clock"
	local flat, n = clockSwing()
	local samples = {}
	for i = 1, n do samples[i] = { flat[2 * i - 1], flat[2 * i] } end
	local want
	for _, rel in ipairs { false, "stop", "clock" } do
		local ev, r = trace.replay({ sign = swing.tune.forwardSign, release = rel or nil, samples = samples })
		expect.eq(ev, "release", tostring(rel))
		want = want or r.releaseAngle
		expect.near(r.releaseAngle, want, 1e-9, tostring(rel))
	end
end)
