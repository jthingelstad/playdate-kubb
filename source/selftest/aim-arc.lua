-- Scenario "aim-arc": the target circle and the planned arc land on screen
-- (Codex on #74: a low throw lands near). Mid wind-up in first person
-- (frame 1), then for targets across the far half (both sidelines and the
-- middle, near the centerline, mid-half and on the far baseline), every
-- planned release from half past 5 to half past 12, from the stance behind
-- the target and from both ends of the line: in first person the circle
-- wholly on screen and the far base kubb at least 12 px tall; in the plan
-- view (B held: camera.shoulder) the circle on screen, the arc under the top
-- of the fit box and inside the sides, and at least its last few points
-- showing (its first rise may come in from the lower edge). Then the same
-- for drills: circles across the area the d-pad allows, the arc down to
-- where the kubb lands.
import "selftest/_throw"

local throw = tw.scenes.throw
local camera = tw.camera
local pt = tw.plan.tune

local function ringOn(ring)
	return ring[1] >= 0 and ring[3] <= 400 and ring[2] >= 0 and ring[4] <= 240
end

local function check(s)
	-- first person
	s.camMix = 0
	local ring, arc, on, all, behind = throw.arcBox(s)
	if not ring then return "no arc" end
	if behind then return "first person: circle behind the camera" end
	if not ringOn(ring) then
		return string.format("first person: circle %.0f,%.0f %.0f,%.0f", ring[1], ring[2], ring[3], ring[4])
	end
	local h = camera.uprightPx(s.aimCam, 0, 8, 0.15)
	if h < 12 then return string.format("first person: far kubb %.1f px", h) end
	-- the plan view
	s.camMix = 1
	ring, arc, on, all, behind = throw.arcBox(s)
	s.camMix = 0
	if behind then return "plan view: circle behind the camera" end
	if not ringOn(ring) then
		return string.format("plan view: circle %.0f,%.0f %.0f,%.0f", ring[1], ring[2], ring[3], ring[4])
	end
	if on < 3 then return "plan view: arc " .. on .. "/" .. all .. " on screen" end
	local top = camera.tune.shoulder.top
	if arc[1] < 0 or arc[3] > 400 or arc[2] < top - 1 then
		return string.format("plan view: arc %.0f,%.0f %.0f,%.0f", arc[1], arc[2], arc[3], arc[4])
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
					for rel = pt.releaseMinDeg, pt.releaseMaxDeg, pt.arcStepDeg do
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
		-- a drill's arc (down to where the kubb lands, short of its circle),
		-- circles across the area the d-pad allows (drill.clampMarker)
		local nb = n
		throw.setDrill(s, true)
		for _, tx in ipairs({ 0, -3, 3 }) do
			for _, ty in ipairs({ 3.5, 6, 8.6 }) do
				for _, px in ipairs({ false, -2.5, 2.5 }) do
					for rel = pt.releaseMinDeg, pt.releaseMaxDeg, pt.arcStepDeg do
						s.stanceSet = false
						throw.aimAt(s, tx, ty)
						if px then throw.setStance(s, px, 0) end
						throw.setArc(s, rel)
						local why = check(s)
						if why then
							return string.format("drill circle %.1f %.1f stance %s release %d: %s", tx, ty,
								px and tostring(px) or "behind", rel, why)
						end
						n = n + 1
					end
				end
			end
		end
		return nil, "aims=" .. nb .. " drills=" .. (n - nb)
	end,
}
