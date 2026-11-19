-- Scenario "crank-flip-flight": the crank flipped (throw.flipCrank, the System
-- Menu's "crank") while the player's throw is in the air. The throw plays on
-- and its trace is kept: the recorder still holds the swing's samples and the
-- sign they were made with, so the line written at rest replays as thrown.
-- Frames: 1 in flight, flipped on this frame, 2 at rest.
import "selftest/_throw"

local st = tw.selftest
local throw = tw.scenes.throw
local seen = {}

st.scenarios["crank-flip-flight"] = st.throwScenario {
	script = function(s) return st.planned(s) end,
	shots = {
		function(s)
			if s.mode == "flight" and s.showTime > 0.2 then
				seen.sign = tw.swing.tune.forwardSign
				seen.n = tw.recorder.n
				throw.flipCrank(s)
				seen.nAfter, seen.signKept = tw.recorder.n, tw.recorder.sign
				return true
			end
		end,
		st.restShot(30),
	},
	maxFrames = 500,
	check = function(s)
		if not tw.crank.flipped then return "the crank is not flipped" end
		if not seen.n or seen.n == 0 then return "no samples were recorded before the flip" end
		if seen.nAfter ~= seen.n then
			return "the flip dropped the throw's trace: " .. seen.n .. " samples, then " .. tostring(seen.nAfter)
		end
		if seen.signKept ~= seen.sign then
			return "the trace's sign is " .. tostring(seen.signKept) .. ", thrown with " .. tostring(seen.sign)
		end
		if s.throws ~= 1 then return "throws " .. s.throws end
		return nil, string.format("samples=%d sign=%d", seen.n, seen.signKept)
	end,
}
