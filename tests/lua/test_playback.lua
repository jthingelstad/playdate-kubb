import "core/playback"
local playback = tw.playback

test("slow motion: real time before a hit, slow around it, easing back after", function()
	local k = playback.slow
	expect.eq(playback.speed(1.0, nil), 1, "no hit known")
	expect.eq(playback.speed(0.5, 2.0), 1, "long before the hit")
	expect.eq(playback.speed(2.0 - k.lead * 0.5, 2.0), k.rate, "just before")
	expect.eq(playback.speed(2.0 + k.hold * 0.5, 2.0), k.rate, "during")
	local mid = playback.speed(2.0 + k.hold + k.ease * 0.5, 2.0)
	expect.truthy(mid > k.rate and mid < 1, "easing " .. mid)
	expect.eq(playback.speed(2.0 + k.hold + k.ease + 0.1, 2.0), 1, "back to real time")
end)

import "core/bench"
local world, bench = tw.world, tw.bench

test("poseAt: the recorded frames exactly, and between them a blend of the two", function()
	local pb = playback.finish(playback.new(bench.world(false), 1 / 50))
	local i = pb.w.projectile.index
	for _, f in ipairs { 0, 5, 17 } do
		local a = { playback.pose(pb, i, f) }
		local b = { playback.poseAt(pb, i, f / 50) }
		for k = 1, 7 do expect.near(b[k], a[k], 1e-9) end
	end
	local x0 = playback.pose(pb, i, 10)
	local x1 = playback.pose(pb, i, 11)
	local x, _, _, qw, qx, qy, qz = playback.poseAt(pb, i, 10.5 / 50)
	expect.near(x, (x0 + x1) / 2, 1e-9)
	expect.near(qw * qw + qx * qx + qy * qy + qz * qz, 1, 1e-9)
	-- past the end: the last frame
	local e = { playback.pose(pb, i, pb.frames) }
	local p = { playback.poseAt(pb, i, pb.frames / 50 + 1) }
	for k = 1, 7 do expect.near(p[k], e[k], 1e-12) end
	-- a body never woken sits at its start
	local s = { playback.poseAt(pb, 1, 0.3) }
	local r = pb.rec[1]
	if r.start < 0 then expect.eq(s[1], r.x) end
end)

test("pace: real time with enough computed ahead, slower in proportion with less, eased", function()
	local k = playback.paceTune
	local pb = { frames = 0, frameDt = 1 / 50, done = false, v = 1 }
	-- half the horizon computed ahead: the pace falls toward 0.5, by at most fall per second
	pb.frames = math.floor(k.horizon * 0.5 * 50)
	local v = playback.pace(pb, 0, 0.04)
	expect.near(v, 1 - k.fall * 0.04, 1e-9)
	for _ = 1, 50 do v = playback.pace(pb, 0, 0.04) end
	expect.near(v, pb.frames / 50 / k.horizon, 1e-9)
	-- plenty ahead: back up to 1, by at most rise per second
	pb.frames = 200
	local v2 = playback.pace(pb, 0, 0.04)
	expect.near(v2, v + k.rise * 0.04, 1e-9)
	for _ = 1, 50 do v2 = playback.pace(pb, 0, 0.04) end
	expect.eq(v2, 1)
	-- nothing ahead: the floor
	pb.frames = 0
	for _ = 1, 50 do v2 = playback.pace(pb, 0, 0.04) end
	expect.eq(v2, k.floor)
	-- computed to rest: real time
	pb.done = true
	for _ = 1, 50 do v2 = playback.pace(pb, 0, 0.04) end
	expect.eq(v2, 1)
end)

test("calm: the throw's last stretch is calm, the flight is not", function()
	-- the bench throw at one kubb of its group: in the full tight group a
	-- baton can come to lie wedged on a fallen kubb between two standing
	-- ones, where the pair contacts' push bias keeps it rocking until
	-- maxTime (2026-11-16, found when the foot catch was taken out), and a
	-- throw that never rests has no calm stretch to find
	local w = world.new { surface = "grass", pieces = { bench.pieces[1] } }
	local t = bench.throw
	world.launchBaton(w, t.x, t.lineY, t.swivel, t.loft, t.speed, t.tumble, t.tilt)
	local pb = playback.finish(playback.new(w, 1 / 50))
	expect.truthy(pb.calmFrom ~= nil)
	expect.truthy(pb.calmFrom > 10 and pb.calmFrom < pb.frames)
end)
