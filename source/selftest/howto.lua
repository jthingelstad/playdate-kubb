-- Scenario "howto": the HOW TO THROW card (Jamie, 2026-11-14: "maybe we need
-- a 'how to' that shows people how the throw works"). Shown over the practice
-- pitch as the System Menu's "how to" does (frame 1); the crank turned under
-- it does nothing; A puts it away and the pitch is back (frame 2), nothing
-- thrown.
import "selftest/_throw"

local st = tw.selftest
local f = tw.swing.tune.forwardSign

st.scenarios.howto = st.throwScenario {
	setup = function(s) tw.scenes.throw.showHowTo(s) end,
	script = {
		{ n = 3 },
		{ crank = -f * 10, n = 12 },     -- a wind-up under the card: ignored
		{ n = 3 },
		{ press = { "a" } },
		{ n = 5 },
	},
	shots = {
		function(s, f) return f == 2 end,
		function(s, f) return f == 22 end,
	},
	check = function(s)
		if s.howto then return "the card is still up" end
		if s.throws ~= 0 then return "a throw under the card" end
		if s.swing.phase ~= "idle" then return "the crank wound up under the card: " .. s.swing.phase end
	end,
}
