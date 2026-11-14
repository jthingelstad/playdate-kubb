-- Scenario "howto": HOW TO THROW, the walkthrough (core/howto, render/howto),
-- over the practice pitch as the System Menu's "how to" opens it, driven by
-- the crank alone. Frames: 1 step 1 before the crank turns, 2 wound back to
-- full power (step 2), 3 a throw stopped on the notch (the side view, the
-- stop's dot, ON THE NOTCH; step 3), 4 the notch moved with A held (done),
-- 5 the pitch again after A: nothing was thrown on it underneath.
import "selftest/_throw"

local st = tw.selftest
local f = tw.swing.tune.forwardSign

local seen = {}

st.scenarios.howto = st.throwScenario {
	setup = function(s)
		s.loftDeg = 30
		tw.scenes.throw.showHowTo(s)
	end,
	script = {
		{ n = 3 },
		st.windup(130, 13),
		{ n = 3 },
		st.flick { 6, 12, 18, 22, 24, 24, 24, 20, 10 },
		{ n = 8 },
		{ hold = { "a" }, crank = f * 10, n = 8 },
		{ n = 3 },
		{ press = { "a" } },
		{ n = 4 },
	},
	shots = {
		function(s, fr) return fr == 2 end,
		function(s) local h = s.howto; return h and h.step == "throw" and h.sw.phase == "winding" end,
		function(s)
			local h = s.howto
			if h and h.last and h.step == "notch" then seen.last = h.last; return true end
		end,
		function(s)
			local h = s.howto
			if h and h.step == "done" then seen.loft = h.loft; return true end
		end,
		-- A has ended it: the practice pitch again
		function(s) return seen.loft and not s.howto end,
	},
	check = function(s)
		if s.howto then return "the walkthrough is still up" end
		if not seen.last then return "no throw on the notch" end
		if seen.last.miss ~= 0 then return "the throw missed the notch: " .. seen.last.angle end
		if not seen.loft or seen.loft < 39 then return "the notch did not move: " .. tostring(seen.loft) end
		if s.throws ~= 0 then return "a throw on the pitch under the walkthrough" end
		if s.swing.phase ~= "idle" then return "the scene's swing is " .. s.swing.phase end
		return nil, string.format(" carry=%.1f", seen.last.carry)
	end,
}
