-- Scenario "swing-tempo": see selftest/_tempo.lua.
import "selftest/_tempo"

local st = tw.selftest
local swing = tw.swing

st.scenarios["swing-tempo"] = st.tempoScenario(17, "ON TEMPO", function(s, l)
	if math.abs(l.launchSpeed - swing.tune.launchMax) > 0.1 then
		return string.format("launch %.2f m/s, wanted about %.2f", l.launchSpeed, swing.tune.launchMax)
	end
end)
