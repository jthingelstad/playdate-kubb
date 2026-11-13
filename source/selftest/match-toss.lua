-- Scenario "match-toss": a kubb toss and the automatic raising after it.
-- Scripted throws (core/autothrow) shown at rest at once until the first
-- toss comes up; that toss is played back in real time. When the tosses are
-- done the tossed kubbs are raised by the engine's policy and the thrower's
-- next baton aims at them. Frames: 1 aiming the toss (the kubb label),
-- 2 the kubb in the air, 3 it at rest with the result line, 4 aiming the
-- next baton at the raised field kubbs (and the advantage line if there is
-- one).
import "selftest/_match"

local st = tw.selftest

local stage = 1
local tossSide = nil
local restAt = nil

st.scenarios["match-toss"] = st.matchScenario {
	opts = { seed = 11, instant = true, skipHandoff = true },
	maxFrames = 1500,
	step = function(ms, ctx, h)
		local ts = ms.ts
		if ms.phase == "over" then error("the match ended before a toss") end
		if stage == 1 then
			-- fast-forward to the first toss, then show it as it happens
			if ms.setup and ms.setup.kind == "toss" and ts.mode == "aim" then
				ts.instant = false
				ms.opts.instant = false
				tossSide = ms.setup.side
				ctx:capture()
				stage = 2
			end
		elseif stage == 2 then
			if ts.mode == "flight" and ts.pb and ts.showTime > 0.45 then
				if not ts.projItem then error("no kubb in the air") end
				ctx:capture()
				stage = 3
			end
		elseif stage == 3 then
			if ts.mode == "rest" and not restAt then restAt = ctx.frame end
			if restAt and ctx.frame == restAt + 20 then
				if not ms.result then error("no result line") end
				ctx:capture()
				ms.opts.instant = true
				ts.instant = true
				stage = 4
			end
		elseif stage == 4 then
			-- the first baton after the tosses
			local s = ms.setup
			if s and s.kind == "baton" and ts.mode == "aim" then
				if s.side ~= tossSide then error("batons went to " .. s.side .. ", tosses were " .. tossSide) end
				ts.instant = false
				-- every field kubb on the pitch stands (raised by the engine)
				local fields = 0
				for _, p in ipairs(s.pieces) do
					if p.role == "field" then
						fields = fields + 1
						if p.toppled then error(p.id .. " was not raised") end
					end
				end
				local err = st.pitchMatchesEngine(ms)
				if err then error(err) end
				ctx.note = ctx.note .. string.format(" fields=%d raised=%d", fields,
					ms.m.settled and ms.m.settled.raised or 0)
				ctx:capture()
				return true
			end
		end
		return false
	end,
}
