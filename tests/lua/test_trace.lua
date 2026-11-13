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
	local flat = { 0.02, -4.5, 0.021, -3.25, 0.019, 30, 0.02, 31.5, 0.02, 33, 0.02, 30 }
	local ev, r = swing.replay(flat)
	expect.eq(ev, "release")
	local line = trace.encode(flat, 6, ev, r, 1, "2026-11-13 10:00:00")
	expect.truthy(not line:find("\n"), "one line")
	local t = trace.decode(line)
	expect.eq(#t.samples, 6)
	expect.near(t.samples[2][2], -3.25, 1e-9)
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
	t.sign = -1
	for _, p in ipairs(t.samples) do p[2] = -p[2] end
	local ev = trace.replay(t)
	expect.eq(ev, "release", "mirrored samples with sign -1 replay as recorded")
	local ev2 = trace.replay(t, true)
	expect.truthy(ev2 ~= "release", "with today's sign the mirrored throw is not a release")
end)
