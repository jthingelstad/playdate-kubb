-- The crank's direction setting and the nudge (device/crank), and a flipped
-- device's traces replaying as they were thrown (core/trace's recorded sign).
import "device/crank"
import "core/swing"
import "core/trace"
local crank, swing, trace = tw.crank, tw.swing, tw.trace

-- every test leaves the core's own sign in place
local function restore() crank.apply(false) end

-- the throw scene's nudge numbers, as in scenes/throw's tune
local T = { nudgeTurns = 3, nudgeTurnDeg = 60, nudgeBottomDeg = 20 }

test("crank: the saved setting reads back flipped only from { flipped = true }", function()
	expect.eq(crank.valid({ flipped = true }), true)
	expect.eq(crank.valid({ flipped = false }), false)
	expect.eq(crank.valid(nil), false)
	expect.eq(crank.valid("flipped"), false)
	expect.eq(crank.valid({ flipped = "yes" }), false)
	expect.eq(crank.valid({}), false)
	expect.eq(crank.valid(crank.save(true)), true)
	expect.eq(crank.valid(crank.save(false)), false)
end)

test("crank: flipping turns the core's sign over and back", function()
	expect.eq(crank.defaultSign, -1, "today's direction (core/swing)")
	crank.apply(true)
	expect.eq(crank.flipped, true)
	expect.eq(swing.tune.forwardSign, 1)
	-- the arm reads the other way round: 3 o'clock (crank 90 from 12) is
	-- forward on a flipped crank, back on today's
	expect.eq(swing.armAngle(270), 90)
	crank.apply(false)
	expect.eq(swing.tune.forwardSign, -1)
	expect.eq(swing.armAngle(270), -90)
	restore()
end)

test("crank: a flipped crank throws with the turn that let today's down", function()
	-- wound 120 back over 20 frames, flicked 210 forward at 24 a frame
	local function samples(sign)
		local s = {}
		for _ = 1, 20 do s[#s + 1] = 0.02; s[#s + 1] = -sign * 6 end
		local left = 210
		while left > 0 do
			local d = math.min(24, left)
			s[#s + 1] = 0.02; s[#s + 1] = sign * d
			left = left - d
		end
		for _ = 1, 5 do s[#s + 1] = 0.02; s[#s + 1] = 0 end
		return s
	end
	crank.apply(true)
	local ev = swing.replay(samples(1))
	expect.eq(ev, "release", "flipped, turned the flipped way")
	local evWrong = swing.replay(samples(-1))
	expect.truthy(evWrong ~= "release", "flipped, turned today's way: no throw")
	restore()
end)

test("crank: a flipped device's trace replays as thrown, with its recorded sign", function()
	crank.apply(true)
	local flat = {}
	for _ = 1, 20 do flat[#flat + 1] = 0.02; flat[#flat + 1] = 6 * -swing.tune.forwardSign end
	for _, d in ipairs({ 8, 16, 24, 24, 24, 24, 24, 24, 0, 0, 0 }) do
		flat[#flat + 1] = 0.02; flat[#flat + 1] = d * swing.tune.forwardSign
	end
	local ev, r = swing.replay(flat)
	expect.eq(ev, "release")
	local back, rel = r.back, r.releaseAngle
	local line = trace.encode(flat, #flat // 2, "release", r, swing.tune.forwardSign, "2026-11-19 12:00:00")
	-- the desktop replays with the core's own sign
	restore()
	local t = trace.decode(line)
	expect.eq(t.sign, 1, "the trace says the crank was flipped")
	local ev2, r2 = trace.replay(t)
	expect.eq(ev2, "release", "replayed with the recorded sign")
	expect.near(r2.back, back, 1e-9)
	expect.near(r2.releaseAngle, rel, 1e-9)
	-- with today's sign instead the same samples are the other way round
	local ev3 = trace.replay(t, true)
	expect.truthy(ev3 ~= "release", "with the current sign it does not throw")
end)

test("crank nudge: three forward turns from the bottom show it", function()
	local N = crank.nudgeNew()
	local function turn(to)
		for a = 0, to, 5 do crank.nudgeArm(N, a, T) end
		for a = to, 0, -5 do crank.nudgeArm(N, a, T) end
	end
	turn(90); expect.eq(N.n, 1)
	turn(90); expect.eq(N.n, 2)
	expect.eq(crank.nudgeShown(N, T), false)
	turn(90); expect.eq(N.n, 3)
	expect.eq(crank.nudgeShown(N, T), true)
end)

test("crank nudge: short turns, turns from off the bottom and nil do not count", function()
	local N = crank.nudgeNew()
	for a = 0, 55, 5 do crank.nudgeArm(N, a, T) end   -- short of 60
	expect.eq(N.n, 0)
	crank.nudgeArm(N, nil, T)
	expect.eq(N.n, 0)
	-- from 3 o'clock (where a throw leaves the crank) up to 12: not from the bottom
	local M = crank.nudgeNew()
	for a = 90, 180, 5 do crank.nudgeArm(M, a, T) end
	expect.eq(M.n, 0)
	-- back from the bottom first, then forward without passing the bottom zone again
	local B = crank.nudgeNew()
	crank.nudgeArm(B, 0, T); crank.nudgeArm(B, -40, T); crank.nudgeArm(B, 70, T)
	expect.eq(B.n, 0)
	-- one turn that goes on round counts once until it is back at the bottom
	local R = crank.nudgeNew()
	for a = 0, 180, 10 do crank.nudgeArm(R, a, T) end
	for a = -170, 0, 10 do crank.nudgeArm(R, a, T) end
	expect.eq(R.n, 1)
	for a = 0, 90, 10 do crank.nudgeArm(R, a, T) end
	expect.eq(R.n, 2, "round again: the next turn")
	-- a fast frame that jumps straight past 60 still counts
	local F = crank.nudgeNew()
	crank.nudgeArm(F, 5, T); crank.nudgeArm(F, 75, T)
	expect.eq(F.n, 1)
end)

test("crank nudge: a wind-up hides it until one more turn, a throw clears it", function()
	local N = crank.nudgeNew()
	N.n = 3
	crank.nudgeWound(N, T)
	expect.eq(crank.nudgeShown(N, T), false, "hidden by the wind-up")
	expect.eq(N.n, 2)
	crank.nudgeArm(N, 0, T); crank.nudgeArm(N, 65, T)
	expect.eq(crank.nudgeShown(N, T), true, "one more forward turn")
	crank.nudgeClear(N)
	expect.eq(N.n, 0)
	expect.eq(crank.nudgeShown(N, T), false)
	-- a wind-up with fewer than the turns keeps the count
	local M = crank.nudgeNew()
	M.n = 1
	crank.nudgeWound(M, T)
	expect.eq(M.n, 1)
end)
