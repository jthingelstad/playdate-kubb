-- Scenario "drill": the practice pitch drilling a kubb. "Pitch: drill" is
-- chosen (setup), the d-pad moves the marker right and out, A is held for a
-- cut, the crank winds back into the band and flicks. Frames: 1 the drill
-- aim with the marker moved and the cut hint, 2 wound into the band, 3 the
-- kubb in the air, 4 its first touch, 5 at rest with the readout, 6 aiming
-- again with the drilled kubb still lying where it ended.
import "selftest/_throw"
import "core/drill"

local st = tw.selftest
local drill = tw.drill

local RIGHT, OUT = 40, 20 -- frames the d-pad is held each way

-- Where the marker ends after the d-pad steps (the scene's own movement at
-- 1/50 s a frame), so the wind-up can aim at its band.
local function markerAfter()
	local t = drill.tune
	local x, y = 0, t.markerStartY
	for _, step in ipairs { { RIGHT, 1, 0 }, { OUT, 0, 1 } } do
		local held = 0
		for _ = 1, step[1] do
			held = held + 1 / 50
			local v = math.min(t.markerSpeedMax, t.markerSpeed + t.markerAccel * held)
			x, y = drill.clampMarker(x + step[2] * v / 50, y + step[3] * v / 50)
		end
	end
	return x, y
end

local mx, my = markerAfter()
local sol = drill.solve(mx, my, 0)
local WIND = sol.band * tw.swing.tune.fullBackswingDeg

st.scenarios.drill = st.throwScenario {
	setup = function(s) tw.scenes.throw.setDrill(s, true) end,
	script = {
		{ n = 3 },
		{ n = RIGHT, hold = { "right" } },
		{ n = 1 },
		{ n = OUT, hold = { "up" } },
		{ n = 2, hold = { "a" } },
		{ n = 30, hold = { "a" }, crank = st.windup(WIND, 30).crank },
		{ n = 3, hold = { "a" } },
		{ cranks = st.flick { 6, 12, 18, 22, 24, 24, 24 }.cranks, hold = { "a" } },
		{ n = 300 },
	},
	shots = {
		function(s, f) return f == 3 + RIGHT + OUT + 2 end,
		function(s, f) return f == 3 + RIGHT + OUT + 3 + 31 end,
		function(s) return s.mode == "flight" and s.pb and s.showTime > 0.35 end,
		function(s) local d = st.sinceContact(s); return d and d >= 0 end,
		st.restShot(30),
		st.restShot(70),
	},
	maxFrames = 500,
	check = function(s)
		local l = s.last
		if not l or not l.drill then return "the throw was not a drill" end
		if math.abs(s.markerX - mx) > 0.01 or math.abs(s.markerY - my) > 0.01 then
			return string.format("marker at %.2f %.2f, expected %.2f %.2f", s.markerX, s.markerY, mx, my)
		end
		if l.cut ~= drill.CUT_A then return "cut " .. tostring(l.cut) end
		if l.verdict ~= "on" then return string.format("verdict %s: power %.2f band %.2f", l.verdict, l.power, l.band) end
		local d = math.sqrt((l.restX - mx) ^ 2 + (l.restY - my) ^ 2)
		if d > 0.6 then return string.format("rested %.2f m from the marker", d) end
		local kept = st.item(s, "d1")
		if not kept or math.abs(kept.x - l.restX) > 1e-3 then return "the drilled kubb was not kept" end
		if s.mode ~= "aim" then return "mode " .. s.mode end
		return nil, string.format("power=%.2f band=%.2f land_m=%.2f rest_m=%.2f", l.power, l.band,
			math.sqrt((l.landX - mx) ^ 2 + (l.landY - my) ^ 2), d)
	end,
}
