-- Scenario "loft": d-pad down to the lowest loft (frame 1), then up to the
-- highest (frame 2). The HUD dial and the minimap aim line change.
import "selftest/_throw"

local script = { { n = 2 } }
for _ = 1, 6 do
	script[#script + 1] = { press = { "down" } }
	script[#script + 1] = { n = 1 }
end
local afterDown = 2 + 12
for _ = 1, 10 do
	script[#script + 1] = { press = { "up" } }
	script[#script + 1] = { n = 1 }
end
script[#script + 1] = { n = 3 }

local lft = tw.flight.tune
tw.selftest.scenarios.loft = tw.selftest.throwScenario {
	script = script,
	shots = {
		function(s, f) return f == afterDown end,
		function(s, f) return f == afterDown + 21 end,
	},
	check = function(s)
		if s.loftDeg ~= lft.loftMaxDeg then return "loft " .. s.loftDeg end
	end,
}
