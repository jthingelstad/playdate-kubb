-- Scenario "drill-tilt": a drill with the console rolled 30 degrees right
-- (selftest/_drilltilt).
import "selftest/_drilltilt"

tw.selftest.scenarios["drill-tilt"] = tw.selftest.tiltScenario(30, "CUT RIGHT")
