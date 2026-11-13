-- Scenario "hud-drill": the HUD through a drilled kubb wound past its band.
-- The marker stays at home; the crank winds back well past the band and
-- flicks, so the kubb goes long. Frames: 1 winding, still short of the band
-- (prompt WIND TO BAND), 2 past it (EASE OFF), 3 at rest with the result
-- callout (LONG, the pointer right of the band, the distance from the marker)
-- and the power chip. The check reads the prompts the scene drew.
import "selftest/_throw"
import "core/drill"

local st = tw.selftest
local drill = tw.drill

local sol = drill.solve(0, drill.tune.markerStartY, 0)
local WIND = (sol.band + 0.25) * tw.swing.tune.fullBackswingDeg
local seen = {}

st.scenarios["hud-drill"] = st.throwScenario {
	setup = function(s) tw.scenes.throw.setDrill(s, true) end,
	script = {
		{ n = 3 },
		st.windup(WIND, 30),
		{ n = 3 },
		st.flick { 6, 12, 18, 22, 24, 24, 24 },
		{ n = 300 },
	},
	shots = {
		function(s, f)
			if f == 3 + 12 then seen[1] = s.promptText; return true end
		end,
		function(s, f)
			if f == 3 + 30 + 2 then seen[2] = s.promptText; return true end
		end,
		st.restShot(30),
	},
	maxFrames = 500,
	check = function(s)
		if seen[1] ~= "WIND TO BAND" then return "short of the band the prompt was " .. tostring(seen[1]) end
		if seen[2] ~= "EASE OFF" then return "past the band the prompt was " .. tostring(seen[2]) end
		local l = s.last
		if not l or not l.drill then return "the throw was not a drill" end
		if l.verdict ~= "long" then return string.format("verdict %s: power %.2f band %.2f", l.verdict, l.power, l.band) end
		if not l.restCm then return "no rest distance for the callout" end
		return nil, string.format("power=%.2f band=%.2f rest_cm=%d", l.power, l.band, l.restCm)
	end,
}
