-- Scenario "burst": the hit throw of "hit" (b3 knocked over); frames at the
-- burst's flash, its TOK! and its break-up (render/burst, the board's
-- HitFX), then aiming again. The check: the burst was a clean one, and it is
-- cleared (and the screen not inverted) for the next throw, and it started
-- within one shown frame of the baton's impact.
import "selftest/_throw"

local st = tw.selftest
local t = tw.render.burst.tune
local seen = nil   -- the burst's kind while it played
local startGap = nil   -- shown seconds from the impact to the burst's first frame
local function at(lo, hi)
	return function(s)
		local B = s.burst
		if B.kind and not seen and s.pb and s.pb.w.firstHit then startGap = s.showTime - s.pb.w.firstHit.t end
		if B.kind then seen = B.kind end
		return B.kind ~= nil and not B.done and B.age >= lo and B.age < hi
	end
end

st.scenarios.burst = st.throwScenario {
	setup = function(s) s.loftDeg = 30 end,
	script = {
		{ n = 5 },
		st.windup(120, 30),
		{ n = 5 },
		st.flick { 6, 12, 18, 22, 24, 24, 24 },
		{ n = 300 },
	},
	shots = {
		at(0, t.flash),
		at(t.flash + 0.1, t.flash + t.burst),
		at(t.flash + t.burst, t.flash + t.burst + t.breakup),
		st.restShot(70),   -- aiming again: the burst is cleared
	},
	maxFrames = 400,
	check = function(s)
		local B = s.burst
		if seen ~= "clean" then return "burst kind " .. tostring(seen) end
		if B.kind ~= nil or B.inverted then return "burst not cleared for the next throw" end
		if s.mode ~= "aim" then return "mode " .. s.mode end
		-- the burst starts at the impact: within one shown frame of it (at
		-- the slow motion's 0.3, a 20 ms frame shows 6 ms)
		if not startGap or startGap < 0 or startGap > 0.02 then
			return "burst started " .. tostring(startGap) .. " s after the impact"
		end
		return nil, string.format("gap=%.4f", startGap)
	end,
}
