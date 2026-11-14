-- core/drills: the practice drills' set-ups, scoring and records.
import "core/drills"
local drills = tw.drills

test("drills: five drills, each with a setup for its first throw", function()
	expect.eq(#drills.list, 5)
	for _, d in ipairs(drills.list) do
		local run = drills.newRun(d)
		local s = drills.setup(d, run)
		expect.truthy(s, d.id .. " setup")
		expect.eq(s.n, 1)
		expect.eq(s.of, d.throws)
		if d.kind == "blast" then
			expect.eq(s.projectile, "kubb")
		else
			expect.eq(s.projectile, "baton")
			expect.truthy(#s.targets >= 1, d.id .. " targets")
		end
	end
end)

test("drills: 8 meters counts each kubb once, keeps it down, ends when all five are down", function()
	local d = drills.byId("8m")
	local run = drills.newRun(d)
	expect.eq(drills.tally(d, run, { toppled = { "b2" } }), false)
	expect.eq(run.score, 1)
	local s = drills.setup(d, run)
	for _, p in ipairs(s.pieces) do expect.truthy(p.id ~= "b2", "b2 stays down") end
	drills.tally(d, run, { toppled = { "b2", "king" } })   -- b2 again, and the king: no points
	expect.eq(run.score, 1)
	drills.tally(d, run, { toppled = { "b1", "b3" } })
	expect.eq(drills.tally(d, run, { toppled = { "b4", "b5" } }), true, "all down ends the run")
	expect.eq(run.score, 5)
	expect.eq(drills.setup(d, run), nil)
end)

test("drills: king shots score the king each time it falls; blast scores near the marker", function()
	local k = drills.byId("king")
	local run = drills.newRun(k)
	for i = 1, 6 do drills.tally(k, run, { toppled = (i % 2 == 0) and { "king" } or {} }) end
	expect.eq(run.score, 3)
	expect.truthy(run.done)
	local b = drills.byId("blast")
	run = drills.newRun(b)
	for _, cm in ipairs { 20, 50, 51, 120, 5, 999 } do drills.tally(b, run, { restCm = cm }) end
	expect.eq(run.score, 3)
	expect.truthy(run.done)
end)

test("drills: around the pitch throws from in front of each kubb in turn", function()
	local d = drills.byId("around")
	local run = drills.newRun(d)
	expect.eq(drills.setup(d, run).playerX, -2)
	drills.tally(d, run, {})
	expect.eq(drills.setup(d, run).playerX, -1)
end)

test("drills: records keep the best, the rate and the last ten", function()
	local rec = {}
	local d = drills.byId("8m")
	for i = 1, 12 do
		local run = drills.newRun(d)
		run.score, run.done = (i == 4) and 5 or (i % 4), true
		local r, best = drills.record(rec, d, run)
		if i == 4 then expect.truthy(best, "a new best") end
	end
	local r = rec["8m"]
	expect.eq(r.best, 5)
	expect.eq(r.runs, 12)
	expect.eq(#r.last, 10)
	expect.eq(drills.rate(r), math.floor(100 * r.points / (12 * 5) + 0.5))
end)
