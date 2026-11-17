-- tools/mjref/export.lua: writes the game's geometry, masses, inertias and
-- contact and material tunables (params.json) and the canonical scenarios
-- (cases.json) for the MuJoCo side (tools/mjref/mjref.py).
--   lua5.4 tools/mjref/export.lua build/mjref
local M = dofile((arg[0]:match("^(.*)/[^/]*$") or ".") .. "/common.lua")
local json = M.json
local out = assert(arg[1], "usage: export.lua <outdir>")
local world, body, flight, drill, plan, collide = tw.world, tw.body, tw.flight, tw.drill, tw.plan, tw.collide

local kinds = {}
for _, name in ipairs { "kubb", "king", "baton" } do
	local k = body.kinds[name]
	local Ix, Iy, Iz = body.inertia(k)
	kinds[name] = { shape = k.shape == 1 and "box" or "capsule", hx = k.hx, hy = k.hy, hz = k.hz,
		hl = k.hl, r = k.r, length = k.length, mass = k.mass, inertia = { Ix, Iy, Iz } }
end
local surfaces = {}
for _, name in ipairs(world.SURFACES) do
	local s = world.surfaces[name]
	surfaces[name] = { mu = s.mu, e = s.e, roll = s.roll, dig = s.dig, bite = s.bite }
end
local t = world.tune
local params = {
	kinds = kinds, surfaces = surfaces,
	world = { dt = t.dt, g = t.g, pairMu = t.pairMu, pairE = t.pairE, restitutionSpeed = t.restitutionSpeed,
		batonTurnHold = t.batonTurnHold, sleepLin = t.sleepLin, sleepAng = t.sleepAng, sleepTime = t.sleepTime,
		toppleDeg = t.toppleDeg, aeroK = t.aeroK, margin = t.margin, iterations = t.iterations },
	dragK = flight.tune.dragK, handHeight = flight.tune.handHeight,
	batonRound = collide.tune.batonRound,
	drill = { noseDownDeg = drill.tune.noseDownDeg, spiral = drill.tune.spiral, landZ = drill.tune.landZ },
	plan = { spinPerStep = plan.tune.spinPerStep, tumbleTurns = plan.tune.tumbleTurns },
}
local function write(name, s)
	local f = assert(io.open(out .. "/" .. name, "w"))
	f:write(s, "\n")
	f:close()
end
write("params.json", json.encode(params))
local list = M.cases.all()
write("cases.json", json.encode(list))
print(string.format("export: %d cases -> %s", #list, out))
