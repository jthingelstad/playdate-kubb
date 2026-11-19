-- Scenario "crank-nudge": the nudge (device/crank, scenes/throw's tune
-- nudge*). The crank turned forward from 6 o'clock to 3 and back, three
-- times, never wound back: after the third the hint over the prompt says the
-- crank can be flipped and where. A wind-up hides it, the throw clears it.
-- Frames: 1 the hint (the practice pitch's words), 2 the wind-up (gone), 3
-- aiming again after the throw (gone, the count cleared).
import "selftest/_throw"

local st = tw.selftest
local throw = tw.scenes.throw
local f = tw.swing.tune.forwardSign
local seen = {}

st.scenarios["crank-nudge"] = st.throwScenario {
	setup = function(s) throw.setMenuName(s, "PITCH") end,
	script = function(s)
		local steps = { { n = 3 } }
		for _ = 1, 3 do
			steps[#steps + 1] = { crank = f * 3, n = 30 }    -- forward to 3 o'clock (150 deg/s)
			steps[#steps + 1] = { crank = -f * 3, n = 30 }   -- and back down to 6
			steps[#steps + 1] = { n = 5 }
		end
		for _, x in ipairs(st.planned(s)) do steps[#steps + 1] = x end
		return steps
	end,
	shots = {
		function(s, fr)
			if s.hintText and not seen.at then seen.at, seen.n = fr, s.nudge.n end
			if seen.at and fr == seen.at + 20 then
				seen.text = s.hintText
				return true
			end
		end,
		function(s)
			if s.swing.phase == "winding" and s.swing.back > 60 then
				seen.windHint = s.hintText
				return true
			end
		end,
		function(s) return s.mode == "aim" and s.throws == 1 end,
	},
	maxFrames = 700,
	check = function(s)
		-- the third forward turn (frames 4 to 33, 69 to 98, 134 to 163) reaches 60 at about frame 154
		if not seen.at or seen.at < 140 then return "the hint showed at frame " .. tostring(seen.at) end
		if seen.n ~= 3 then return "the hint showed after " .. tostring(seen.n) .. " turns" end
		if seen.text ~= "CRANK BACKWARD? MENU, PITCH: FLIP CRANK" then return "the hint said " .. tostring(seen.text) end
		if seen.windHint then return "the hint stayed during the wind-up" end
		if s.hintText or s.nudge.n ~= 0 then return "after the throw: hint " .. tostring(s.hintText) .. ", count " .. s.nudge.n end
		-- the longest wording (a match's) fits beside the clock, over the prompt
		local w = tw.render.hud.labelFont():getTextWidth("CRANK BACKWARD? MENU, MATCH: FLIP CRANK") + 10
		local h = tw.render.hud.tune.hint
		if h.right - 2 - w < 4 then return "the hint is " .. w .. " px: off the screen" end
		if h.y + h.h + 2 > tw.render.hud.tune.prompt.y then return "the hint overlaps the prompt" end
		return nil, string.format("at=%d w=%d", seen.at, w)
	end,
}
