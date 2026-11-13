-- Scenario "aim-center": the player at x = 0 aiming straight down the pitch.
-- Frame 1: the aim camera with the far base kubbs. Frame 2: the same with the
-- crank docked, so the "use the crank" prompt shows. Also checks that the
-- real device input provider runs.
import "selftest/_throw"

tw.selftest.scenarios["aim-center"] = tw.selftest.throwScenario {
	script = { { n = 3 }, { n = 40, docked = true } },
	shots = {
		function(s, f) return f == 2 end,
		function(s, f) return f == 40 end,
	},
	check = function(s)
		if s.playerX ~= 0 or s.swivel ~= 0 then return "player moved" end
		local c = s.aimCam
		local h = tw.camera.uprightPx(c, 0, 8, 0.15)
		if h < 12 then return "far kubb only " .. h .. " px" end
		-- the real device provider answers without error (nothing pressed here)
		local d = tw.input.device()
		d:advance()
		if d:held("left") or d:pressed("a") then return "device provider sees a button" end
		if type(d:crank()) ~= "number" or type(d:dt()) ~= "number" then return "device provider" end
		d:docked()
	end,
}
