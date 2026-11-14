-- Scenarios "drill-stop" and "drill-early": a drilled kubb thrown as a baton
-- is (Jamie, 2026-11-14: "the player should only need to learn how the crank
-- works for throwing once"). The practice pitch drilling at the starting
-- marker, with the release where the crank stops: wound back into the band
-- and a hard flick, stopped on the drill's notch (the loft that reaches the
-- marker) or 40 degrees before it. On the notch the verdict is ON THE NOTCH,
-- the kubb leaves at that loft and rests near the marker; early it is EARLY:
-- LOW and leaves lower. Either way the flight the camera follows is the one
-- thrown (Codex on #85). Frames: 1 aiming (the band and the notch on the
-- dial), 2 at rest, 3 aiming again (the stop's dot and the verdict).
import "selftest/_throw"
import "core/drill"

local st = tw.selftest
local drill, flight = tw.drill, tw.flight

local mx, my = 0, drill.tune.markerStartY
local sol = drill.solve(mx, my, 0)
local WIND = sol.band * tw.swing.tune.fullBackswingDeg

local function scenario(short, verdict, check)
	-- forward from the wind-up to the stop: WIND back to the bottom, then the
	-- loft, less `short`
	local steps, left = {}, WIND + sol.loft - short
	while left > 0 do
		local d = math.min(20, left)
		steps[#steps + 1] = d
		left = left - d
	end
	return st.throwScenario {
		stopRelease = true,
		setup = function(s) tw.scenes.throw.setDrill(s, true) end,
		script = {
			{ n = 3 },
			st.windup(WIND, 25),
			{ n = 3 },
			st.flick(steps),
			{ n = 300 },
		},
		shots = {
			function(s, f) return f == 2 end,
			st.restShot(30),
			function(s) return s.mode == "aim" and s.throws == 1 end,
		},
		maxFrames = 500,
		check = function(s)
			local l = s.last
			if not l or not l.drill then return "the throw was not a drill" end
			if s.stopText ~= verdict then return "verdict " .. tostring(s.stopText) end
			-- the flight the camera follows is the one thrown
			local L = s.drillLaunch
			local _, py = flight.predict(s.playerX, s.playerY, L.swivel, L.loft, L.speed)
			if math.abs(s.flight.ly - py) > 1e-6 then
				return string.format("the camera's flight lands at %.2f, the throw's at %.2f", s.flight.ly, py)
			end
			local d = math.sqrt((l.restX - mx) ^ 2 + (l.restY - my) ^ 2)
			local err = check(s, d)
			if err then return err end
			return nil, string.format(" loft=%.1f rest_m=%.2f", s.loftDeg, d)
		end,
	}
end

st.scenarios["drill-stop"] = scenario(0, "ON THE NOTCH", function(s, d)
	if math.abs(s.loftDeg - sol.loft) > 0.5 then
		return string.format("left at %.1f, the notch is %.1f", s.loftDeg, sol.loft)
	end
	if d > 0.6 then return string.format("rested %.2f m from the marker", d) end
end)

st.scenarios["drill-early"] = scenario(40, "EARLY: LOW", function(s, d)
	if s.loftDeg > sol.loft - 5 then
		return string.format("left at %.1f, the notch is %.1f: not lower", s.loftDeg, sol.loft)
	end
end)
