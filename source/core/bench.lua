-- The physics benchmark (DESIGN 5): one fixed scenario, a baton thrown into a
-- tight group of five kubbs, stepped for 3 simulated seconds whether or not
-- everything has come to rest. `make bench` runs it on the desktop
-- (tools/bench.lua) and the System Menu "Bench" item runs the very same
-- function on the device; only the clock differs.
import "core/tw"
import "core/world"

local world = tw.world

local bench = {}

bench.seconds = 3
-- five field kubbs standing close together around (0, 4.3), turned a little
bench.pieces = {
	{ id = "b1", kind = "kubb", x = 0.00, y = 4.20, yaw = 0.0 },
	{ id = "b2", kind = "kubb", x = 0.10, y = 4.30, yaw = 0.3 },
	{ id = "b3", kind = "kubb", x = -0.10, y = 4.32, yaw = -0.2 },
	{ id = "b4", kind = "kubb", x = 0.03, y = 4.42, yaw = 0.6 },
	{ id = "b5", kind = "kubb", x = -0.06, y = 4.52, yaw = 0.1 },
}
-- from the baseline center, straight up the pitch, 35 degrees of loft,
-- end over end at 7 rad/s
bench.throw = { x = 0, lineY = 0, swivel = 0, loft = 35, speed = 6.0, tumble = 7, tilt = 0 }

function bench.world()
	local w = world.new{ surface = "grass", pieces = bench.pieces }
	local t = bench.throw
	world.launchBaton(w, t.x, t.lineY, t.swivel, t.loft, t.speed, t.tumble, t.tilt)
	return w
end

-- Run the scenario. clock() returns seconds. If `chunk` is given, `yield`
-- is called every `chunk` steps (the device redraws a progress line there;
-- the time spent in yield is not counted). Returns a result table.
function bench.run(clock, chunk, yield)
	local w = bench.world()
	local steps = math.floor(bench.seconds / world.tune.dt + 0.5)
	local busy, maxAwake, maxContacts = 0, 0, 0
	-- the collision phase: steps with two or more bodies awake (timed one by one)
	local hotSteps, hotTime = 0, 0
	local done = 0
	while done < steps do
		local n = chunk and math.min(chunk, steps - done) or (steps - done)
		local t0 = clock()
		local ts = t0
		for _ = 1, n do
			world.step(w)
			local te = clock()
			if w.awakeCount >= 2 then hotSteps, hotTime = hotSteps + 1, hotTime + (te - ts) end
			ts = te
			if w.awakeCount > maxAwake then maxAwake = w.awakeCount end
			if w.contacts > maxContacts then maxContacts = w.contacts end
		end
		busy = busy + (ts - t0)
		done = done + n
		if yield then yield(done, steps) end
	end
	local r = world.result(w)
	return {
		steps = steps,
		simSeconds = steps * world.tune.dt,
		seconds = busy,
		msPerStep = busy * 1000 / steps,
		stepsPerSecond = steps / busy,
		msPerSimSecond = busy * 1000 / (steps * world.tune.dt),
		hotSteps = hotSteps,
		hotMsPerStep = hotSteps > 0 and hotTime * 1000 / hotSteps or 0,
		maxAwake = maxAwake,
		maxContacts = maxContacts,
		toppled = #r.toppled,
		touched = #r.touched,
	}
end

-- One line of text for the result (the device appends it to bench.txt).
function bench.line(r, where)
	return string.format("%s: %d steps (%.1f s simulated) in %.3f s; %.3f ms/step; %.0f steps/s; %.1f ms per simulated s; %.1f steps per 20 ms frame; collision phase %d steps at %.3f ms/step (%.1f per 20 ms frame); awake max %d, contacts max %d; toppled %d",
		where or "bench", r.steps, r.simSeconds, r.seconds, r.msPerStep, r.stepsPerSecond, r.msPerSimSecond,
		20 / r.msPerStep, r.hotSteps, r.hotMsPerStep, r.hotMsPerStep > 0 and 20 / r.hotMsPerStep or 0,
		r.maxAwake, r.maxContacts, r.toppled)
end

tw.bench = bench
