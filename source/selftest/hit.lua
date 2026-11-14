-- Scenario "hit": a strong clean throw from the center of the baseline at
-- 30 degrees of loft (set by setup) lands on the middle far base kubb b3
-- and knocks it over. Frames: 1 about 0.2 s before the hit, 2 the hit, 3 b3
-- falling, 4 at rest with the readout, 5 aiming again with b3 still down.
-- Frames 2 and 3 are in the slow motion: the HUD's SLOW MOTION flag shows.
-- The check also stands everything back up with throw.reset.
import "selftest/_throw"

local st = tw.selftest
local slowSeen = nil   -- s.slowMo 0.1 s after the hit

st.scenarios.hit = st.throwScenario {
	setup = function(s) s.loftDeg = 30 end,
	script = {
		{ n = 5 },
		st.windup(120, 30),
		{ n = 5 },
		st.flick { 6, 12, 18, 22, 24, 24, 24 },
		{ n = 300 },
	},
	shots = {
		function(s) local d = st.sinceHit(s); return d and d >= -0.2 end,
		function(s) local d = st.sinceHit(s); return d and d >= 0 end,
		function(s)
			local d = st.sinceHit(s)
			if d and d >= 0.1 then slowSeen = s.slowMo; return true end
		end,
		st.restShot(30),
		st.restShot(70),
	},
	maxFrames = 400,
	check = function(s)
		local r = s.result
		if not r then return "no result" end
		if not r.firstHit or r.firstHit.with ~= "b3" then
			return "first hit " .. tostring(r.firstHit and r.firstHit.with)
		end
		if #r.toppled ~= 1 or r.toppled[1] ~= "b3" then return "toppled " .. table.concat(r.toppled, ",") end
		if s.mode ~= "aim" then return "mode " .. s.mode end
		if not slowSeen then return "no slow motion flag 0.1 s after the hit" end
		if not st.item(s, "b3").toppled then return "b3 stood back up" end
		if s.last.down ~= 1 then return "readout down " .. tostring(s.last.down) end
		tw.scenes.throw.reset(s)
		for i = 1, s.nitems do
			local it = s.items[i]
			if it.toppled or math.abs(it.r33 - 1) > 1e-3 then return "reset left " .. it.id .. " down" end
		end
	end,
}
