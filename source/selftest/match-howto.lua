-- Scenario "match-howto": HOW TO THROW in a match (System Menu "Match: how
-- to"; Codex on #81: the match drove its own phases under it). A VS match:
-- asked for over the first hand-off card, it shows at once (frame 1), B only
-- leaves it (the card stays), and the match goes on. Asked for while the
-- Playdate shows its aim, nothing is thrown under it however long it stays
-- up (frame 2); B puts it away and the Playdate throws.
import "selftest/_match"

local st = tw.selftest
local throw = tw.scenes.throw

local stage, at = 1, nil

st.scenarios["match-howto"] = st.matchScenario {
	opts = { vs = "B", seed = 5, cpuSeed = 7, instant = true, maxTurns = 14, cpuThink = 0.12 },
	maxFrames = 6000,
	step = function(ms, ctx, h)
		local ts = ms.ts
		if stage == 1 then
			if ms.phase == "handoff" then
				throw.showHowTo(ts)
				at = { frame = ctx.frame }
				stage = 2
			end
		elseif stage == 2 then
			if not ts.howto then error("the card went away by itself") end
			if ms.phase ~= "handoff" then error("the match left the hand-off under the card: " .. ms.phase) end
			if ctx.frame >= at.frame + 3 then
				ctx:capture()
				h.feed { { press = { "b" } }, { n = 3 } }
				stage = 3
			end
		elseif stage == 3 and h.idle() then
			if ts.howto then error("B did not leave the walkthrough") end
			if ms.phase ~= "handoff" then error("B went through the walkthrough to the hand-off: " .. ms.phase) end
			h.feed { { press = { "a" } }, { n = 2 } }
			stage = 4
		elseif stage == 4 then
			if ms.phase == "play" and ts.mode == "aim" and ms.cpu and ms.setup.side == ms.cpu and ts.watching then
				throw.showHowTo(ts)
				at = { frame = ctx.frame, throws = ms.throws, cpu = ms.cpuThrows }
				stage = 5
			end
		elseif stage == 5 then
			if ms.cpuThrows ~= at.cpu or ts.mode ~= "aim" then error("the Playdate threw under the card") end
			if ctx.frame >= at.frame + 40 then
				ctx:capture()
				h.feed { { press = { "b" } }, { n = 2 } }
				stage = 6
			end
		elseif stage == 6 and ms.cpuThrows > at.cpu then
			if ts.howto then error("B did not leave the walkthrough") end
			return true
		end
		return false
	end,
}
