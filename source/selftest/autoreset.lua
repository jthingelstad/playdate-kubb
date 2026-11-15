-- Scenario "autoreset": only b3 counts as a far base kubb here, so the hit
-- throw that knocks it over leaves every far base kubb down, and when the
-- rest hold ends the scene stands everything back up by itself. Frames:
-- 1 at rest with b3 down, 2 aiming again with b3 standing.
import "selftest/_throw"

local st = tw.selftest
local throw = tw.scenes.throw

st.scenarios.autoreset = st.throwScenario {
	setup = function(s)
		local l = throw.defaultLayout()
		for _, p in ipairs(l) do p.base = (p.id == "b3") end
		throw.setLayout(s, l)
	end,
	script = function(s) return st.planned(s) end,
	shots = {
		st.restShot(30),
		st.restShot(70),
	},
	maxFrames = 400,
	check = function(s)
		local r = s.result
		if not r or r.toppled[1] ~= "b3" then return "b3 was not toppled" end
		if s.mode ~= "aim" then return "mode " .. s.mode end
		local b3 = st.item(s, "b3")
		if b3.toppled or math.abs(b3.x) > 1e-6 or math.abs(b3.y - 8) > 1e-6 then return "b3 not stood back up" end
	end,
}
