-- Scenario "swing-fast": see selftest/_tempo.lua.
import "selftest/_tempo"

local st = tw.selftest
local swing = tw.swing

st.scenarios["swing-fast"] = st.tempoScenario(26, "FAST: LONG", function(s, l)
	if l.launchSpeed < swing.tune.launchMax + 0.3 then
		return string.format("launch %.2f m/s: not faster than full power", l.launchSpeed)
	end
end)
