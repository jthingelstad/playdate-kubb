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

-- The pitch shown must be exactly the engine's: every scene item at the
-- pose core/outcome gives for the engine's state (view frame). Returns an
-- error string or nil. Call right after a throw is set up (aim or handoff).
function tw.selftest.pitchMatchesEngine(ms)
	local s = ms.setup
	if not s then return "no throw set up" end
	local pieces = tw.outcome.pieces(ms.m.game, s.side)
	local ts = ms.ts
	if ts.nitems ~= #pieces then return "items " .. ts.nitems .. " vs engine " .. #pieces end
	for i, p in ipairs(pieces) do
		local it = ts.items[i]
		if it.id ~= p.id then return "item " .. i .. " is " .. it.id .. ", engine " .. p.id end
		if math.abs(it.x - p.x) > 1e-3 or math.abs(it.y - p.y) > 1e-3 then
			return string.format("%s at (%.3f, %.3f), engine (%.3f, %.3f)", p.id, it.x, it.y, p.x, p.y)
		end
		if it.toppled ~= p.toppled then return p.id .. " toppled " .. tostring(it.toppled) end
	end
	return nil
end
