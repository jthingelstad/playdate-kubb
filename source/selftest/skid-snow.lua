-- Scenario "skid-snow": the skid throw on snow. Packed snow is slick but the
-- baton ploughs to a stop: the check wants 0.4 to 4 m from the first touch
-- to the rest point. Frames as in skid, on snow's look (a sparse sprinkle
-- for the rough).
import "selftest/skid"

local st = tw.selftest

st.scenarios["skid-snow"] = st.skidScenario("snow", 0.4, 4.0)
