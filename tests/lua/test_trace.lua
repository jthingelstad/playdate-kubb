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

test("fixture traces replay to the results they recorded", function()
	local ls = lines(FIXTURE)
	expect.truthy(#ls >= 4, "fixture has traces")
	local seen = { release = 0, letdown = 0, helicopter = 0 }
	for i, l in ipairs(ls) do
		local t = trace.decode(l)
		expect.eq(t.v, 1)
		local ev, r = trace.replay(t)
		expect.eq(ev, t.event, "line " .. i .. " event")
		seen[ev] = seen[ev] + 1
		if ev == "release" then
			expect.near(r.power, t.result.power, 0.005, "line " .. i .. " power")
			expect.near(r.tilt, t.result.tilt, 0.5, "line " .. i .. " tilt")
			expect.eq(r.legal, t.result.legal, "line " .. i .. " legal")
			if not r.legal then seen.helicopter = seen.helicopter + 1 end
		end
	end
	expect.truthy(seen.release >= 2 and seen.letdown >= 1 and seen.helicopter >= 1, "covers the cases")
end)

test("encode then decode round-trips samples and result", function()
	local sign = swing.tune.forwardSign
	-- (a wind-up, a flick and the crank stopped: the release)
	local flat = { 0.02, -4.5, 0.021, -3.25, 0.019, 30, 0.02, 31.5, 0.02, 33, 0.02, 30, 0.02, 0, 0.02, 0 }
	for i = 2, #flat, 2 do flat[i] = flat[i] * sign end
	local ev, r = swing.replay(flat)
	expect.eq(ev, "release")
	local line = trace.encode(flat, 8, ev, r, sign, "2026-11-13 10:00:00")
	expect.truthy(not line:find("\n"), "one line")
	local t = trace.decode(line)
	expect.eq(#t.samples, 8)
	expect.eq(t.release, "stop")
	expect.eq(t.result.how, "stopped")
	expect.near(t.result.releaseAngle, r.releaseAngle, 1e-4)
	expect.near(t.samples[2][2], -3.25 * sign, 1e-9)
	expect.eq(t.result.legal, r.legal)
	expect.near(t.result.power, r.power, 1e-5)
	local ev2, r2 = trace.replay(t)
	expect.eq(ev2, ev)
	expect.near(r2.power, r.power, 1e-5)
end)

test("a let-down encodes without a result", function()
	local line = trace.encode({ 0.02, -10, 0.02, 1 }, 2, "letdown", nil, 1)
	local t = trace.decode(line)
	expect.eq(t.result, nil)
	expect.eq(t.event, "letdown")
end)

test("replay keeps the recorded sign unless told otherwise", function()
	local t = trace.decode(lines(FIXTURE)[1])
	-- make the trace one recorded with the opposite of today's crank sign
	local other = -swing.tune.forwardSign
	if t.sign ~= other then
		t.sign = other
		for _, p in ipairs(t.samples) do p[2] = -p[2] end
	end
	local ev = trace.replay(t)
	expect.eq(ev, "release", "a trace with the other sign replays as recorded")
	local ev2 = trace.replay(t, true)
	expect.truthy(ev2 ~= "release", "with today's sign that trace is not a release")
end)

test("a drill line carries its mode, marker, band, landing and rest; a baton line has none", function()
	-- (a wind-up, a flick and the crank stopped: the release)
	local flat = { 0.02, -4.5, 0.021, -3.25, 0.019, 30, 0.02, 31.5, 0.02, 33, 0.02, 30, 0.02, 0, 0.02, 0 }
	for i = 2, #flat, 2 do flat[i] = flat[i] * swing.tune.forwardSign end
	local _, r = swing.replay(flat)
	local baton = trace.encode(flat, 8, "release", r, 1)
	expect.truthy(not baton:find('"mode"') and not baton:find('"marker'), "baton line unchanged")
	r.mode, r.band, r.verdict, r.cut = "drill", 0.6, "on", -1
	r.markerX, r.markerY, r.landX, r.landY, r.restX, r.restY, r.throwerX = 0.5, 6, 0.48, 5.9, 0.4, 6.05, 0.5
	local t = trace.decode(trace.encode(flat, 8, "release", r, 1))
	expect.eq(t.result.mode, "drill")
	expect.eq(t.result.verdict, "on")
	expect.eq(t.result.cut, -1)
	expect.near(t.result.band, 0.6, 1e-6)
	expect.near(t.result.markerY, 6, 1e-6)
	expect.near(t.result.landY, 5.9, 1e-6)
	expect.near(t.result.restX, 0.4, 1e-6)
	expect.near(t.result.throwerX, 0.5, 1e-6)
end)

test("a line recorded before the stop release replays with the old rule", function()
	-- an old line: no "release" field, released as the arm passed the bottom
	local flat = { 0.02, -4.5, 0.021, -3.25, 0.019, 30, 0.02, 31.5, 0.02, 33, 0.02, 30 }
	local samples = {}
	for i = 1, #flat - 1, 2 do samples[#samples + 1] = { flat[i], flat[i + 1] * swing.tune.forwardSign } end
	local ev, r = trace.replay({ sign = swing.tune.forwardSign, samples = samples })
	expect.eq(ev, "release")
	expect.eq(r.how, "passed")
	-- the same samples under the stop rule have not stopped yet
	local ev2 = trace.replay({ sign = swing.tune.forwardSign, release = "stop", samples = samples })
	expect.eq(ev2, nil)
end)
