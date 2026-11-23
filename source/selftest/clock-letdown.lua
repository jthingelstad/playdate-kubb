-- Scenario "clock-letdown": stopping before 6 throws nothing (DESIGN 4
-- "What goes wrong"). A wind-up to 10 o'clock, a fast flick that stops at 8
-- o'clock (short of the bottom: let down; the crank parked behind the
-- bottom must come down through 6 first: CRANK DOWN), then the crank brought
-- forward past 6, wound again and let down slowly through 6. Frames: 1 wound
-- to 10 (the hand and the peak dot), 2 after the first let-down (CRANK
-- DOWN, no throw), 3 after the second (WIND BACK).
import "selftest/_throw"

local st = tw.selftest
local f = tw.swing.tune.forwardSign

st.scenarios["clock-letdown"] = st.throwScenario {
	script = {
		{ n = 3 },
		st.windup(120, 20),                 -- frames 4 to 23
		{ n = 3 },
		st.flick { 20, 20, 20 },            -- fast, to 8 o'clock (-60), and stops
		{ n = 20 },
		{ crank = f * 7, n = 10 },          -- forward past the bottom (to 10 degrees ahead)
		st.windup(90, 15),
		{ n = 3 },
		{ crank = f * 2, n = 50 },          -- slowly forward: 100 deg/s, through the bottom
		{ n = 10 },
	},
	shots = {
		function(s, fr) return fr == 24 end,
		function(s, fr)
			if fr == 40 then
				if s.promptText ~= "CRANK DOWN" then error("parked behind: " .. tostring(s.promptText)) end
				if s.throws ~= 0 then error("the flick stopped at 8 threw") end
				return true
			end
		end,
		function(s, fr) return s.input:finished() end,
	},
	maxFrames = 200,
	check = function(s)
		if s.throws ~= 0 then return "throws " .. s.throws end
		if s.mode ~= "aim" or s.swing.phase ~= "idle" then return "mode " .. s.mode .. ", " .. s.swing.phase end
		if s.promptText ~= "WIND BACK" then return "prompt " .. tostring(s.promptText) end
	end,
}
