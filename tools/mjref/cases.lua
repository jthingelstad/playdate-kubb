-- The canonical scenarios of the reference-engine comparison (tools/mjref).
-- Each case is one initial state: every body's pose, velocity and angular
-- velocity (world frame), made here once with the game's own launch code
-- (world.batonLaunchState, world.drillLaunchState, drill.solveAt,
-- plan.tumbleFor). ours.lua runs it in core/world and mjref.py in MuJoCo, so
-- the two engines start from the same numbers.
--
-- A case: { id, scen, group, params = {name = value}, surface, duration,
--   bodies = { { id, kind, pos, quat (w x y z), vel, angvel, projectile,
--   aero, resting } }, extra = { ... } }.
-- `resting` bodies start asleep in our engine (a piece standing on the
-- pitch); MuJoCo has no sleep and starts them at rest on the ground.
local quat, body, world, flight, drill, plan = tw.quat, tw.body, tw.world, tw.flight, tw.drill, tw.plan
local sin, cos, rad, sqrt = math.sin, math.cos, math.rad, math.sqrt

local cases = {}

local function v3(x, y, z) return { x, y, z } end

-- A body table from the 13 numbers of a launch state.
local function fromState(id, kind, s, extra)
	local b = {
		id = id, kind = kind,
		pos = v3(s[1], s[2], s[3]), quat = { s[4], s[5], s[6], s[7] },
		vel = v3(s[8], s[9], s[10]), angvel = v3(s[11], s[12], s[13]),
	}
	for k, v in pairs(extra or {}) do b[k] = v end
	return b
end

-- A piece at rest on the ground with this orientation (local axes as world
-- vectors), its lowest point on z = 0.
local function resting(id, kind, x, y, qw, qx, qy, qz)
	local b = body.new(kind, id)
	body.setPose(b, x, y, 0, qw or 1, qx or 0, qy or 0, qz or 0)
	local z = -body.lowestZ(b)
	return { id = id, kind = kind, pos = v3(x, y, z), quat = { b.qw, b.qx, b.qy, b.qz },
		vel = v3(0, 0, 0), angvel = v3(0, 0, 0), resting = true }
end

-- A standing kubb (or king) struck by a horizontal impulse J (N s) along +y at
-- height h on its -y face, at x = 0: the state just after the blow.
local function struck(id, kind, x, y, J, h)
	local b = resting(id, kind, x, y)
	local k = body.kinds[kind]
	local Ix = body.inertia(k)
	local rz = h - b.pos[3]
	b.vel = v3(0, J / k.mass, 0)
	-- w = I^-1 (r x J), r = (0, -hy, rz), J = (0, J, 0): r x J = (-rz J, 0, 0)
	b.angvel = v3(-rz * J / Ix, 0, 0)
	b.resting = false
	return b
end

-- A baton with its long axis u = (0, cos phi, sin phi) (phi above the
-- horizontal, the upper end forward for phi < 90), local x across.
local function batonQuat(phi)
	local c, s = cos(phi), sin(phi)
	return { quat.fromAxes(1, 0, 0, 0, s, -c, 0, c, s) }
end

-- A broadside baton: long axis along x, at (x, y, z).
local function broadsideQuat()
	return { quat.fromAxes(0, 1, 0, 0, 0, 1, 1, 0, 0) }
end

local function add(list, c) list[#list + 1] = c end

local function fmt(x) return string.format("%g", x) end

function cases.all()
	local list = {}
	local surfaces = world.SURFACES
	local bk = body.kinds.baton
	local kk = body.kinds.kubb

	-- 0. drops: the bounce each engine gives a flat landing (sanity, and the
	-- check that restitution is mapped right).
	for _, surf in ipairs(surfaces) do
		for _, v in ipairs { 1, 2, 4 } do
			-- a kubb lying flat (long axis along x), 2 cm above the ground, falling
			local q = broadsideQuat()
			add(list, { id = "drop-kubb-" .. surf .. "-" .. v, scen = "drop", group = "kubb flat " .. surf,
				params = { v = v }, surface = surf, duration = 1.5,
				bodies = { { id = "k", kind = "kubb", pos = v3(0, 1, 0.035 + 0.02), quat = q,
					vel = v3(0, 0, -v), angvel = v3(0, 0, 0) } } })
			add(list, { id = "drop-baton-" .. surf .. "-" .. v, scen = "drop", group = "baton flat " .. surf,
				params = { v = v }, surface = surf, duration = 1.5,
				bodies = { { id = "b", kind = "baton", pos = v3(0, 1, bk.r + 0.02), quat = q,
					vel = v3(0, 0, -v), angvel = v3(0, 0, 0) } } })
		end
	end

	-- 1. a baton landing: its long axis phi above the horizontal at the touch
	-- (90 end first; under 90 the trailing end low, over 90 the leading end
	-- low), coming down at 7 m/s forward and 4.5 down (an 8 m throw at about
	-- 30 degrees), turning end over end at 6.5 rad/s (the plan's 8 m rate).
	-- It starts `gap` m above the ground: at 4.5 m/s a 240 Hz step covers
	-- 1.9 cm, so the three gaps meet the ground at different points of a step
	-- (the same landing; only where the step boundary falls differs).
	for _, surf in ipairs(surfaces) do
		for phiDeg = 0, 165, 15 do
			for _, gap in ipairs { 0.002, 0.006, 0.010 } do
				local phi = rad(phiDeg)
				local zc = bk.hl * math.abs(sin(phi)) + bk.r + gap
				add(list, { id = string.format("land-%s-%d-%g", surf, phiDeg, gap), scen = "landing", group = surf,
					params = { phi = phiDeg, gap = gap }, surface = surf, duration = 6,
					bodies = { { id = "baton", kind = "baton", pos = v3(0, 2, zc), quat = batonQuat(phi),
						vel = v3(0, 7, -4.5), angvel = v3(-6.5, 0, 0), projectile = true } } })
			end
		end
	end

	-- 2. a broadside strike on a standing kubb: the baton flat and across the
	-- line, flying level at speed v with its centre at height h, 3 cm from the
	-- kubb's face.
	for _, h in ipairs { 0.03, 0.05, 0.07, 0.09, 0.11, 0.13, 0.145 } do
		for _, v in ipairs { 2, 4, 6, 8, 10 } do
			add(list, { id = "side-" .. fmt(h) .. "-" .. v, scen = "broadside", group = "h " .. fmt(h),
				params = { h = h, v = v }, surface = "grass", duration = 4,
				bodies = {
					resting("kubb", "kubb", 0, 0),
					{ id = "baton", kind = "baton", pos = v3(0, -kk.hy - bk.r - 0.03, h), quat = broadsideQuat(),
						vel = v3(0, v, 0), angvel = v3(0, 0, 0), projectile = true },
				} })
		end
	end

	-- 3. the king struck broadside.
	local kg = body.kinds.king
	for _, h in ipairs { 0.05, 0.10, 0.15, 0.20, 0.25, 0.29 } do
		for _, v in ipairs { 4, 6, 8, 10 } do
			add(list, { id = "king-" .. fmt(h) .. "-" .. v, scen = "king", group = "h " .. fmt(h),
				params = { h = h, v = v }, surface = "grass", duration = 4,
				bodies = {
					resting("king", "king", 0, 0),
					{ id = "baton", kind = "baton", pos = v3(0, -kg.hy - bk.r - 0.03, h), quat = broadsideQuat(),
						vel = v3(0, v, 0), angvel = v3(0, 0, 0), projectile = true },
				} })
		end
	end

	-- 4. Tyler's case: a baton coming down end over end `short` m before a
	-- standing kubb's centre, its long axis at phi at the nominal touch. It
	-- starts 0.08 s earlier on the drag-free arc that gets it there.
	local T0, w = 0.08, 6.5
	for _, short in ipairs { 0.2, 0.3, 0.4 } do
		for phiDeg = 0, 165, 15 do
			local phi = rad(phiDeg)
			local zc = bk.hl * math.abs(sin(phi)) + bk.r
			local vy, vz = 7, -4.5
			local g = world.tune.g
			-- back along the arc (the tumble turns phi down by w a second)
			local y0 = -short - vy * T0
			local z0 = zc - vz * T0 - 0.5 * g * T0 * T0
			add(list, { id = "endon-" .. fmt(short) .. "-" .. phiDeg, scen = "endon", group = "short " .. fmt(short),
				params = { short = short, phi = phiDeg }, surface = "grass", duration = 5,
				bodies = {
					resting("kubb", "kubb", 0, 0),
					{ id = "baton", kind = "baton", pos = v3(0, y0, z0), quat = batonQuat(phi + w * T0),
						vel = v3(0, vy, vz + g * T0), angvel = v3(-w, 0, 0), projectile = true },
				} })
		end
	end

	-- 5. the tip threshold: a standing kubb struck at height h by a blow J,
	-- a geometric grid of J (the threshold is the smallest J that topples it).
	for _, surf in ipairs { "grass", "snow" } do
		for _, h in ipairs { 0.02, 0.04, 0.06, 0.08, 0.10, 0.12, 0.14 } do
			local J = 0.04
			local n = 0
			while J <= 1.6 do
				n = n + 1
				add(list, { id = string.format("tip-%s-%g-%02d", surf, h, n), scen = "tip",
					group = surf .. " h " .. fmt(h), params = { h = h, J = J }, surface = surf, duration = 3,
					bodies = { struck("kubb", "kubb", 0, 0, J, h) } })
				J = J * 1.08
			end
		end
	end

	-- 6. a kubb struck into a kubb `gap` m behind it (faces parallel), and a
	-- tight row of three.
	for _, h in ipairs { 0.04, 0.12 } do
		for _, gap in ipairs { 0.001, 0.03, 0.07, 0.15 } do
			for _, J in ipairs { 0.1, 0.15, 0.2, 0.3, 0.4, 0.6 } do
				add(list, { id = string.format("pair-%g-%g-%g", h, gap, J), scen = "domino",
					group = "pair h " .. fmt(h) .. " gap " .. fmt(gap), params = { h = h, gap = gap, J = J },
					surface = "grass", duration = 4,
					bodies = { struck("A", "kubb", 0, 0, J, h), resting("B", "kubb", 0, 2 * kk.hy + gap) } })
			end
		end
		for _, gap in ipairs { 0.001, 0.03 } do
			for _, J in ipairs { 0.1, 0.15, 0.2, 0.3, 0.4, 0.6 } do
				add(list, { id = string.format("row3-%g-%g-%g", h, gap, J), scen = "domino",
					group = "row3 h " .. fmt(h) .. " gap " .. fmt(gap), params = { h = h, gap = gap, J = J },
					surface = "grass", duration = 4,
					bodies = { struck("A", "kubb", 0, 0, J, h), resting("B", "kubb", 0, 2 * kk.hy + gap),
						resting("C", "kubb", 0, 2 * (2 * kk.hy + gap)) } })
			end
		end
	end

	-- 7. a drilled kubb: the plan's clean drill (no scatter) onto a mark 6 m
	-- out at loft 30 and 47 (half past 1), 0 to 3 taps of spin, the release
	-- nose angle 4 degrees either way of the tune's, on each ground; the air's
	-- drag and turn in flight.
	local dt = drill.tune
	for _, surf in ipairs(surfaces) do
		for _, loft in ipairs { 30, 47 } do
			for taps = 0, 3 do
				for _, dn in ipairs { -4, 0, 4 } do
					local spin = taps * plan.tune.spinPerStep
					local sol = drill.solveAt(0, 6, 0, loft, {}, 0, surf, spin)
					local bd = drill.body(1, 1, spin, {})
					local s = { world.drillLaunchState(0, 0, 0, loft, sol.speed, bd.noseDown + dn, bd.rollLand,
						bd.spin, 0, 0, 0, 0, 0) }
					add(list, { id = string.format("drill-%s-%d-%d-%d", surf, loft, taps, dn), scen = "drill",
						group = string.format("%s loft %d", surf, loft),
						params = { loft = loft, taps = taps, nose = dt.noseDownDeg + dn },
						surface = surf, duration = 8,
						extra = { markX = 0, markY = 6, land = sol.land },
						bodies = { fromState("drill", "kubb", s, { projectile = true, aero = true }) } })
				end
			end
		end
	end

	-- 8. free flight: drag only, against flight.carry (the aim's arithmetic) to
	-- the moment the centre comes down through zCross.
	local zCross = 0.3
	local h = flight.tune.handHeight
	for _, loft in ipairs { 10, 20, 30, 40, 50 } do
		for _, v in ipairs { 5, 7, 9, 11 } do
			local s = { world.batonLaunchState(0, 0, 0, loft, v, plan.tumbleFor(v, loft), 0) }
			local R, T = flight.carry(v, rad(loft), h - zCross, flight.tune.dragK.baton)
			add(list, { id = string.format("flight-baton-%d-%d", loft, v), scen = "flight", group = "baton loft " .. loft,
				params = { loft = loft, v = v }, surface = "grass", duration = T + 0.15,
				extra = { zCross = zCross, carryR = R, carryT = T },
				bodies = { fromState("baton", "baton", s, { projectile = true }) } })
		end
	end
	for _, loft in ipairs { 30, 47 } do
		for _, v in ipairs { 5, 7, 9 } do
			local s = { world.drillLaunchState(0, 0, 0, loft, v, dt.noseDownDeg, 0, dt.spiral, 0, 0, 0, 0, 0) }
			local R, T = flight.carry(v, rad(loft), h - zCross, flight.tune.dragK.kubb)
			add(list, { id = string.format("flight-kubb-%d-%d", loft, v), scen = "flight", group = "kubb loft " .. loft,
				params = { loft = loft, v = v }, surface = "grass", duration = T + 0.15,
				extra = { zCross = zCross, carryR = R, carryT = T },
				bodies = { fromState("drill", "kubb", s, { projectile = true, aero = true }) } })
		end
	end
	return list
end

return cases
