-- Scenario "drill-stop": a drilled kubb thrown as a baton is (Jamie,
-- 2026-11-14: "the player should only need to learn how the crank works for
-- throwing once"). The practice pitch drilling at the starting marker, with
-- the release where the crank stops: wound back into the band, a hard flick
-- stopped on the drill's notch (the loft that reaches the marker). The verdict
-- is ON THE NOTCH, the kubb leaves at that loft and rests near the marker.
-- Frames: 1 aiming (the band and the notch on the dial), 2 at rest, 3 aiming
-- again (the stop's dot and the verdict).
import "selftest/_throw"
import "core/drill"

local st = tw.selftest
local drill = tw.drill

local mx, my = 0, drill.tune.markerStartY
local sol = drill.solve(mx, my, 0)
local WIND = sol.band * tw.swing.tune.fullBackswingDeg

-- forward from the wind-up to the notch: WIND back to the bottom, then the loft
local steps, left = {}, WIND + sol.loft
while left > 0 do
	local d = math.min(20, left)
	steps[#steps + 1] = d
	left = left - d
end

st.scenarios["drill-stop"] = st.throwScenario {
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
		if s.stopText ~= "ON THE NOTCH" then return "verdict " .. tostring(s.stopText) end
		if math.abs(s.loftDeg - sol.loft) > 0.5 then
			return string.format("left at %.1f, the notch is %.1f", s.loftDeg, sol.loft)
		end
		local d = math.sqrt((l.restX - mx) ^ 2 + (l.restY - my) ^ 2)
		if d > 0.6 then return string.format("rested %.2f m from the marker", d) end
		return nil, string.format(" loft=%.1f rest_m=%.2f", s.loftDeg, d)
	end,
}
