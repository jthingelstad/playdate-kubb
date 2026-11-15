-- Scenario "low-hard": the low, flat throw (Jamie, 2026-11-14: a field kubb
-- near the baseline is hit low and hard, to roll it into others; DESIGN 4:
-- "stop at 5"). Three field kubbs at about 6.5 to 7.2 m, 1.2 m right of the
-- middle; the circle on f1 (the stance behind it, clear of the king) and the
-- arc planned down with B to half past 5 (the plan's lowest release): the
-- plan's clean throw at that arc leaves low and fast and must take a field
-- kubb down. Frames: 1 aiming (the low arc), 2 the hit, 3 at rest.
import "selftest/_throw"

local st = tw.selftest
local throw = tw.scenes.throw

st.scenarios["low-hard"] = st.throwScenario {
	setup = function(s)
		local l = throw.defaultLayout()
		l[#l + 1] = { id = "f1", kind = "kubb", x = 1.20, y = 6.50, yaw = 0 }
		l[#l + 1] = { id = "f2", kind = "kubb", x = 1.45, y = 7.00, yaw = 0.3 }
		l[#l + 1] = { id = "f3", kind = "kubb", x = 1.00, y = 7.25, yaw = -0.2 }
		throw.setLayout(s, l)
		throw.aimAt(s, 1.2, 6.5)
		throw.setArc(s, tw.plan.tune.releaseMinDeg)
	end,
	script = function(s) return st.planned(s) end,
	shots = {
		function(s, f) return f == 3 end,
		function(s) local d = st.sinceHit(s); return d and d >= 0.05 end,
		st.restShot(30),
	},
	maxFrames = 400,
	check = function(s)
		local r, l = s.result, s.last
		if not r or not l then return "no result" end
		if l.launchLoft > 10 then return string.format("left at %.1f degrees: not low", l.launchLoft) end
		local down = 0
		for _, id in ipairs(r.toppled) do
			if id:sub(1, 1) == "f" then down = down + 1 end
		end
		if down < 1 then return "no field kubb down: " .. table.concat(r.toppled, ",") end
		return nil, string.format(" loft=%.1f launch=%.1f down=%d", l.launchLoft, l.launchSpeed, down)
	end,
}
