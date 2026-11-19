-- Scenario "crank-flip-mid": the crank flipped in the middle of a wind-up
-- (throw.flipCrank, the System Menu's "flip crank"). The wind-up is dropped,
-- not thrown: the swing goes back to idle unarmed, and the flick that follows
-- (today's forward, the flipped crank's back) only starts a new wind-up.
-- Frames: 1 wound to 10 o'clock, flipped on this frame, 2 just after (idle,
-- CRANK FLIPPED), 3 after the flick (a wind-up, no throw).
import "selftest/_throw"

local st = tw.selftest
local throw = tw.scenes.throw
local seen = {}

st.scenarios["crank-flip-mid"] = st.throwScenario {
	-- built at load, with today's sign
	script = { { n = 3 }, st.windup(120, 20), { n = 10 },
		st.flick { 8, 16, 24, 24, 24, 24, 24, 24, 24, 24 }, { n = 40 } },
	shots = {
		function(s)
			local sw = s.swing
			if sw.phase == "winding" and sw.back >= 115 and not seen.flipped then
				throw.flipCrank(s)
				seen.flipped = true
				seen.phase = s.swing.phase
				return true
			end
		end,
		function(s, f)
			seen.at = seen.at or f
			if f < seen.at + 2 then return false end
			seen.note, seen.phase2 = s.promptText, s.swing.phase
			return true
		end,
		function(s) return s.input:finished() end,
	},
	maxFrames = 300,
	check = function(s)
		if seen.phase ~= "idle" or seen.phase2 ~= "idle" then
			return "after the flip the swing was " .. tostring(seen.phase) .. ", " .. tostring(seen.phase2)
		end
		if seen.note ~= "CRANK FLIPPED" then return "after the flip the prompt was " .. tostring(seen.note) end
		if s.throws ~= 0 or s.mode ~= "aim" then return "the flip threw: throws " .. s.throws .. ", " .. s.mode end
		if s.swing.phase ~= "winding" then return "the flick after the flip is " .. s.swing.phase .. ", not a wind-up" end
		return nil, "after=" .. s.swing.phase
	end,
}
