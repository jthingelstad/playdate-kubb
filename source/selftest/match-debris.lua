-- Scenario "match-debris": within a turn the batons thrown and the kubbs they
-- knocked down stay lying on the pitch; the hand-off clears them. Scripted
-- throws (core/autothrow) shown at rest at once until a baton is set up
-- with a downed kubb and a lying baton from earlier in the same turn; that
-- baton is played back in real time. Frames: 1 aiming with the debris on
-- the pitch (and on the minimap), 2 that baton at rest among it, 3 the
-- hand-off card at the end of the turn (the debris gone), 4 the other
-- team aiming at the engine's pitch.
import "selftest/_match"

local st = tw.selftest

local stage = 1
local restAt = nil
local turn, side = nil, nil

st.scenarios["match-debris"] = st.matchScenario {
	opts = { seed = 7, instant = true },
	maxFrames = 3000,
	step = function(ms, ctx, h)
		local ts = ms.ts
		if ms.phase == "over" then error("the match ended at stage " .. stage) end
		if stage == 1 then
			if ms.phase == "handoff" and h.idle() then h.pressA() end
			local s = ms.setup
			if ms.phase == "play" and ts.mode == "aim" and s and s.kind == "baton" then
				local k, b = st.debrisShown(ms)
				if k >= 1 and b >= 1 and s.n < s.of then
					local err = st.pitchMatchesEngine(ms)
					if err then error(err) end
					turn, side = ms.m.game.turn, s.side
					ctx.note = ctx.note .. string.format(" debris_kubbs=%d debris_batons=%d", k, b)
					ctx:capture()
					ts.instant = false
					ms.opts.instant = false
					stage = 2
				end
			end
		elseif stage == 2 then
			if ts.mode == "rest" and not restAt then restAt = ctx.frame end
			if restAt and ctx.frame == restAt + 20 then
				-- the earlier debris is still drawn while this baton rests
				local k, b = st.debrisShown(ms)
				if k + b < 2 then error("debris gone during the rest hold") end
				ctx:capture()
				ts.instant = true
				ms.opts.instant = true
				stage = 3
			end
		elseif stage == 3 then
			if ms.phase == "play" and ts.mode == "aim" and ms.m.game.turn == turn then
				-- another throw of the same turn: the debris is still there
				local err = st.pitchMatchesEngine(ms)
				if err then error(err) end
				local k, b = st.debrisShown(ms)
				if b < 2 then error("the turn's batons are not all lying there: " .. b) end
			end
			if ms.phase == "handoff" then
				if ms.m.game.turn == turn then error("hand-off within the turn") end
				if #ms.setup.debris ~= 0 or #ms.m.debris.list ~= 0 then error("debris after the hand-off") end
				local err = st.pitchMatchesEngine(ms)
				if err then error(err) end
				ctx:capture()
				h.pressA()
				stage = 4
			end
		elseif stage == 4 then
			if ms.phase == "play" and ts.mode == "aim" then
				if ms.setup.side == side then error("the Playdate did not change hands") end
				local err = st.pitchMatchesEngine(ms)
				if err then error(err) end
				local k, b = st.debrisShown(ms)
				if k + b ~= 0 then error("debris shown after the hand-off") end
				ctx:capture()
				return true
			end
		end
		return false
	end,
}
