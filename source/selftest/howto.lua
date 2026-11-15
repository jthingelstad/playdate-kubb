-- Scenario "howto": HOW TO THROW (core/howto) over the practice pitch, every
-- step done with scripted input: the crank down to 6, three real throws on
-- the plan's clean swing (point and throw, power, arc), the d-pad moving the
-- circle, A walking, B moving the arc and tilting, then A to finish. Then it is
-- started again and eight taps of B skip through it. The inputs for each step
-- are fed as the step comes up (the throws are built from the plan as it is
-- then: the first throw knocks b3 down and the circle moves on).
-- Frames (one per step, and what each throw step said after its throw):
--   01 the crank   02 the crank done   03 point and throw   04 its verdicts
--   05 power       06 power done       07 the arc           08 arc done
--   09 the d-pad   10 d-pad done       11 walk              12 walk done
--   13 plan (B held, the camera out)   14 plan done         15 the last step
--   16 the pitch once A has ended it (no panel)
--   17 the same after B tapped through a second run
import "selftest/_throw"
import "core/howto"
import "render/howto"

local st = tw.selftest
local throw = tw.scenes.throw

-- Append input steps to the scene's scripted provider (it may have run out:
-- start it again on the first new step).
local function feed(s, list)
	local p = s.input
	if p:finished() then p.k = 0 end
	for _, st in ipairs(list) do p.steps[#p.steps + 1] = st end
end

local function at(s, step, phase)
	local h = s.howto
	return h ~= nil and s.mode == "aim" and h.step == step and h.phase == phase
end

local B = function(btn) return { hold = { "b" }, press = { btn } } end
local seen = {}

st.scenarios.howto = st.throwScenario {
	startPos = 120,     -- the crank at 4 o'clock: step 1 asks for 6
	setup = function(s) throw.showHowTo(s) end,
	script = { { n = 2 } },
	maxFrames = 5000,
	shots = {
		-- 1 the crank
		function(s, f)
			if f < 3 or not at(s, 1, "do") then return false end
			feed(s, { { crank = 3, n = 20 }, { n = 3 } })
			return true
		end,
		function(s)
			if not at(s, 1, "after") then return false end
			feed(s, { { press = { "a" } }, { n = 3 } })
			return true
		end,
		-- 2 point and throw
		function(s)
			if not at(s, 2, "do") then return false end
			seen.target = s.markerOn and s.markerOn.id
			feed(s, tw.selftest.planned(s, 0, 0, 10))
			return true
		end,
		function(s)
			if not at(s, 2, "after") then return false end
			seen.verdict = tw.howto.verdictLine(s.howto)
			feed(s, { { press = { "a" } }, { n = 3 } })
			return true
		end,
		-- 3 power: the plan's clean throw is ON
		function(s)
			if not at(s, 3, "do") then return false end
			feed(s, tw.selftest.planned(s, 0, 0, 10))
			return true
		end,
		function(s)
			if not at(s, 3, "after") then return false end
			seen.powerOn = s.howto.on
			feed(s, { { press = { "a" } }, { n = 3 } })
			return true
		end,
		-- 4 the arc
		function(s)
			if not at(s, 4, "do") then return false end
			feed(s, tw.selftest.planned(s, 0, 0, 10))
			return true
		end,
		function(s)
			if not at(s, 4, "after") then return false end
			seen.arcOn = s.howto.on
			feed(s, { { press = { "a" } }, { n = 3 } })
			return true
		end,
		-- 5 the d-pad moves the circle
		function(s)
			if not at(s, 5, "do") then return false end
			seen.mx = s.markerX
			feed(s, { { n = 20, hold = { "left" } }, { n = 3 } })
			return true
		end,
		function(s)
			if not at(s, 5, "after") then return false end
			seen.moved = seen.mx - s.markerX
			feed(s, { { press = { "a" } }, { n = 3 } })
			return true
		end,
		-- 6 A walks
		function(s)
			if not at(s, 6, "do") then return false end
			seen.px = s.playerX
			feed(s, { { n = 30, hold = { "a", "right" } }, { n = 3 } })
			return true
		end,
		function(s)
			if not at(s, 6, "after") then return false end
			seen.walked = s.playerX - seen.px
			feed(s, { { press = { "a" } }, { n = 3 } })
			return true
		end,
		-- 7 B plans: the arc up a step and a tilt, B held (the camera out)
		function(s)
			if not at(s, 7, "do") then return false end
			if not seen.fed7 then
				seen.fed7, seen.rel = true, s.release
				feed(s, { { n = 25, hold = { "b" } }, B("up"), { n = 2, hold = { "b" } }, B("right"),
					{ n = 40, hold = { "b" } }, { n = 30 } })
			end
			return s.camMix >= 1
		end,
		function(s)
			if not at(s, 7, "after") or s.input:held("b") or s.camMix > 0 then return false end
			seen.relNow, seen.tilt = s.release, s.tilt
			feed(s, { { press = { "a" } }, { n = 3 } })
			return true
		end,
		-- 8 the last step; A ends it
		function(s)
			if not at(s, 8, "do") then return false end
			feed(s, { { press = { "a" } }, { n = 3 } })
			return true
		end,
		-- ended: the pitch with no panel; then a second run, skipped through
		-- with taps of B
		function(s)
			if s.howto then return false end
			seen.closed = true
			throw.showHowTo(s)
			seen.again = true
			local list = {}
			for _ = 1, #tw.howto.STEPS do
				list[#list + 1] = { press = { "b" } }
				list[#list + 1] = { n = 3 }
			end
			list[#list + 1] = { n = 3 }
			feed(s, list)
			return true
		end,
		function(s) return seen.again and s.howto == nil and s.input:finished() end,
	},
	check = function(s)
		local rh, t = tw.render.howto, tw.render.howto.tune
		if rh.widest() > 400 - 2 * t.pad then return "a line is " .. rh.widest() .. " px: wider than the panel" end
		local big, label = tw.render.ui.display(16), tw.render.ui.label()
		for _, step in ipairs(tw.howto.STEPS) do
			local w = big:getTextWidth(step.title) + label:getTextWidth("TAP B: SKIP") + 3 * t.pad
			if w > 400 then return "the title " .. step.title .. " runs into the footer" end
		end
		if seen.target ~= "b3" then return "point and throw did not start on b3: " .. tostring(seen.target) end
		if not (seen.verdict and seen.verdict:find("^THAT ONE: ON  ON")) then
			return "the first throw's verdicts: " .. tostring(seen.verdict)
		end
		if not seen.powerOn then return "the power step's clean throw was not ON" end
		if not seen.arcOn then return "the arc step's clean throw was not ON" end
		if not (seen.moved and seen.moved >= tw.howto.tune.circleMove) then return "the circle moved " .. tostring(seen.moved) end
		if not (seen.walked and seen.walked >= tw.howto.tune.walkMove) then return "walked " .. tostring(seen.walked) end
		if seen.relNow ~= seen.rel + tw.plan.tune.arcStepDeg or seen.tilt ~= tw.plan.tune.tiltStepDeg then
			return "the plan step: release " .. tostring(seen.relNow) .. " tilt " .. tostring(seen.tilt)
		end
		if not seen.closed then return "A on the last step did not end it" end
		if s.howto then return "the taps of B did not skip through it" end
		if s.throws ~= 3 then return "throws " .. s.throws end
		return nil, seen.verdict
	end,
}
