-- Scenario "skid-sand": the skid throw on sand. The baton plugs where it
-- lands: the check wants less than 0.4 m from the first touch to the rest
-- point. Frames as in skid.
import "selftest/skid"

local st = tw.selftest

st.scenarios["skid-sand"] = st.skidScenario("sand", -0.4, 0.4)
