-- A clean baton is aimed through its piece at the piece's mid-height
-- (plan.aimZFor, plan.tune.aimHeightShare), not at its foot (a play test,
-- 2026-11-16: "all of them went clean over the field kubb"). The plan's
-- speed solve, its flight time and tumble, the computer's aim and a real
-- flight through the air.
import "core/tw"
import "core/throwplan"
import "core/flight"
import "core/body"
import "core/world"
import "core/autothrow"
local plan, flight, body, world, autothrow = tw.plan, tw.flight, tw.body, tw.world, tw.autothrow
local rad = math.rad

local function solve(d, release, aimZ)
	return plan.solve({ projectile = "baton", px = 0, py = 0, tx = 0, ty = d, release = release,
		level = "club", aimZ = aimZ }, {})
end

test("aim heights: half a kubb, half the king, the ground off a piece", function()
	expect.near(plan.aimZFor("kubb"), body.kinds.kubb.hz, 1e-12)
	expect.near(plan.aimZFor("king"), body.kinds.king.hz, 1e-12)
	expect.near(plan.aimZFor("kubb"), 0.075, 1e-9)
	expect.near(plan.aimZFor("king"), 0.15, 1e-9)
	expect.eq(plan.aimZFor(nil), 0)
	local share = plan.tune.aimHeightShare
	plan.tune.aimHeightShare = 0
	expect.eq(plan.aimZFor("kubb"), 0)
	plan.tune.aimHeightShare = share
end)

test("the plan's speed carries the centre to the target at its aim height", function()
	local ft = flight.tune
	for _, d in ipairs { 3, 5.27, 8 } do
		for _, release in ipairs { 30, 60, 90 } do
			for _, z in ipairs { 0, 0.075, 0.15 } do
				local sol = solve(d, release, z)
				expect.near(sol.aimZ, z, 1e-12)
				local R, T = flight.carry(sol.speed, rad(sol.loft), ft.handHeight - z, ft.dragK.baton)
				expect.near(R, d, 0.003)
				expect.near(sol.flightT, T, 0.002)
				expect.near(sol.tumble, plan.tumbleFor(sol.speed, sol.loft, sol.flightT), 1e-9)
			end
		end
		-- at the same loft, a centre aimed higher is thrown a little harder and
		-- gets there sooner
		local foot, mid = solve(d, 60, 0), solve(d, 60, 0.075)
		expect.truthy(mid.speed > foot.speed and mid.flightT < foot.flightT,
			string.format("%.2f m: %.3f > %.3f", d, mid.speed, foot.speed))
	end
	-- no aimZ is the ground, as before
	local a, b = solve(6, 60), solve(6, 60, 0)
	expect.eq(a.speed, b.speed)
	expect.eq(a.aimZ, 0)
end)

test("a launch with no tumble on the plan takes its flight to the aim height", function()
	local sol = solve(5.27, 60, 0.075)
	local T = plan.flightTime(sol.speed, sol.loft, sol.aimZ)
	expect.near(T, sol.flightT, 0.002)
end)

-- From 5 m out the clean field throw's ends are clear of the grass until
-- the target (nearer, an end can brush the ground first: aimed at the foot,
-- the centre crossed 2 to 15 cm up).
test("in the air the clean throw's centre passes the target at the aim height", function()
	for _, d in ipairs { 5.27, 8 } do
		local z = plan.aimZFor("kubb")
		local sol = solve(d, 60, z)
		local w = world.new { surface = "grass", pieces = {}, stakes = false, groundSeed = 1 }
		local b = world.launchBaton(w, 0, 0, sol.swivel, sol.loft, sol.speed, sol.tumble, 0)
		local py, pz = b.y, b.z
		local at
		for _ = 1, 240 * 3 do
			world.step(w)
			if b.y >= d then
				at = pz + (b.z - pz) * (d - py) / (b.y - py)
				break
			end
			py, pz = b.y, b.z
		end
		expect.truthy(at, "reached the target line")
		expect.near(at, z, 0.03)
	end
end)

test("the computer aims a baton at mid-height: a kubb's, the king's", function()
	local function setup(role, y)
		local id = role == "king" and "king" or "t1"
		return { kind = "baton", side = "A", lineY = 0, forwardY = 0, kingShot = role == "king",
			targets = { id }, batonId = "baton1",
			pieces = { { id = id, kind = role == "king" and "king" or "kubb", role = role, half = "B", x = 0, y = y } } }
	end
	local a = autothrow.choose(setup("field", 5), autothrow.rng(1), 0)
	expect.near(a.plan.aimZ, 0.075, 1e-9)
	local k = autothrow.choose(setup("king", 4), autothrow.rng(1), 0)
	expect.near(k.plan.aimZ, 0.15, 1e-9)
end)

test("a clean throw at a lone kubb topples it at 3, 5.27 and 8 m", function()
	for _, d in ipairs { 3, 5.27, 8 } do
		local down = 0
		for seed = 1, 4 do
			local sol = solve(d, 60, plan.aimZFor("kubb"))
			local w = world.new { surface = "grass", pieces = { { id = "k", kind = "kubb", x = 0, y = d } },
				stakes = false, groundSeed = seed }
			world.launchBaton(w, 0, 0, sol.swivel, sol.loft, sol.speed, sol.tumble, 0)
			for _ = 1, 240 * 8 do
				world.step(w)
				if world.isAtRest(w) then break end
			end
			if w.byId.k.toppled then down = down + 1 end
		end
		expect.truthy(down >= 3, string.format("%.2f m: %d of 4", d, down))
	end
end)
