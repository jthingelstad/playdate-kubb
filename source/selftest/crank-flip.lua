-- Scenario "crank-flip": the crank flipped (throw.flipCrank, what the System
-- Menu's "flip crank" calls; device/crank). Today's swing (wound up the left,
-- flicked up the right) throws nothing on a flipped crank: its wind-up turns
-- the arm forward from the bottom (nothing starts) and its flick turns it back
-- through the bottom (a wind-up), and bringing it forward slowly lets that
-- down. Then the plan's clean swing turned the flipped way throws and takes a
-- base kubb down. Nothing is saved: a self-test run never writes the setting
-- (main.lua). Frames: 1 CRANK FLIPPED in the prompt flag, 2 today's flick
-- read as a wind-up, 3 the flipped throw in flight, 4 at rest.
import "selftest/_throw"

local st = tw.selftest
local throw = tw.scenes.throw
local seen = {}

st.scenarios["crank-flip"] = st.throwScenario {
	setup = function(s) throw.flipCrank(s) end,
	script = function(s)
		local flipped = tw.swing.tune.forwardSign
		-- today's swing: built with today's sign
		tw.swing.tune.forwardSign = -flipped
		local steps = tw.input.swingSteps(s.sol.back, s.sol.release)
		tw.swing.tune.forwardSign = flipped
		steps[#steps + 1] = { n = 20 }
		-- forward slowly (100 deg/s, flipped) from where it stopped, past the bottom
		steps[#steps + 1] = { crank = flipped * 2, n = math.ceil(s.sol.release / 2) + 5 }
		steps[#steps + 1] = { n = 20 }
		for _, x in ipairs(st.planned(s)) do steps[#steps + 1] = x end
		return steps
	end,
	shots = {
		function(s, f)
			if f ~= 3 then return false end
			seen.note = s.promptText
			return true
		end,
		function(s)
			local sw = s.swing
			if s.throws == 0 and sw.phase == "winding" and sw.arm < -60 then
				seen.wound = true
				return true
			end
			if seen.wound and sw.phase == "idle" and s.mode == "aim" then seen.letdown = true end
		end,
		function(s)
			if s.swing.phase == "idle" and s.mode == "aim" and s.throws == 0 then seen.letdown = true end
			if s.mode == "flight" and s.showTime > 0.35 then
				seen.throwsAtFlight = s.throws
				return true
			end
		end,
		st.restShot(30),
	},
	maxFrames = 700,
	check = function(s)
		if not tw.crank.flipped or tw.swing.tune.forwardSign ~= -tw.crank.defaultSign then
			return "the crank is not flipped: sign " .. tw.swing.tune.forwardSign
		end
		if seen.note ~= "CRANK FLIPPED" then return "after the flip the prompt was " .. tostring(seen.note) end
		if not seen.letdown then return "today's swing was never let down" end
		if seen.throwsAtFlight ~= 1 or s.throws ~= 1 then
			return "throws " .. tostring(seen.throwsAtFlight) .. " then " .. s.throws .. ": today's swing threw"
		end
		local r = s.result
		local down = 0
		for _, id in ipairs(r and r.toppled or {}) do if id:match("^b%d$") then down = down + 1 end end
		if down < 1 then return "the flipped throw took no base kubb down" end
		if s.vPower ~= 0 or s.vRelease ~= 0 then
			return string.format("verdicts %s %s", tostring(s.vPower), tostring(s.vRelease))
		end
		return nil, string.format("sign=%d down=%d", tw.swing.tune.forwardSign, down)
	end,
}
