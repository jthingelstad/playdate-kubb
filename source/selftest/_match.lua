-- Shared kit for the match self-tests (helper, not a scenario).
--
-- tw.selftest.matchScenario{ opts = {...}, step = fn(ms, ctx, h), maxFrames = n }
--   opts   scenes/match options (seed, instant, skipHandoff, maxTurns)
--   step   called after each frame's update + draw with the match scene;
--          returns true when the scenario is done. `h` holds
--            h.feed(steps)   play these input.scripted steps from the next frame
--            h.pressA()      press A on the next frame
--            h.idle()        no scripted input is left
-- It times update + draw per frame and puts avg/max ms in ctx.note (a
-- scenario may append to it).
import "core/tw"
import "input"
import "scenes/match"
import "core/outcome"

local scene = tw.scenes.match

function tw.selftest.matchScenario(def)
	local ms, p, h = nil, nil, {}
	local total, worst, frames = 0, 0, 0
	function h.feed(steps)
		p.steps, p.i, p.k = steps, 1, 0
	end
	function h.pressA() h.feed { { press = { "a" } } } end
	function h.idle() return p:finished() end
	return {
		step = function(ctx)
			if not ms then
				p = tw.input.scripted({})
				ms = scene.new(p, def.opts)
				scene.enter()
				if def.refreshRate then playdate.display.setRefreshRate(def.refreshRate) end
			end
			local t0 = playdate.getElapsedTime()
			scene.update(ms)
			scene.draw(ms)
			local ms_ = (playdate.getElapsedTime() - t0) * 1000
			frames, total, worst = frames + 1, total + ms_, math.max(worst, ms_)
			ctx.note = string.format("avg_ms=%.2f max_ms=%.2f", total / frames, worst)
			if def.step(ms, ctx, h) then return true end
			if ctx.frame >= (def.maxFrames or 2000) then
				error("not done by frame " .. ctx.frame .. " (phase " .. ms.phase .. ", turn " .. ms.m.game.turn
					.. ", mode " .. ms.ts.mode .. ")")
			end
			return false
		end,
	}
end

-- The pitch shown must be exactly the engine's plus this turn's debris:
-- every scene item at the pose core/outcome gives for the engine's state
-- (view frame; a lying kubb may be at its exact rest pose nearby), then one
-- item per debris piece of the setup, down, at its pose. Returns an error
-- string or nil. Call right after a throw is set up (aim or handoff).
function tw.selftest.pitchMatchesEngine(ms)
	local s = ms.setup
	if not s then return "no throw set up" end
	local pieces = tw.outcome.pieces(ms.m.game, s.side)
	local ts = ms.ts
	local nd = #(s.debris or {})
	if ts.nitems ~= #pieces + nd then
		return "items " .. ts.nitems .. " vs engine " .. #pieces .. " + debris " .. nd
	end
	for i, p in ipairs(pieces) do
		local it = ts.items[i]
		if it.id ~= p.id then return "item " .. i .. " is " .. it.id .. ", engine " .. p.id end
		if math.abs(it.x - p.x) > 1e-3 or math.abs(it.y - p.y) > 1e-3 then
			return string.format("%s at (%.3f, %.3f), engine (%.3f, %.3f)", p.id, it.x, it.y, p.x, p.y)
		end
		if it.toppled ~= p.toppled then return p.id .. " toppled " .. tostring(it.toppled) end
		-- core 1.0's seat: a kubb drawn plumb would be leaned by world.addPiece when the
		-- throw's world is built and step at its first frame (docs/notes/match.md "The seat")
		local _, _, _, _, seated = tw.world.seat(s.surface, it.kind, it.x, it.y, it.qw, it.qx, it.qy, it.qz)
		if seated then return p.id .. " is drawn plumb; the throw's world will seat it" end
	end
	for i = 1, nd do
		local d, it = s.debris[i], ts.items[#pieces + i]
		if it.id ~= d.id or it.kind ~= d.kind then return "debris item " .. i .. " is " .. it.id end
		if math.abs(it.x - d.x) > 1e-3 or math.abs(it.y - d.y) > 1e-3 or not it.toppled then
			return string.format("debris %s at (%.3f, %.3f), want (%.3f, %.3f)", d.id, it.x, it.y, d.x, d.y)
		end
	end
	return nil
end

-- Debris items on the pitch now: kubbs and batons (counts).
function tw.selftest.debrisShown(ms)
	local s, ts = ms.setup, ms.ts
	local kubbs, batons = 0, 0
	local first = s and (ts.nitems - #(s.debris or {})) or ts.nitems
	for i = first + 1, ts.nitems do
		if ts.items[i].baton then batons = batons + 1 else kubbs = kubbs + 1 end
	end
	return kubbs, batons
end
