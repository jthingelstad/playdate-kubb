-- Frame-time telemetry (device/frametel): phases around the slow motion,
-- starved frames and stalls, and the log line.
import "device/frametel"
import "core/playback"
import "core/trace"
import "core/bench"
local frametel, playback, trace, bench = tw.frametel, tw.playback, tw.trace, tw.bench

test("frametel: frames split before, in and after the slow motion", function()
	local t = frametel.new()
	for _ = 1, 10 do frametel.frame(t, 0.02, 1, false) end
	frametel.frame(t, 0.05, 0.3, false)
	for _ = 1, 4 do frametel.frame(t, 0.02, 0.3, false) end
	frametel.frame(t, 0.02, 0.6, false)        -- easing back is still slow
	for _ = 1, 3 do frametel.frame(t, 0.03, 1, false) end
	expect.eq(t.n1, 10); expect.near(t.s1, 0.2, 1e-12); expect.near(t.m1, 0.02, 1e-12)
	expect.eq(t.n2, 6); expect.near(t.s2, 0.15, 1e-12); expect.near(t.m2, 0.05, 1e-12)
	expect.eq(t.n3, 3); expect.near(t.m3, 0.03, 1e-12)
	frametel.reset(t)
	expect.eq(t.n1 + t.n2 + t.n3, 0)
	expect.eq(t.phase, 1)
end)

test("frametel: starved frames and the longest stall", function()
	local t = frametel.new()
	frametel.frame(t, 0.02, 1, true)
	frametel.frame(t, 0.02, 1, false)
	frametel.frame(t, 0.03, 0.3, true)
	frametel.frame(t, 0.04, 0.3, true)
	frametel.frame(t, 0.02, 0.3, false)
	expect.eq(t.starved, 3)
	expect.near(t.stall, 0.07, 1e-12)
end)

test("frametel: the line is JSON under 300 bytes", function()
	local t = frametel.new()
	for _ = 1, 50 do frametel.frame(t, 0.0213, 1, false) end
	for _ = 1, 60 do frametel.frame(t, 0.0387, 0.3, true) end
	for _ = 1, 40 do frametel.frame(t, 0.0201, 1, false) end
	local line = frametel.encode(t, { time = "2026-11-20 19:42:07", scene = "practice", proj = "baton",
		awake = 12, contacts = 48, bodies = 28, steps = 2880, phys = 1234.5678 })
	expect.truthy(#line < 300, "line is " .. #line .. " bytes")
	local o = trace.decode(line)
	expect.eq(o.v, 1)
	expect.eq(o.scene, "practice"); expect.eq(o.proj, "baton")
	expect.eq(o.pre[1], 50); expect.near(o.pre[3], 21.3, 0.05); expect.near(o.pre[4], 21.3, 0.05)
	expect.eq(o.slow[1], 60); expect.near(o.slow[2], 2.32, 0.01)
	expect.eq(o.post[1], 40)
	expect.eq(o.starved, 60); expect.near(o.stall, 2322, 0.1)
	expect.eq(o.awake, 12); expect.eq(o.contacts, 48); expect.eq(o.bodies, 28); expect.eq(o.steps, 2880)
	expect.near(o.phys, 1234567.8, 0.1)
	-- an empty phase reads [0,0.00,0.0,0.0]
	expect.truthy(frametel.encode(frametel.new(), {}):find('"slow":[0,0.00,0.0,0.0]', 1, true), "empty phase")
end)

test("playback: keeps the most bodies awake and contacts of any step", function()
	local pb = playback.finish(playback.new(bench.world(), 1 / 50))
	-- the same throw stepped by hand: the most awake in any step
	local w, most = bench.world(), 0
	while not tw.world.isAtRest(w) do
		tw.world.step(w)
		if w.awakeCount > most then most = w.awakeCount end
	end
	expect.eq(pb.awakeMax, most)
	expect.truthy(most >= 4, "awake " .. most)
	expect.truthy(pb.contactsMax > 10, "contacts " .. pb.contactsMax)
end)
