-- Scenario "drill-tilt-left": a drill with the console rolled 40 degrees
-- left, past the full cut (selftest/_drilltilt).
import "selftest/_drilltilt"

tw.selftest.scenarios["drill-tilt-left"] = tw.selftest.tiltScenario(-40, "CUT LEFT")
