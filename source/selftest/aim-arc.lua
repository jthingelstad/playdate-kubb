-- Scenario "aim-arc": the aim arc lands on screen (Codex on #74: a wind-up's
-- shorter arc once fell under the view, and a low hard throw lands near, under
-- the long lens's lower edge). Mid wind-up (frame 1), then at every loft from
-- the lowest to the highest, from the middle and both ends of the line,
-- turned both ways: the landing ring wholly on screen, the arc under the top
-- margin and inside the sides, and at least its last few points showing (it may
-- rise in from the lower edge).
import "selftest/_throw"

local ft = tw.flight.tune

local function check(s)
	local top = tw.scenes.throw.tune.arcTop
	local ring, arc, on, all, behind = tw.scenes.throw.arcBox(s)
	if not ring then return "no arc" end
	if behind then return "ring behind the camera" end
	if ring[1] < 0 or ring[3] > 400 or ring[2] < 0 or ring[4] > 240 then
		return string.format("ring %.0f,%.0f %.0f,%.0f", ring[1], ring[2], ring[3], ring[4])
	end
	if on < 3 then return "arc " .. on .. "/" .. all .. " on screen" end
	if arc[1] < 0 or arc[3] > 400 or arc[2] < top - 1 then
		return string.format("arc %.0f,%.0f %.0f,%.0f", arc[1], arc[2], arc[3], arc[4])
	end
end

tw.selftest.scenarios["aim-arc"] = tw.selftest.throwScenario {
	script = { { n = 2 }, tw.selftest.windup(40, 20), { n = 4 } },
	shots = { function(s, f) return f == 24 end },
	check = function(s)
		if s.swing.phase ~= "winding" then return "phase " .. s.swing.phase end
		local x0, sw0, l0 = s.playerX, s.swivel, s.loftDeg
		local bad = nil
		for _, px in ipairs({ 0, -2.5, 2.5 }) do
			for _, turn in ipairs({ 0, -0.6, 0.6 }) do
				for loft = ft.loftMinDeg, ft.loftMaxDeg, 5 do
					s.playerX, s.swivel, s.loftDeg = px, turn, loft
					local why = check(s)
					if why then
						bad = string.format("x %.1f turn %.1f loft %d: %s", px, turn, loft, why)
						break
					end
				end
				if bad then break end
			end
			if bad then break end
		end
		s.playerX, s.swivel, s.loftDeg = x0, sw0, l0
		return bad
	end,
}
