-- Scenario "layer": the hit throw (the plan's clean throw onto b3) with
-- render/world's verify on: every frame drawn from the layer (the still
-- pieces kept in a background image while the camera holds) is drawn a second time from scratch and the two must match pixel
-- for pixel. The camera is made to hold on the impact point once the baton
-- touches anything (frameRadius 0) and its half circle is off (swingDeg 0),
-- so the layer is used while b3 falls. At least 40 layered frames (44 on
-- the Simulator with the plan's throw, 2026-11-15; 66 with the old one).
-- Frames: 1 b3 falling, 2 at rest.
import "selftest/_throw"

local st = tw.selftest
local R = tw.render.world
local T = tw.scenes.throw
local frameRadius

st.scenarios.layer = st.throwScenario {
	setup = function(s)
		R.verify = {}
		frameRadius = T.tune.frameRadius
		T.tune.frameRadius = 0
		T.tune.swingDeg = 0   -- one scenario a Simulator run: nothing to restore
	end,
	script = function(s) return st.planned(s) end,
	shots = {
		function(s) local d = st.sinceHit(s); return d and d >= 0.25 end,
		st.restShot(10),
	},
	maxFrames = 400,
	check = function(s)
		local V, C = R.verify, R.count
		R.verify = nil
		T.tune.frameRadius = frameRadius
		if V.frames < 40 then
			return string.format("only %d layered frames (cached %d, built %d, full %d)", V.frames, C.cached, C.built, C.full)
		end
		if V.bad > 0 then return V.bad .. " pixels differ in " .. V.frames .. " layered frames" end
		return nil, "layered=" .. V.frames
	end,
}
