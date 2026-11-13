-- Shared kit for the throw-scene self-tests. Files in source/selftest/ that
-- start with "_" are helpers, not scenarios (the Makefile skips them).
--
-- tw.selftest.throwScenario{ script = {...}, shots = {...}, check = fn, maxFrames = n }
--   script  input.scripted steps (crank degrees are raw, as getCrankChange)
--   shots   array of predicates fn(scene, frame) -> true when the frame
--           should be captured; each fires once, in order
--   check   optional fn(scene) -> nil or an error string, run at the end
-- The scenario ends when every shot is taken (or fails after maxFrames).
-- It also times update + draw per frame and appends avg/max ms to the marker.
import "core/tw"
import "input"
import "scenes/throw"
import "core/trace"
import "recorder"

local throw = tw.scenes.throw

function tw.selftest.throwScenario(def)
	local scene, shot = nil, 1
	local total, worst, frames = 0, 0, 0
	return {
		step = function(ctx)
			if not scene then
				scene = throw.new(tw.input.scripted(def.script, nil, def.startPos))
				throw.enter()
			end
			local t0 = playdate.getElapsedTime()
			throw.update(scene)
			throw.draw(scene)
			local ms = (playdate.getElapsedTime() - t0) * 1000
			frames, total, worst = frames + 1, total + ms, math.max(worst, ms)
			ctx.note = string.format("avg_ms=%.2f max_ms=%.2f", total / frames, worst)
			local want = def.shots[shot]
			if want and want(scene, ctx.frame) then
				ctx:capture()
				shot = shot + 1
			end
			if shot > #def.shots then
				if def.check then
					local err = def.check(scene)
					if err then error(err) end
				end
				return true
			end
			if ctx.frame >= (def.maxFrames or 600) then
				error("only " .. (shot - 1) .. " of " .. #def.shots .. " shots by frame " .. ctx.frame)
			end
			return false
		end,
	}
end

-- Script pieces. Raw crank degrees: negative = anti-clockwise = back (with
-- swing.tune.forwardSign = 1), so these follow the sign.
local function sign() return tw.swing.tune.forwardSign end

function tw.selftest.windup(deg, frames)
	return { crank = -sign() * deg / frames, n = frames }
end

function tw.selftest.flick(steps)
	local c = {}
	for i, d in ipairs(steps) do c[i] = sign() * d end
	return { cranks = c }
end

-- Is the flying baton's center on screen, above row maxY?
function tw.selftest.batonOnScreen(s, maxY)
	local fl = s.flight
	local sx, sy = tw.camera.project(s.viewCam, fl.x, fl.y, fl.z)
	return sx and sx >= 0 and sx <= 400 and sy >= 0 and sy <= (maxY or 240)
end
