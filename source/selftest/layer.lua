-- Scenario "layer": the hit throw (a strong clean throw at 30 degrees of
-- loft onto b3) with render/world's verify on: every frame drawn from the
-- layer (the still pieces kept in a background image while the camera
-- holds) is drawn a second time from scratch and the two must match pixel
-- for pixel. The camera is made to hold on the impact point once the baton
-- touches anything (frameRadius 0), so the layer is used while b3 falls.
-- Frames: 1 b3 falling, 2 at rest.
import "selftest/_throw"

local st = tw.selftest
local R = tw.render.world
local T = tw.scenes.throw
local frameRadius

st.scenarios.layer = st.throwScenario {
	setup = function(s)
		s.loftDeg = 30
		R.verify = {}
		frameRadius = T.tune.frameRadius
		T.tune.frameRadius = 0
	end,
	script = {
		{ n = 5 },
		st.windup(120, 30),
		{ n = 5 },
		st.flick { 6, 12, 18, 22, 24, 24, 24 },
		{ n = 300 },
	},
	shots = {
		function(s) local d = st.sinceHit(s); return d and d >= 0.25 end,
		st.restShot(10),
	},
	maxFrames = 400,
	check = function(s)
		local V, C = R.verify, R.count
		R.verify = nil
		T.tune.frameRadius = frameRadius
		if V.frames < 50 then
			return string.format("only %d layered frames (cached %d, built %d, full %d)", V.frames, C.cached, C.built, C.full)
		end
		if V.bad > 0 then return V.bad .. " pixels differ in " .. V.frames .. " layered frames" end
		return nil, "layered=" .. V.frames
	end,
}
