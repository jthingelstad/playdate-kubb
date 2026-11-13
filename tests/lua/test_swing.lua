import "core/swing"
local swing = tw.swing

local DT = 1 / 50
local BACK = -swing.tune.forwardSign
local FWD = swing.tune.forwardSign

-- Build a flat {dt, delta, ...} trace from forward-degree steps per frame
-- (negative = back). Raw deltas carry the crank sign.
local function trace(parts)
	local out = {}
	for _, p in ipairs(parts) do
		for _ = 1, (p.n or 1) do
			out[#out + 1] = DT
			out[#out + 1] = p.d * FWD
		end
	end
	return out
end

local function windup(deg, frames)
	return { d = -deg / frames, n = frames }
end

local function run(parts)
	return swing.replay(trace(parts))
end

local function flick(steps)
	local parts = { windup(120, 30), { d = 0, n = 5 } }
	for _, d in ipairs(steps) do parts[#parts + 1] = { d = d } end
	return parts
end

test("crank direction is one constant", function()
	expect.truthy(swing.tune.forwardSign == 1 or swing.tune.forwardSign == -1)
	-- with the sign flipped, the same raw trace mirrored still throws
	local raw = trace(flick { 6, 12, 18, 22, 24, 24, 24 })
	local old = swing.tune.forwardSign
	swing.tune.forwardSign = -old
	for i = 2, #raw, 2 do raw[i] = -raw[i] end
	local ev, r = swing.replay(raw)
	swing.tune.forwardSign = old
	expect.eq(ev, "release")
	expect.truthy(r.power > 0.9)
end)

test("clean strong flick: legal, smooth, power near 1", function()
	local ev, r = run(flick { 6, 12, 18, 22, 24, 24, 24 })
	expect.eq(ev, "release")
	expect.eq(r.how, "passed")
	expect.truthy(r.power >= 0.95, "power " .. r.power)
	expect.truthy(r.smoothness >= 0.9, "smoothness " .. r.smoothness)
	expect.truthy(r.tilt <= 30 and r.legal, "tilt " .. r.tilt)
	expect.near(r.launchSpeed, swing.tune.launchMax, 0.3)
	expect.truthy(r.tumbleRate > 6 and r.tumbleRate <= swing.tune.tumbleMax + 1e-9)
end)

test("weak flick: low power, still legal", function()
	local steps = {}
	for i = 1, 26 do steps[i] = 5 end      -- 250 deg/s, steady
	local ev, r = run(flick(steps))
	expect.eq(ev, "release")
	expect.truthy(r.power < 0.3, "power " .. r.power)
	expect.truthy(r.legal, "steady is legal")
	expect.truthy(r.launchSpeed < 6, "launch " .. r.launchSpeed)
end)

test("stuttered flick: fast and near-stopped frames alternate, is a helicopter", function()
	local ev, r = run(flick { 40, 2, 40, 2, 40, 2 })
	expect.eq(ev, "release")
	expect.truthy(r.tilt > 30, "tilt " .. r.tilt)
	expect.eq(r.legal, false)
end)

test("uneven but honest flick is legal (hardware sampling jitter)", function()
	-- speeds from a recorded hardware flick at 41 ms frames: 391, 1454, 775, 798, 1244 deg/s
	local ev, r = swing.replay(trace {
		windup(120, 12), { d = 0 }, { d = 16 }, { d = 60 }, { d = 32 }, { d = 33 }, { d = 51 } })
	expect.eq(ev, "release")
	expect.truthy(r.legal, "tilt " .. r.tilt)
end)

test("slow forward return lets the wind-up down: no throw", function()
	local ev = run { windup(90, 20), { d = 2, n = 60 } }
	expect.eq(ev, "letdown")
end)

test("wind-up alone is no throw", function()
	local s = swing.new()
	local t = trace { windup(100, 25), { d = 0, n = 50 } }
	for i = 1, #t, 2 do expect.eq(swing.update(s, t[i + 1], t[i]), nil) end
	expect.eq(s.phase, "winding")
	expect.near(s.backswing, 100, 1e-9)
end)

test("backswing caps power", function()
	local ev, r = run { windup(40, 10), { d = 25, n = 2 } }
	expect.eq(ev, "release")
	expect.truthy(r.power <= 40 / swing.tune.fullBackswingDeg + 1e-9, "power " .. r.power)
	-- and the backswing itself stops growing at backswingMaxDeg
	local s = swing.new()
	local t = trace { windup(400, 40) }
	for i = 1, #t, 2 do swing.update(s, t[i + 1], t[i]) end
	expect.near(s.backswing, swing.tune.backswingMaxDeg, 1e-9)
end)

test("forward speed falling below half its peak releases early", function()
	local ev, r = run(flick { 10, 20, 24, 6, 2 })
	expect.eq(ev, "release")
	expect.eq(r.how, "slowed")
	expect.truthy(r.power > 0.5, "released at speed, power " .. r.power)
end)

test("a little crank jitter while idle does not start a wind-up", function()
	local s = swing.new()
	local t = trace { { d = -2 }, { d = 2 }, { d = -3 }, { d = 1 }, { d = -2 } }
	for i = 1, #t, 2 do swing.update(s, t[i + 1], t[i]) end
	expect.eq(s.phase, "idle")
end)

test("the arm angle is measured from the bottom of the turn", function()
	local f = swing.tune.forwardSign
	expect.near(swing.armAngle(180), 0, 1e-9)
	expect.near(swing.armAngle(180 - 30 * f), -30, 1e-9, "30 degrees back")
	expect.near(swing.armAngle(180 + 45 * f), 45, 1e-9, "45 degrees forward")
	expect.near(math.abs(swing.armAngle(0)), 180, 1e-9, "straight up")
end)

test("the throw arms only when the crank crosses the bottom going back", function()
	expect.truthy(swing.crossedBack(5, -4))
	expect.truthy(swing.crossedBack(0, -10))
	expect.truthy(not swing.crossedBack(-20, -40), "already behind the bottom")
	expect.truthy(not swing.crossedBack(170, -170), "across the top of the turn")
	expect.truthy(not swing.crossedBack(nil, -10), "first frame")
	expect.truthy(not swing.crossedBack(-5, 5), "going forward")
end)
