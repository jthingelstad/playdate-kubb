-- Shared kit for the throw-scene self-tests. Files in source/selftest/ that
-- start with "_" are helpers, not scenarios (the Makefile skips them).
--
-- tw.selftest.throwScenario{ script = {...}, shots = {...}, check = fn, maxFrames = n, setup = fn }
--   script  input.scripted steps (crank degrees are raw, as getCrankChange)
--   shots   array of predicates fn(scene, frame) -> true when the frame
--           should be captured; each fires once, in order
--   check   optional fn(scene) -> nil or an error string, run at the end; a
--           second return value is appended to the marker's note
--   setup   optional fn(scene), run once after the scene is made (a layout,
--           a surface)
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
				if def.setup then def.setup(scene) end
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
					local err, extra = def.check(scene)
					if err then error(err) end
					if extra then ctx.note = ctx.note .. " " .. extra end
				end
				return true
			end
			if ctx.frame >= (def.maxFrames or 600) then
				error("only " .. (shot - 1) .. " of " .. #def.shots .. " shots by frame " .. ctx.frame
					.. " (" .. tw.selftest.describe(scene) .. ")")
			end
			return false
		end,
	}
end

-- One line about the scene and its physics, for failure messages.
function tw.selftest.describe(s)
	local out = "mode " .. s.mode
	local pb = s.pb
	if pb then
		local w = pb.w
		out = out .. string.format(", frame %d of %d, done %s, sim %.2f s, %d steps", pb.frame, pb.frames,
			tostring(pb.done), w.time, w.steps)
		for i = 1, w.n do
			local b = w.bodies[i]
			if b.awake then
				out = out .. string.format("; %s awake at %.2f %.2f %.3f v %.3f %.3f %.3f w %.2f %.2f %.2f",
					b.id, b.x, b.y, b.z, b.vx, b.vy, b.vz, b.wx, b.wy, b.wz)
			end
		end
	end
	return out
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

-- Seconds of the throw on screen relative to the baton's first hit on a
-- body (nil until the physics has found one).
function tw.selftest.sinceHit(s)
	local pb = s.pb
	if not pb or not pb.w.firstHit then return nil end
	return s.showTime - pb.w.firstHit.t
end

-- The same relative to the baton's first contact with anything.
function tw.selftest.sinceContact(s)
	local pb = s.pb
	if not pb or not pb.w.firstContact then return nil end
	return s.showTime - pb.w.firstContact.t
end

-- A shot `after` frames into the rest after a throw (the rest hold is 50
-- frames; past it the scene is aiming again). Each scenario makes its own.
function tw.selftest.restShot(after)
	local at = nil
	return function(s, f)
		if s.mode == "rest" and not at then at = f end
		return at and f == at + after
	end
end

-- The scene item with this id.
function tw.selftest.item(s, id)
	for i = 1, s.nitems do
		if s.items[i].id == id then return s.items[i] end
	end
end

-- Is the flying baton's center on screen, above row maxY?
function tw.selftest.batonOnScreen(s, maxY)
	local fl = s.flight
	local sx, sy = tw.camera.project(s.viewCam, fl.x, fl.y, fl.z)
	return sx and sx >= 0 and sx <= 400 and sy >= 0 and sy <= (maxY or 240)
end
