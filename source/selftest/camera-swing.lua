-- Scenario "camera-swing": the aim camera's two views (docs/notes/throw.md "The aim
-- camera"). On the practice pitch with a baton: first person (frame 1); B
-- held swings the camera out over the shoulder and zooms out (frame 2 half
-- way, frame 3 settled: the whole target half, the arc and the circle); B +
-- up raises the arc and the plan view re-fits (frame 4); B let go swings it
-- back (frame 5 half way, frame 6 first person again, exactly the camera of
-- frame 1). Then the same for a drill (frames 7 to 10: first person, half
-- way, the plan view, back). The crank never moves: nothing is thrown.
-- Launched with selftest=camera-swing the graphics calls are counted
-- (selftest/_drawcount.lua): the note gives the mean calls of an aim frame
-- with the camera still (the world frame is a cached image) and moving
-- (every one a full draw of the world).
import "selftest/_throw"

local st = tw.selftest
local throw = tw.scenes.throw
local camera = tw.camera

local SCRIPT = {
	{ n = 5 },                                    -- 1-5 first person
	{ n = 40, hold = { "b" } },                   -- 6-45 the plan view
	{ hold = { "b" }, press = { "up" } },         -- 46 the arc up a step
	{ n = 24, hold = { "b" } },                   -- 47-70
	{ n = 30 },                                   -- 71-100 back to first person
	{ n = 5 },                                    -- 101-105 (a drill from 101)
	{ n = 30, hold = { "b" } },                   -- 106-135
	{ n = 30 },                                   -- 136-165
}

-- frame -> what is captured there and checked
local SHOTS = { [3] = "fp", [15] = "mid", [30] = "plan", [70] = "refit", [80] = "mid", [100] = "back",
	[104] = "fp", [115] = "mid", [135] = "plan", [165] = "back" }

local function camKey(c)
	return string.format("%.6f %.6f %.6f %.6f %.6f %.6f %.4f %.4f %.4f", c.px, c.py, c.pz, c.lx, c.ly, c.lz, c.f,
		c.cx, c.cy)
end

local function onScreen(c, x, y, z)
	local sx, sy = camera.project(c, x, y, z or 0)
	return sx and sx >= 0 and sx <= 400 and sy >= 0 and sy <= 240
end

local function planCheck(s, what)
	local c = s.aimCam
	if s.camMix ~= 1 then return what .. ": mix " .. s.camMix end
	for _, p in ipairs { { -2.5, 8 }, { 2.5, 8 }, { 0, 4 }, { -1, 4 }, { 1, 4 } } do
		if not onScreen(c, p[1], p[2]) then return string.format("%s: (%.1f, %.0f) off screen", what, p[1], p[2]) end
	end
	if not onScreen(c, s.markerX, s.markerY) then return what .. ": the circle off screen" end
	if c.f >= s.fpCam.f then return what .. ": no zoom out" end
	if c.px <= s.playerX + 0.5 then return what .. ": not over the right shoulder" end
	local ring, arc, on = throw.arcBox(s)
	if ring and (on < 3 or arc[2] < camera.tune.shoulder.top - 1 or arc[1] < 0 or arc[3] > 400) then
		return string.format("%s: arc %.0f,%.0f %.0f,%.0f (%d on)", what, arc[1], arc[2], arc[3], arc[4], on)
	end
end

st.scenarios["camera-swing"] = {
	step = function(ctx)
		local C = tw.drawcount
		if not ctx.scene then
			ctx.scene = throw.new(tw.input.scripted(SCRIPT))
			throw.enter()
			ctx.still, ctx.nStill, ctx.moving, ctx.nMoving, ctx.lastKey = 0, 0, 0, 0, nil
		end
		local s = ctx.scene
		local f = ctx.frame
		if f == 101 then throw.setDrill(s, true) end
		throw.update(s)
		C.n = 0
		throw.draw(s)
		local key = camKey(s.aimCam)
		if ctx.lastKey then
			if key == ctx.lastKey then ctx.still, ctx.nStill = ctx.still + C.n, ctx.nStill + 1
			else ctx.moving, ctx.nMoving = ctx.moving + C.n, ctx.nMoving + 1 end
		end
		ctx.lastKey = key
		local what = SHOTS[f]
		if what then
			local label = (f > 100 and "drill " or "baton ") .. what
			local err
			if what == "fp" then
				if s.camMix ~= 0 then err = "mix " .. s.camMix end
				if camera.uprightPx(s.aimCam, 0, 8, 0.15) < 12 then err = "far kubb under 12 px" end
				if not onScreen(s.aimCam, s.markerX, s.markerY) then err = "the circle off screen" end
				if math.abs(s.aimCam.px - s.playerX) > 0.01 then err = "not behind the thrower" end
				ctx.fpKey = key
			elseif what == "mid" then
				if not (s.camMix > 0.3 and s.camMix < 0.7) then err = "mix " .. s.camMix end
			elseif what == "plan" then
				err = planCheck(s, label)
				ctx.planF = s.aimCam.f
			elseif what == "refit" then
				if s.release ~= ctx.release0 + tw.plan.tune.arcStepDeg then err = "release " .. tostring(s.release) end
				err = err or planCheck(s, label)
			elseif what == "back" then
				if s.camMix ~= 0 then err = "mix " .. s.camMix end
				if key ~= ctx.fpKey then err = "not the first-person camera again" end
			end
			if err then error(label .. ": " .. err) end
			if what == "plan" and f < 100 then ctx.release0 = s.release end
			ctx:capture()
		end
		if s.throws ~= 0 or s.mode ~= "aim" then error("thrown: mode " .. s.mode) end
		ctx.note = string.format("aim calls still=%.1f (%d) moving=%.1f (%d)",
			ctx.nStill > 0 and ctx.still / ctx.nStill or 0, ctx.nStill,
			ctx.nMoving > 0 and ctx.moving / ctx.nMoving or 0, ctx.nMoving)
		return f >= 165
	end,
}
