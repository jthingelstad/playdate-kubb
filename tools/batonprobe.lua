-- How batons and kubbs meet (Tyler's play test, 2026-11-15: "a baton phased
-- through a kubb", "a fast baton barely moved a kubb", "hit twice hard and
-- did not fall", "kubbs feel like they glide"). Three measures:
--
-- 1. The sweep: batons from the baseline at one standing kubb 8 m out, every
--    loft from 8 to 50 degrees and carries from 0.6 m short to 0.35 m past it,
--    over a few grounds, each run to rest. Of the throws that touched the
--    kubb: the share it toppled; the fast ones (over 6 m/s at the touch) that
--    left it standing (top grazes); bounce-backs (tilted past 25 degrees and
--    back up); how often it left the ground (its lowest point over 1 cm up)
--    and for 0.2 s or more.
-- 2. End first: of the same throws, those whose first touch of the ground
--    was on an end (long axis within 45 degrees of upright): how many lost
--    more than three quarters of the spin they came down with within their
--    first 0.05 s on the ground.
-- 3. Tyler's batons (--tyler file): his launches from a traces.jsonl replayed
--    against the base kubbs, the king and a field kubb at his target when it
--    was nearer than 7.5 m, no wind: how many toppled something.
-- 4. The computer's rates (--rates n): core/autothrow's batons (club, its
--    mistakes) at the five base kubbs from the baseline, at one field kubb 2
--    to 5 m from an advantage line, and at the king alone from the baseline;
--    n throws each (seed 11): the share of legal throws that toppled a target.
--
--   lua5.4 tools/batonprobe.lua [--quick] [--seeds 3] [--tyler traces.jsonl] [--rates 400]
--     [--set name=value | --set grass.e=0 | --set collide.batonRound=0 ...]
--     (world.tune, a surface or collide.tune, for trials)
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end
import "core/tw"
import "core/world"
import "core/throwplan"
import "core/autothrow"
import "core/collide"

local world, plan = tw.world, tw.plan
local sqrt, deg, acos, abs = math.sqrt, math.deg, math.acos, math.abs

local seeds, quick, tyler, rates = 3, false, nil, nil
local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--seeds" then seeds = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--tyler" then tyler = arg[i + 1]; i = i + 1
	elseif a == "--rates" then rates = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--quick" then quick = true
	elseif a == "--set" then
		-- --set name=value (world.tune) or surface.name=value (world.surfaces),
		-- to try a change without editing the code
		local key, v = arg[i + 1]:match("^([%w_.]+)=(.+)$")
		local sname, field = key:match("^(%w+)%.([%w_]+)$")
		if sname == "collide" then tw.collide.tune[field] = tonumber(v)
		elseif sname then world.surfaces[sname][field] = tonumber(v)
		else world.tune[key] = tonumber(v) end
		i = i + 1
	end
	i = i + 1
end
if quick then seeds = 1 end

local function spin(b) return sqrt(b.wx * b.wx + b.wy * b.wy + b.wz * b.wz) end
local function lowest(k)
	return k.z - (k.hz * abs(k.r33) + k.hx * abs(k.r31) + k.hy * abs(k.r32))
end

-- 1 and 2: the sweep
local touched, toppled, fastStanding, bounceBack, left, leftLong = 0, 0, 0, 0, 0, 0
local endFirst, killed, endMin = 0, 0, 1
local STEP = 1 / 240
for loft = 8, 50, 3 do
	for dd = -0.6, 0.351, 0.05 do
		local sol = plan.solve({ projectile = "baton", px = 0, py = 0, tx = 0, ty = 8 + dd,
			release = plan.releaseFor(loft), level = "club" }, {})
		local tumble = plan.tumbleFor(sol.speed)
		for seed = 1, seeds do
			local w = world.new { surface = "grass", pieces = { { id = "k", kind = "kubb", x = 0, y = 8 } },
				groundSeed = seed, stakes = false }
			local b = world.launchBaton(w, 0, 0, 0, loft, sol.speed, tumble, 0)
			local k = w.byId.k
			local hitV, maxTilt, airT, rose = nil, 0, 0, false
			local groundStep, spin0, endOn
			for step = 1, 240 * 12 do
				local v = sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
				local s0 = spin(b)
				local wasGround = w.firstContact
				world.step(w)
				if not hitV and k.touchT then hitV = v end
				if not wasGround and w.firstContact and w.firstContact.with == "ground" then
					groundStep, spin0, endOn = step, s0, abs(b.r33) > 0.7071
				end
				-- the least spin in the first 0.05 s on the ground, against the
				-- spin it came down with
				if groundStep and endOn and spin0 > 5 and step <= groundStep + 12 then
					local f = spin(b) / spin0
					if step == groundStep or f < endMin then endMin = f end
					if step == groundStep + 12 then
						endFirst = endFirst + 1
												if endMin < 0.25 then killed = killed + 1 end
					end
				end
				if hitV then
					local t = deg(acos(abs(k.r33) > 1 and 1 or abs(k.r33)))
					if t > maxTilt then maxTilt = t end
					if lowest(k) > 0.01 then rose = true; airT = airT + STEP end
				end
				if world.isAtRest(w) then break end
			end
			if hitV then
				touched = touched + 1
				if k.toppled then toppled = toppled + 1
				else
					if hitV > 6 then fastStanding = fastStanding + 1 end
					if maxTilt > 25 then bounceBack = bounceBack + 1 end
				end
				if rose then left = left + 1 end
				if airT >= 0.2 then leftLong = leftLong + 1 end
			end
		end
	end
end
print(string.format("sweep: %d throws touched the kubb, %d toppled (%.0f%%)", touched, toppled, 100 * toppled / touched))
print(string.format("  fast (> 6 m/s) and left standing: %d", fastStanding))
print(string.format("  bounce-backs (past 25 degrees, back up): %d", bounceBack))
print(string.format("  kubb left the ground: %d (%.0f%%), for 0.2 s or more: %d", left, 100 * left / touched, leftLong))
print(string.format("end first: %d landings; lost more than three quarters of their spin in the first 0.05 s: %d (%.0f%%)",
	endFirst, killed, endFirst > 0 and 100 * killed / endFirst or 0))

-- 3: Tyler's batons
if tyler then
	local n, hit = 0, 0
	for line in io.lines(tyler) do
		if line:find('"event":"release"', 1, true) and line:find('"projectile":"baton"', 1, true) then
			local res = line:match('"result":(%b{})')
			local r = {}
			for key, v in res:gmatch('"([%w_]+)":([^,}]+)') do r[key] = tonumber(v) end
			if r.launchSpeed then
				n = n + 1
				local pieces = {}
				for j = 1, 5 do pieces[#pieces + 1] = { id = "b" .. j, kind = "kubb", x = j - 3, y = 8 } end
				pieces[#pieces + 1] = { id = "king", kind = "king", x = 0, y = 4 }
				if r.ty < 7.5 then pieces[#pieces + 1] = { id = "f1", kind = "kubb", x = r.tx, y = r.ty } end
				local w = world.new { surface = "grass", pieces = pieces }
				local sw = math.atan(r.tx - r.px, r.ty - r.py) + math.rad(r.swivelOff or 0)
				world.launchBaton(w, r.px, r.py, sw, r.launchLoft, r.launchSpeed, r.tumbleRate, r.tilt or 0)
				world.run(w)
				local res2 = world.result(w)
				if #res2.toppled > 0 then hit = hit + 1 end
			end
		end
	end
	print(string.format("Tyler's batons: %d of %d toppled something", hit, n))
end

-- 4: the computer's rates
if rates then
	local autothrow = tw.autothrow
	local r = autothrow.rng(11)
	local function setupFor(kind)
		local pieces, s = {}, nil
		if kind == "field" then
			local fy = 4.2 + r.next() * 2.5
			local fx = -1.5 + r.next() * 3
			pieces[1] = { id = "f1", kind = "kubb", role = "field", x = fx, y = fy }
			s = { targets = { "f1" }, forwardY = fy - (2 + r.next() * 3) }
		elseif kind == "king" then
			s = { targets = { "king" }, forwardY = 0, kingShot = true }
		else
			s = { targets = { "b1", "b2", "b3", "b4", "b5" }, forwardY = 0 }
		end
		if kind ~= "king" then
			for j = 1, 5 do pieces[#pieces + 1] = { id = "b" .. j, kind = "kubb", role = "base", x = j - 3, y = 8 } end
		end
		pieces[#pieces + 1] = { id = "king", kind = "king", role = "king", x = 0, y = 4 }
		s.kind, s.pieces, s.lineY, s.batonId = "baton", pieces, 0, "baton"
		return s
	end
	for _, kind in ipairs { "base", "field", "king" } do
		local down, legal = 0, 0
		for _ = 1, rates do
			local s = setupFor(kind)
			local a = autothrow.choose(s, r)
			if a.legal then
				legal = legal + 1
				local w = world.new { surface = "grass", pieces = s.pieces }
				autothrow.launch(w, s, a)
				world.run(w)
				local want = {}
				for _, id in ipairs(s.targets) do want[id] = true end
				for _, id in ipairs(world.result(w).toppled) do
					if want[id] then down = down + 1; break end
				end
			end
		end
		print(string.format("computer at %-5s %d of %d legal throws toppled a target (%.0f%%)", kind, down, legal,
			100 * down / legal))
	end
end
