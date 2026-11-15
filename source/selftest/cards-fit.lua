-- Scenario "cards-fit": the winner card with names that used to run off it
-- (the RC review of 2026-11-15). Frames: 1 a team name too wide for display
-- 32 beside the burst ("TEAM MONTGOMERY", drawn in display 16) and six
-- players with ten-letter names (packed by width, two lines), 2 a name that
-- still fits display 32 ("SNOW KUBBS").
import "core/tw"
import "render/cards"
import "render/ui"

local rcards, ui = tw.render.cards, tw.render.ui

local function card(name, players)
	return { winnerName = name, turns = 24, minutes = 31, thrown = 60, hits = 25, players = players }
end

local SIX = {
	{ name = "Montgomery", hits = 22, thrown = 29 }, { name = "Alexandria", hits = 15, thrown = 28 },
	{ name = "Bartholomew", hits = 9, thrown = 12 }, { name = "Christabel", hits = 11, thrown = 20 },
	{ name = "Maximilian", hits = 3, thrown = 9 }, { name = "Jacqueline", hits = 18, thrown = 30 },
}

tw.selftest.scenarios["cards-fit"] = {
	step = function(ctx)
		if ctx.frame == 1 then
			local t = rcards.tune
			if ui.display(32):getTextWidth("TEAM MONTGOMERY") <= t.winNameRoom then
				error("the long name fits display 32: the scenario does not test the fallback")
			end
			rcards.winner(card("Team Montgomery", SIX), "Team Montgomery toppled the king", true):draw(0, 0)
			ctx:capture()
		elseif ctx.frame == 2 then
			rcards.winner(card("Snow Kubbs", { SIX[1], SIX[2], SIX[3] }), "Snow Kubbs toppled the king", true):draw(0, 0)
			ctx:capture()
			return true
		end
		return false
	end,
}
