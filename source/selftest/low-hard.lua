-- Scenario "low-hard": the low, hard throw (Jamie, 2026-11-14: a field kubb
-- near the baseline is hit low and hard, to roll it into others). Three field
-- kubbs at about 6.5 to 7.2 m, 1.2 m right of the middle (thrown from in
-- line with them, clear of the king); the loft at the floor (5 degrees, set by
-- setup) and a strong flick, thrown as in play (flight.loftBoost on): the
-- baton must leave faster than the swing's full speed, land short and skid
-- into the group. Frames: 1 aiming at 5 degrees, 2 the hit, 3 at rest.
import "selftest/_throw"

local st = tw.selftest
local throw = tw.scenes.throw

st.scenarios["low-hard"] = st.throwScenario {
	loftBoost = true,
	setup = function(s)
		local l = throw.defaultLayout()
		l[#l + 1] = { id = "f1", kind = "kubb", x = 1.20, y = 6.50, yaw = 0 }
		l[#l + 1] = { id = "f2", kind = "kubb", x = 1.45, y = 7.00, yaw = 0.3 }
		l[#l + 1] = { id = "f3", kind = "kubb", x = 1.00, y = 7.25, yaw = -0.2 }
		throw.setLayout(s, l)
		-- in line with them, clear of the king in the middle
		s.playerX = 1.2
		s.loftDeg = tw.flight.tune.loftMinDeg
	end,
	script = {
		{ n = 5 },
		st.windup(120, 30),
		{ n = 5 },
		st.flick { 5, 10, 14, 17, 18, 18, 18 },
		{ n = 300 },
	},
	shots = {
		function(s, f) return f == 3 end,
		function(s) local d = st.sinceHit(s); return d and d >= 0.05 end,
		st.restShot(30),
	},
	maxFrames = 400,
	check = function(s)
		local r, l = s.result, s.last
		if not r or not l then return "no result" end
		if s.loftDeg ~= 5 then return "loft " .. s.loftDeg end
		local full = tw.swing.tune.launchMax
		if not (l.launchSpeed > full) then
			return string.format("launch %.2f m/s, not harder than %.2f", l.launchSpeed, full)
		end
		local down = 0
		for _, id in ipairs(r.toppled) do
			if id:sub(1, 1) == "f" then down = down + 1 end
		end
		if down < 1 then return "no field kubb down: " .. table.concat(r.toppled, ",") end
		return nil, string.format(" launch=%.1f down=%d", l.launchSpeed, down)
	end,
}
