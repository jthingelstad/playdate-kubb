-- Scenario "skid-sand": the skid throw on sand. The baton all but plugs
-- where it lands: the check wants less than 0.9 m from the first touch to
-- the rest point (grass: 0.4 to 2.5). (0.4 until 2026-11-16: this throw
-- kicks 0.5 m on sand on the median ground, from 0.3 to 0.8 m over 40
-- grounds, and the throw's own ground decided the check.) Frames as in skid.
import "selftest/skid"

local st = tw.selftest

st.scenarios["skid-sand"] = st.skidScenario("sand", -0.4, 0.9)
