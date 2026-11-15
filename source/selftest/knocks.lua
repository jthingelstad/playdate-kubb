-- Scenario "knocks": the recorded knocks (sound.lua). The hit throw (b3
-- knocked over) with the sound on at volume 0: every knock take loads, and
-- one knock plays for each piece struck (wood on wood), as the picture reaches it
-- (none before the first hit). Frame: just after the hit.
import "selftest/_throw"

local st = tw.selftest
local sound = tw.sound
local before, struck, played = nil, nil, nil

st.scenarios.knocks = st.throwScenario {
	setup = function(s)
		sound.on, sound.tune.knockVol, sound.played = true, 0, 0
	end,
	script = function(s) return st.planned(s) end,
	shots = {
		function(s)
			local d = st.sinceHit(s)
			if d and d < 0 and d > -0.1 then before = sound.played end
			if d and d >= 0.05 then return true end
		end,
		function(s)
			if s.mode ~= "rest" or not s.pb or not s.pb.done then return false end
			local w = s.pb.w
			struck = 0
			for i = 1, w.n do
				local b = w.bodies[i]
				if b.touchT and b ~= w.projectile then struck = struck + 1 end
			end
			played = sound.played
			return true
		end,
	},
	maxFrames = 400,
	check = function(s)
		sound.on = false
		local n = sound.loaded()
		if n ~= sound.tune.knocks then return "knock takes loaded: " .. n end
		if before ~= 0 then return "knocks before the hit: " .. tostring(before) end
		if not struck or struck < 1 then return "nothing struck" end
		if played ~= struck then return string.format("%d knocks for %d struck", played, struck) end
	end,
}
