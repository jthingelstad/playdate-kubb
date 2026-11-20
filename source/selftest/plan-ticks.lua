-- Scenario "plan-ticks": the plan's controls take any value in their range
-- (core 0.9: plan.tune arcTickDeg, tiltTickDeg, spinTick). On the practice
-- pitch with a baton, B held: a tap of up moves the release one tick, a tap
-- of left tilts one tick; held, up slides a tick a frame after
-- throw.tune.tickHold (frame 1: the plan view after the slide, TILT L 1).
-- Then a drill: a tap of right spins a quarter (frame 2, SPIN R 0.25), held
-- it slides to plan.tune.spinSteps and stops there. Last, a match's inkast
-- (scenes/match sets setup.turn): the spin is kept for the side's next kubb
-- in the turn and goes in another turn or for the other side.
import "selftest/_throw"
import "core/match"
import "core/names"

local st = tw.selftest
local throw, plan, cmatch = tw.scenes.throw, tw.plan, tw.match
local MISS = {}

local B = { "b" }
local SCRIPT = {
	{ n = 5 },                                     -- 1-5
	{ n = 5, hold = B },                           -- 6-10 the plan view
	{ hold = B, press = { "up" } },                -- 11 a tap: one tick
	{ n = 5, hold = B },                           -- 12-16
	{ hold = B, press = { "left" } },              -- 17 a tap: one tick of tilt
	{ n = 5, hold = B },                           -- 18-22
	{ n = 30, hold = { "b", "up" } },              -- 23-52 held: slides
	{ n = 5, hold = B },                           -- 53-57
	{ n = 10 },                                    -- 58-67 (a drill from 60)
	{ n = 5, hold = B },                           -- 68-72
	{ hold = B, press = { "right" } },             -- 73 a tap: a quarter of spin
	{ n = 5, hold = B },                           -- 74-78
	{ n = 80, hold = { "b", "right" } },           -- 79-158 held: to the end of the range
	{ n = 5, hold = B },                           -- 159-163
}

local function near(a, b) return math.abs(a - b) < 1e-9 end

-- the inkast check: a match to A's tosses at turn 3, set up as scenes/match does
local function inkast()
	local s = throw.new(tw.input.scripted {})
	local m = cmatch.new { start = { year = 2026, month = 11, day = 20, hour = 12, min = 0 },
		teams = tw.names.teams { A = "Ash", B = "Birch" } }
	local g = m.game
	g:throwBaton(MISS); g:throwBaton(MISS)
	g:throwBaton({ toppled = { "a1" } }); g:throwBaton({ toppled = { "a2" } }); g:throwBaton(MISS); g:throwBaton(MISS)
	local function setup()
		local su = cmatch.setup(m)
		su.turn = g.turn
		return su
	end
	local su = setup()
	if su.projectile ~= "kubb" or su.side ~= "A" then return "no inkast for A at turn 3: " .. tostring(su.projectile) end
	throw.prepare(s, su)
	throw.setSpin(s, 1.25)
	g:toss({ rest = { x = 0.4, y = 6.0, standing = false, angle = 0.3 }, moved = {} })
	su = setup()
	if su.projectile ~= "kubb" then return "the second kubb is not a toss" end
	throw.prepare(s, su)
	if s.spin ~= 1.25 then return "the side's next kubb in the turn lost the spin: " .. tostring(s.spin) end
	if s.tilt ~= 0 or s.arcSet then return "the next kubb kept more than the spin" end
	-- another turn, or the other side: the spin goes
	local other = {}
	for k, v in pairs(su) do other[k] = v end
	other.turn = su.turn + 1
	throw.prepare(s, other)
	if s.spin ~= 0 then return "the spin outlived the turn" end
	throw.setSpin(s, -0.5)
	other.side = "B"
	throw.prepare(s, other)
	if s.spin ~= 0 then return "the spin went to the other side" end
	return nil
end

st.scenarios["plan-ticks"] = {
	step = function(ctx)
		if not ctx.scene then
			ctx.scene = throw.new(tw.input.scripted(SCRIPT))
			throw.enter()
		end
		local s, f = ctx.scene, ctx.frame
		local pt = plan.tune
		if f == 60 then throw.setDrill(s, true) end
		throw.update(s)
		throw.draw(s)
		if f == 10 then ctx.rel0 = s.release end
		if f == 11 and not near(s.release, ctx.rel0 + pt.arcTickDeg) then
			error("a tap moved the release to " .. s.release .. " from " .. ctx.rel0)
		end
		if f == 16 and not near(s.release, ctx.rel0 + pt.arcTickDeg) then error("the tap went on moving") end
		if f == 22 and not near(s.tilt, -pt.tiltTickDeg) then error("a tap of left tilted " .. s.tilt) end
		if f == 57 then
			local ticks = (s.release - ctx.rel0) / pt.arcTickDeg
			if ticks < 10 and not near(s.release, pt.releaseMaxDeg) then error("held, the release slid " .. ticks .. " ticks") end
			if s.release > pt.releaseMaxDeg then error("the release went past its range") end
			ctx.ticks = ticks
			ctx:capture()
		end
		if f == 78 then
			if not near(s.spin, pt.spinTick) then error("a tap of right spun " .. s.spin) end
			ctx:capture()
		end
		if f == 163 then
			if not near(s.spin, pt.spinSteps) then error("held, the spin ended at " .. s.spin) end
			local err = inkast()
			if err then error(err) end
			ctx.note = string.format("tap: 1 tick; held 30 frames: %.0f ticks; spin to %s; inkast keeps it", ctx.ticks,
				tostring(s.spin))
			return true
		end
		return false
	end,
}
