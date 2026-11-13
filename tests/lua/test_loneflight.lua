-- world.loneFlight (the one-body free-flight step) must change nothing: the
-- match case's throws and a bench throw end in exactly the same state with it
-- off and on, step for step (tools/physdump.lua checks whole games).
import "core/bench"
import "core/drill"
import "core/match"
local bench, world, drill, match = tw.bench, tw.world, tw.drill, tw.match

local function state(w)
	local parts = { string.format("%.17g %d", w.time, w.steps) }
	for k = 1, w.n do
		local b = w.bodies[k]
		parts[#parts + 1] = string.format("%s %s %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %.17g %s",
			b.id, tostring(b.awake), b.x, b.y, b.z, b.qw, b.qx, b.qy, b.qz, b.vx, b.vy, b.vz, b.wx, b.wy, b.wz,
			b.sleepTime, tostring(b.toppled))
	end
	return table.concat(parts, "\n")
end

local function play(t, lone)
	local saved = world.loneFlight
	world.loneFlight = lone
	local s = bench.matchSetup(t.projectile)
	local w = world.new { surface = "grass", pieces = match.worldPieces(s) }
	local a = bench.matchThrow(t)
	if a.drill then
		local sol = drill.solve(a.drill.markerX, a.drill.markerY, 0, {})
		local L = drill.launch(sol, { power = sol.band, smoothness = 1, tilt = 0 }, 0, {})
		world.launchDrill(w, s.kubb, sol.x, 0, L.swivel, L.loft, L.speed, L.noseDown, L.rollLand, L.spin,
			L.wobble, L.digGain)
	else
		world.launchBaton(w, a.x, a.y, a.swivel, a.loftDeg, a.speed, a.tumbleRate, a.tilt, s.batonId)
	end
	local trail, lonely = {}, 0
	while not world.isAtRest(w) do
		world.step(w)
		if w.loneStep == w.steps then lonely = lonely + 1 end
		if w.steps % 10 == 0 then trail[#trail + 1] = state(w) end
	end
	trail[#trail + 1] = state(w)
	world.loneFlight = saved
	return table.concat(trail, "\n"), lonely
end

test("lone flight: the match throws are bit-identical with it off and on", function()
	for _, t in ipairs(bench.matchThrows) do
		local off, n0 = play(t, false)
		local on, n1 = play(t, true)
		expect.eq(n0, 0)
		expect.truthy(n1 > 100)
		expect.truthy(off == on)
	end
end)
