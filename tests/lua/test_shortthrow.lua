-- The crank throw at a short range (engine 0.8: the hand at a short throw,
-- flight.handAt). The game's own path, as scenes/throw runs it: crank samples
-- shaped like input.swingSteps (a wind-up, a pause, a flick that stops) go
-- through core/swing, the result through plan.launch against the plan, and the
-- baton leaves from the plan's hand (scenes/throw's fire). A clean crank throw
-- at a kubb a step away topples it; overpowering it misses; from 2 m on the
-- hand is the feet, as before.
import "core/swing"
import "core/flight"
import "core/world"
import "core/throwplan"

local swing, flight, world, plan = tw.swing, tw.flight, tw.world, tw.plan
local DT = 0.02   -- the self-tests' frame (input.scripted); 24 degrees a frame is a full flick

-- crank samples (dt, raw crank change) for a wind-up to `back` degrees over
-- 30 frames, 5 still frames and a flick that stops at `stop` (clock degrees
-- past the bottom), as input.swingSteps scripts it
local function samples(back, stop, peak)
	local sign, s = swing.tune.forwardSign, {}
	for _ = 1, 5 do s[#s + 1] = DT; s[#s + 1] = 0 end
	for _ = 1, 30 do s[#s + 1] = DT; s[#s + 1] = -sign * back / 30 end
	for _ = 1, 5 do s[#s + 1] = DT; s[#s + 1] = 0 end
	local left, k = back + stop, 0
	while left > 1e-9 do
		k = k + 1
		local d = (k <= 3) and (peak or 24) * k / 3 or (peak or 24)
		if d > left then d = left end
		s[#s + 1] = DT; s[#s + 1] = sign * d
		left = left - d
	end
	for _ = 1, 20 do s[#s + 1] = DT; s[#s + 1] = 0 end
	return s
end

-- the plan scenes/throw makes for a person's baton at a field kubb d m straight
-- ahead: the default arc for the distance (engine 0.10) on the meter (0.13)
local function solveAt(d)
	return plan.solve({ projectile = "baton", px = 0, py = 0, tx = 0, ty = d,
		release = plan.arcFor("baton", d), meter = plan.meter(), surface = "grass", spin = 0,
		aimZ = plan.aimZFor("kubb") }, {})
end

-- the crank's swing thrown at a kubb d m away (turned yaw); true when it falls
local function throwAt(d, back, stop, yaw)
	local sol = solveAt(d)
	local ev, r = swing.replay(samples(back, stop))
	expect.eq(ev, "release", "the crank released a throw")
	local L = plan.launch(sol, r, { projectile = "baton" }, {})   -- no level: the plan's meter
	local w = world.new { surface = "grass", stakes = false,
		pieces = { { id = "k", kind = "kubb", x = 0, y = d, yaw = yaw or 0 } } }
	world.launchBaton(w, 0, 0, L.swivel, L.loft, L.speed, L.tumble, L.tilt, "baton",
		sol.handZ, sol.handFwd, sol.handTip)
	world.run(w, 4)
	return world.result(w).toppled[1] == "k", sol, L
end

test("short throw: the crank's clean swing at a kubb a step away topples it", function()
	for _, d in ipairs { 0.5, 1.0, 1.5 } do
		local sol = solveAt(d)
		expect.truthy(sol.handZ < flight.tune.handHeight, "the hand is lower at " .. d)
		local fell, _, L = throwAt(d, sol.back, sol.release)
		expect.eq(L.powerV, 0, "power ON at " .. d)
		expect.eq(L.releaseV, 0, "stop ON at " .. d)
		expect.truthy(fell, "toppled at " .. d)
		expect.truthy(throwAt(d, sol.back, sol.release, math.pi / 4), "toppled turned 45 degrees at " .. d)
	end
end)

test("short throw: overpowering the crank at a kubb a step away misses", function()
	-- wound well past the power target (three bands), stopped on the release
	local d, n, of = 1.0, 0, 0
	local sol = solveAt(d)
	for _, extra in ipairs { 3, 3.5, 4 } do
		local back = sol.back + extra * sol.level.powerHalf * 2
		local fell, _, L = throwAt(d, back, sol.release)
		expect.truthy(L.powerV > 0, "the gauge calls it long")
		of = of + 1
		if fell then n = n + 1 end
	end
	expect.truthy(n == 0, "overpowered throws toppled " .. n .. " of " .. of)
end)

test("short throw: from 2 m on the baton leaves from the feet, as before", function()
	for _, d in ipairs { 2.0, 4.0, 8.0 } do
		local sol = solveAt(d)
		expect.eq(sol.handZ, flight.tune.handHeight, "hand height at " .. d)
		expect.eq(sol.handFwd, 0, "hand forward at " .. d)
		expect.eq(sol.handTip, 0, "hand tip at " .. d)
	end
end)
