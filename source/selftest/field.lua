-- Scenario "field": three field kubbs stand in a tight group at about
-- (0, 5.9), past the centerline. The circle on f1, the arc planned to half past
-- 4, and the plan's clean throw from behind it fly over the king into
-- the group. Frames: 1 just
-- before the hit, 2 the hit, 3 the group falling, 4 at rest.
import "selftest/_throw"

local st = tw.selftest
local throw = tw.scenes.throw

st.scenarios.field = st.throwScenario {
	setup = function(s)
		local l = throw.defaultLayout()
		l[#l + 1] = { id = "f1", kind = "kubb", x = 0.00, y = 5.90, yaw = 0.2 }
		l[#l + 1] = { id = "f2", kind = "kubb", x = 0.09, y = 5.96, yaw = 0.5 }
		l[#l + 1] = { id = "f3", kind = "kubb", x = -0.08, y = 5.99, yaw = -0.3 }
		throw.setLayout(s, l)
		-- the circle on f1, the arc a little lower than a field kubb's (about
		-- half past 4: it drives into the group behind). 46, not 45: since the
		-- pair bounce is solved with the footing (2026-11-16) the throw at 45
		-- fells f1 alone, though over 404 desktop throws into this group two or
		-- more fall more often than before (31% -> 42%); 44, 46 and 47 fell two
		-- or more before and after
		throw.aimAt(s, 0, 5.9)
		throw.setArc(s, 46)
	end,
	script = function(s) return st.planned(s) end,
	shots = {
		function(s) local d = st.sinceHit(s); return d and d >= -0.15 end,
		function(s) local d = st.sinceHit(s); return d and d >= 0.02 end,
		function(s) local d = st.sinceHit(s); return d and d >= 0.3 end,
		st.restShot(30),
	},
	maxFrames = 400,
	check = function(s)
		local r = s.result
		if not r then return "no result" end
		if not r.firstHit or r.firstHit.with:sub(1, 1) ~= "f" then
			return "first hit " .. tostring(r.firstHit and r.firstHit.with)
		end
		local down = 0
		for _, id in ipairs(r.toppled) do
			if id:sub(1, 1) == "f" then down = down + 1 end
		end
		if down < 2 then return "field kubbs down " .. table.concat(r.toppled, ",") end
		if r.kingToppled then return "king toppled" end
	end,
}
