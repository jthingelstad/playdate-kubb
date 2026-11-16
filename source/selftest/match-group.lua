-- Scenario "match-group": the computer drilling a turn of kubbs into a group.
-- Scripted throws (core/autothrow) shown at rest at once until a turn of 3
-- kubbs comes up; its tosses are played back in real time. Then on, at once,
-- to a turn of 5 or more, played back in real time too. Frames: per turn,
-- 1 aiming the first kubb, then each kubb at rest (the group as it forms),
-- and the last kubb at rest before the raising. For a film (tools/film.sh
-- with film=1), the note gives the frames each turn plays in.
import "selftest/_match"

local st = tw.selftest

local want = { { of = 3, done = false }, { of = 5, done = false } }
local cur = nil       -- the turn being played back: its entry in want
local first = nil     -- frame the turn's first toss came up
local restAt = nil    -- frame the current toss came to rest
local lastN = 0       -- toss number at rest last captured
local marks = ""      -- the frames each filmed turn played in

local function pick(of)
	for _, w in ipairs(want) do
		if not w.done and (of == w.of or (w.of >= 5 and of >= 5)) then return w end
	end
end

st.scenarios["match-group"] = st.matchScenario {
	-- (seed 5 until 2026-11-16: any change to the physics plays a different
	-- match, and that one ended before a turn of five came up; 6, 7 and 8 film both)
	opts = { seed = 6, instant = true, skipHandoff = true },
	maxFrames = 6000,
	step = function(ms, ctx, h)
		local ts, s = ms.ts, ms.setup
		ctx.note = ctx.note .. marks
		if ms.phase == "over" then error("the match ended before both turns were filmed") end
		if not cur then
			if s and s.kind == "toss" and s.n == 1 and ts.mode == "aim" then
				local w = pick(s.of)
				if w then
					cur, first, restAt, lastN = w, ctx.frame, nil, 0
					ts.instant = false
					ms.opts.instant = false
					ctx:capture()
				end
			end
			return false
		end
		-- playing back the turn
		if s and s.kind == "toss" then
			if ts.mode == "rest" and not restAt and s.n ~= lastN then restAt = ctx.frame end
			if restAt and ctx.frame == restAt + 20 then
				ctx:capture()
				lastN, restAt = s.n, nil
				if s.n == s.of then
					cur.done = true
					local mark = string.format(" of%d=%d-%d", s.of, first, ctx.frame)
					marks, ctx.note = marks .. mark, ctx.note .. mark
					cur = nil
					ms.opts.instant = true
					ts.instant = true
					for _, w in ipairs(want) do
						if not w.done then return false end
					end
					return true
				end
			end
		end
		return false
	end,
}
