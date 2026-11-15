-- Scenario "clock-gauge": the throw gauge as a clock (hud.clock, DESIGN 4
-- "The throw: the crank as a clock"), the verdicts after a throw
-- (hud.verdicts) and the plan chip (hud.planChip), drawn over the practice
-- pitch with the scene's own plaques off (s.covered). Frames:
--   1 idle, targets for an 8 m baton (power 112..128, release 72..108)
--   2 winding at 10 o'clock, inside the power target (FLICK!)
--   3 swinging, just past 6, the backswing peak on the ring
--   4 overpowered: winding at half past 11
--   5 a drill: a high release target (120..150), SPIN R 2 planned
--   6 after a throw: the last peak and stop as hollow dots, SHORT / ON /
--     SHAKY, TILT R 2.5 planned
-- Every state is also drawn with hud.tune.cache off and must give the same
-- pixels as the cached layer's copy. The note gives the graphics calls of
-- hud.clock alone (launched with this scenario, selftest/_drawcount counts
-- them): a frame whose hand moved, a frame that repeats the last, a frame
-- that rebuilds the face.
import "selftest/_throw"
import "render/hud"

local st = tw.selftest
local throw = tw.scenes.throw
local hud = tw.render.hud
local gfx <const> = playdate.graphics

local function base()
	return { phase = "idle", arm = 0, crank = 0, back = 0, powerLo = 112, powerHi = 128, releaseLo = 72,
		releaseHi = 108, deadDeg = 30, overDeg = 150, lastBack = nil, lastStop = nil, prompt = nil }
end

local function with(t)
	local s = base()
	for k, v in pairs(t) do s[k] = v end
	return s
end

local STATES = {
	{ st = with { phase = "idle", crank = 12, prompt = "WIND BACK" } },
	{ st = with { phase = "winding", arm = -120, back = 120, prompt = "FLICK!" } },
	{ st = with { phase = "swinging", arm = 20, back = 122 } },
	{ st = with { phase = "winding", arm = -165, back = 165, prompt = "EASE OFF" } },
	{ st = with { phase = "idle", crank = 8, powerLo = 98, powerHi = 112, releaseLo = 120, releaseHi = 150,
		prompt = "WIND BACK" }, plan = { "kubb", 2 } },
	{ st = with { phase = "idle", crank = 96, lastBack = 104, lastStop = 96, prompt = "WIND BACK" },
		verdicts = { -1, 0, false }, plan = { "baton", 2.5 } },
}

-- the HUD's region (everything this scenario draws is below y 150)
local Y0 = 150
local function differs(a, b)
	local bad = 0
	for y = Y0, 239 do
		for x = 0, 399 do
			if a:sample(x, y) ~= b:sample(x, y) then bad = bad + 1 end
		end
	end
	return bad
end

local function drawState(S)
	hud.clock(S.st)
	if S.plan then hud.planChip(S.plan[1], S.plan[2]) end
	if S.verdicts then hud.verdicts(S.verdicts[1], S.verdicts[2], S.verdicts[3]) end
end

st.scenarios["clock-gauge"] = {
	step = function(ctx)
		local C = tw.drawcount
		if not ctx.scene then
			ctx.scene = throw.new(tw.input.scripted { { n = 600 } })
			ctx.scene.covered = true
			throw.enter()
			ctx.i, ctx.k = 1, 0
			ctx.moving, ctx.movingN, ctx.still, ctx.stillN, ctx.rebuild = 0, 0, 0, 0, 0
		end
		local s = ctx.scene
		throw.update(s)
		throw.draw(s)
		local S = STATES[ctx.i]
		if S then
			-- k 0: drawn straight (new inputs); 1: the layer filled; 2: its copy
			-- (captured); 3: cache off, compared with 2
			local k = ctx.k
			hud.tune.cache = (k ~= 3)
			C.n = 0
			drawState(S)
			if k == 2 then
				ctx.a = gfx.getWorkingImage()
				ctx:capture()
			elseif k == 3 then
				local bad = differs(ctx.a, gfx.getWorkingImage())
				hud.tune.cache = true
				if bad > 0 then error(string.format("state %d: %d pixels differ with the cache off", ctx.i, bad)) end
			end
			if k == 3 then ctx.i, ctx.k = ctx.i + 1, 0 else ctx.k = k + 1 end
			return false
		end
		-- the counts: hud.clock alone, a wind-up from 7 to 10 o'clock (the hand
		-- moves every frame), then the dial held still
		local f = ctx.count or 0
		ctx.count = f + 1
		hud.tune.cache = true
		local W = ctx.wind or with { phase = "winding" }
		ctx.wind = W
		if f < 20 then
			W.arm, W.back = -30 - f * 5, 30 + f * 5
		end
		C.n = 0
		if f == 20 then W.powerLo = 110 end   -- re-aimed: the face is drawn again
		hud.clock(W)
		if f >= 1 and f < 20 then ctx.moving, ctx.movingN = ctx.moving + C.n, ctx.movingN + 1
		elseif f == 20 then ctx.rebuild = C.n
		elseif f >= 23 then ctx.still, ctx.stillN = ctx.still + C.n, ctx.stillN + 1 end
		if f < 30 then return false end
		if not C.on then
			ctx.note = "pixels same with the cache off; calls not counted (launch with selftest=clock-gauge)"
		else
			ctx.note = string.format("pixels same with the cache off; hud.clock calls: hand moving %.1f, still %.1f, face rebuilt %d",
				ctx.moving / ctx.movingN, ctx.still / ctx.stillN, ctx.rebuild)
		end
		return true
	end,
}
