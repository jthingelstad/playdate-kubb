-- Scenario "skid": a medium throw lands short, near the centerline past the
-- king, on grass, and kicks on along the lawn. Frames: 1 the landing,
-- 2 0.3 s later, 3 at rest. The check wants a kick of 0.4 to 2.5 m from the
-- first touch to the rest point (skid-sand wants much less).
import "selftest/_throw"

local st = tw.selftest

function st.skidScenario(surface, minKick, maxKick)
	return st.throwScenario {
		setup = function(s) s.surface = surface end,
		script = {
			{ n = 2 },
			st.windup(120, 30),
			{ n = 5 },
			st.flick { 5, 10, 14, 18, 20, 20, 20 },
			{ n = 300 },
		},
		shots = {
			function(s) local d = st.sinceContact(s); return d and d >= 0 end,
			function(s) local d = st.sinceContact(s); return d and d >= 0.3 end,
			st.restShot(30),
		},
		maxFrames = 400,
		check = function(s)
			local r = s.result
			if not r then return "no result" end
			local fc = r.firstContact
			if not fc or fc.with ~= "ground" then return "first contact " .. tostring(fc and fc.with) end
			if fc.y < 3.5 or fc.y > 6 then return string.format("landed at %.2f", fc.y) end
			local b = r.bodies.baton
			local kick = b.y - fc.y
			s.kick = kick
			if kick < minKick or kick > maxKick then
				return string.format("%s kick %.2f m, want %.1f to %.1f", surface, kick, minKick, maxKick)
			end
		end,
	}
end

st.scenarios.skid = st.skidScenario("grass", 0.4, 2.5)
