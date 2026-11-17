-- tools/mjref/ours.lua: runs every case of cases.lua in the game's engine
-- (core/world, headless, the same world API the game uses) and writes a
-- trace per case and mode to ours.jsonl: each body's pose, velocity, angular
-- velocity (world frame) and whether it pressed the ground, every `every`
-- steps (240 Hz / every), until all is at rest or the case's duration.
--   lua5.4 tools/mjref/ours.lua build/mjref [--every 2] [--only prefix]
local M = dofile((arg[0]:match("^(.*)/[^/]*$") or ".") .. "/common.lua")
local json = M.json
local world, body = tw.world, tw.body
local out = assert(arg[1], "usage: ours.lua <outdir> [--every n] [--only prefix]")
local every, only = 2, nil
local i = 2
while arg[i] do
	if arg[i] == "--every" then every = tonumber(arg[i + 1]); i = i + 2
	elseif arg[i] == "--only" then only = arg[i + 1]; i = i + 2
	else error("unknown option " .. arg[i]) end
end

local function run(c, mode)
	local w = world.new { surface = M.surface(c.surface, mode), stakes = false, groundSeed = 1 }
	local bodies = {}
	for _, d in ipairs(c.bodies) do
		local p, q, v, a = d.pos, d.quat, d.vel, d.angvel
		local b
		if d.projectile then
			b = world.launch(w, d.kind, d.id, p[1], p[2], p[3], q[1], q[2], q[3], q[4],
				v[1], v[2], v[3], a[1], a[2], a[3])
			if d.aero then b.aeroK = world.tune.aeroK end
		else
			b = world.addPiece(w, { id = d.id, kind = d.kind, x = p[1], y = p[2], z = p[3],
				qw = q[1], qx = q[2], qy = q[3], qz = q[4] })
			if not d.resting then
				body.setVelocity(b, v[1], v[2], v[3], a[1], a[2], a[3])
				world.wake(b)
			end
		end
		bodies[#bodies + 1] = b
	end
	local tr = {}
	for k = 1, #bodies do tr[k] = {} end
	local pressed = {}
	local function sample()
		for k, b in ipairs(bodies) do
			local t = tr[k]
			local n = #t
			t[n + 1], t[n + 2], t[n + 3] = b.x, b.y, b.z
			t[n + 4], t[n + 5], t[n + 6], t[n + 7] = b.qw, b.qx, b.qy, b.qz
			t[n + 8], t[n + 9], t[n + 10] = b.vx, b.vy, b.vz
			t[n + 11], t[n + 12], t[n + 13] = b.wx, b.wy, b.wz
			t[n + 14] = pressed[k] and 1 or 0
			pressed[k] = nil
		end
	end
	sample()
	local steps = math.floor(c.duration / world.tune.dt + 0.5)
	local s = 0
	-- the ground flag of a sample: did it press the ground in any step since the last
	while s < steps do
		world.step(w)
		s = s + 1
		for k, b in ipairs(bodies) do if (b.groundImpulse or 0) > 0 then pressed[k] = true end end
		if s % every == 0 then sample() end
		if world.isAtRest(w) then break end
	end
	local r = world.result(w)
	local ids, traces = {}, {}
	for k, b in ipairs(bodies) do ids[k] = b.id; traces[k] = json.numbers(tr[k], "%.6g") end
	local fc, fh = r.firstContact, r.firstHit
	local head = json.encode {
		id = c.id, mode = mode, dt = world.tune.dt * every, steps = s,
		firstContact = fc and { t = fc.t, with = fc.with, x = fc.x, y = fc.y, z = fc.z } or false,
		firstHit = fh and { t = fh.t, with = fh.with } or false,
		toppled = #r.toppled > 0 and r.toppled or json.EMPTY,
		touched = #r.touched > 0 and r.touched or json.EMPTY,
		ids = ids,
	}
	return head:sub(1, -2) .. ',"traces":[' .. table.concat(traces, ",") .. "]}"
end

local f = assert(io.open(out .. "/ours.jsonl", "w"))
local n, t0 = 0, os.clock()
for _, c in ipairs(M.cases.all()) do
	if not only or c.id:sub(1, #only) == only then
		for _, mode in ipairs { "mech", "game" } do
			f:write(run(c, mode), "\n")
		end
		n = n + 1
	end
end
f:close()
print(string.format("ours: %d cases x 2 modes in %.1f s -> %s/ours.jsonl", n, os.clock() - t0, out))
