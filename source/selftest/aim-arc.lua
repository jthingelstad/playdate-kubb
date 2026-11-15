-- Scenario "aim-arc": the planned arc and the target circle land on screen
-- (Codex on #74: a low throw lands near, under the long lens's lower edge).
-- Mid wind-up (frame 1), then for targets across the far half (both
-- sidelines and the middle, near the centerline, mid-half and on the far
-- baseline), every planned release from half past 5 to half past 12, from
-- the stance behind the target, and up to 1 o'clock from both ends of the
-- line (higher arcs from a corner rise over the top margin: the lens stops
-- widening at throw.tune.arcMinF): the circle
-- wholly on screen, the arc under the top margin and inside the sides, and
-- at least its last few points showing (it may rise in from the lower edge).
import "selftest/_throw"

local throw = tw.scenes.throw
local pt = tw.plan.tune

local function check(s)
	local top = throw.tune.arcTop
	local ring, arc, on, all, behind = throw.arcBox(s)
	if not ring then return "no arc" end
	if behind then return "circle behind the camera" end
	if ring[1] < 0 or ring[3] > 400 or ring[2] < 0 or ring[4] > 240 then
		return string.format("circle %.0f,%.0f %.0f,%.0f", ring[1], ring[2], ring[3], ring[4])
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
		local n = 0
		for _, tx in ipairs({ 0, -2.5, 2.5 }) do
			for _, ty in ipairs({ 4.2, 6, 8 }) do
				for _, px in ipairs({ false, -2.5, 2.5 }) do
					-- (from a corner of the line the highest arcs, past 1 o'clock,
					-- do not fit: the lens stops widening at arcMinF)
					local top = px and 150 or pt.releaseMaxDeg
					for rel = pt.releaseMinDeg, top, pt.arcStepDeg do
						s.stanceSet = false
						throw.aimAt(s, tx, ty)
						if px then throw.setStance(s, px, 0) end
						throw.setArc(s, rel)
						local why = check(s)
						if why then
							return string.format("target %.1f %.1f stance %s release %d: %s", tx, ty,
								px and tostring(px) or "behind", rel, why)
						end
						n = n + 1
					end
				end
			end
		end
		return nil, "aims=" .. n
	end,
}
