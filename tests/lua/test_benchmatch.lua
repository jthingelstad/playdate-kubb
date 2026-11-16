-- The autobench's match case (core/bench.matchSetup, matchThrows) must stay
-- what it says it is: a baton that hits a field kubb, a baton that misses
-- and rolls on, a drilled kubb that lands clear.
import "core/bench"
import "core/drill"
import "core/match"
local bench, world, drill, match = tw.bench, tw.world, tw.drill, tw.match

local function play(t)
	local s = bench.matchSetup(t.projectile)
	local w = world.new { surface = "grass", pieces = match.worldPieces(s) }
	local a = bench.matchThrow(t)
	if a.drill then
		local sol = drill.solve(a.drill.markerX, a.drill.markerY, 0, {})
		local L = drill.launch(sol, { power = sol.band, smoothness = 1, tilt = 0 }, 0, {})
		world.launchDrill(w, s.kubb, sol.x, 0, L.swivel, L.loft, L.speed, L.noseDown, L.rollLand, L.spin,
			L.wobble)
	else
		world.launchBaton(w, a.x, a.y, a.swivel, a.loftDeg, a.speed, a.tumbleRate, a.tilt, s.batonId)
	end
	world.run(w)
	return world.result(w), w
end

test("bench match case: the hit topples f1, the miss and the drill touch nothing", function()
	local byName = {}
	for _, t in ipairs(bench.matchThrows) do byName[t.name] = t end
	local r, w = play(byName.hit)
	expect.eq(r.firstHit and r.firstHit.with, "f1")
	expect.eq(#r.toppled, 1)
	expect.truthy(w.n >= 20)
	r = play(byName.miss)
	expect.eq(r.firstHit, nil)
	expect.eq(#r.touched, 1)
	r = play(byName.drill)
	expect.eq(r.firstHit, nil)
	expect.eq(r.touched[1], "f3")
end)
