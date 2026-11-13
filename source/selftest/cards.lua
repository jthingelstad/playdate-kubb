-- Scenario "cards": the match's hand-off and winner cards in a whole match
-- of scripted throws (core/autothrow, shown at rest at once), every hand-off
-- passed with A. The card must match core/cards for the engine's state.
-- Frames: 1 the first hand-off whose team throws kubbs in before its
-- batons (a mid-match card: what the other team took, the kubbs and batons,
-- the pitch), 2 the same card with ten kubbs taken (the row must stay left of
-- the map), 3 the winner card. Then A must ask for a rematch.
import "selftest/_match"
import "core/cards"

local st = tw.selftest

local shotHandoff, shotWinner, pressed = false, false, false
local notes = ""

st.scenarios.cards = st.matchScenario {
	opts = { seed = 5, instant = true, maxTurns = 30 },
	refreshRate = 0,
	maxFrames = 6000,
	step = function(ms, ctx, h)
		if ms.phase == "handoff" and h.idle() then
			local c = ms.handoff
			if not c or c.to ~= ms.setup.side or c.turn ~= ms.m.game.turn then error("hand-off card out of date") end
			if not ms.card then error("no hand-off card image") end
			if not shotHandoff and c.kubbs > 0 and c.took then
				ctx:capture()
				-- the fullest "just took" row: ten kubbs must stay clear of the map
				local full = setmetatable({ took = { field = 5, base = 5 } }, { __index = c })
				tw.render.cards.handoff(full):draw(0, 0)
				ctx:capture()
				ms.card:draw(0, 0)
				shotHandoff = true
				notes = notes .. string.format(" handoff=turn%d,%s,kubbs%d,took%d+%d", c.turn, c.to, c.kubbs,
					c.took.field, c.took.base)
			end
			h.pressA()
		elseif ms.phase == "over" then
			if not shotWinner then
				if not ms.card then error("no winner card image") end
				if not shotHandoff then error("the match had no hand-off with kubbs to throw in") end
				ctx:capture()
				shotWinner = true
				local w = ms.win
				notes = notes .. string.format(" winner=%s turns=%d hits=%d/%d", w.winner, w.turns, w.hits, w.thrown)
				h.pressA()
				pressed = true
			elseif pressed and h.idle() then
				if ms.exit ~= "match" then error("A on the winner card gave " .. tostring(ms.exit)) end
				ctx.note = ctx.note .. notes
				return true
			end
		end
		return false
	end,
}
