-- Scenario "cards-fit": the winner card with names that used to run off it
-- (the RC review of 2026-11-15), now generated names of up to 16 letters (game
-- 0.12.0). Frames: 1 a team name too wide for display 32 beside the burst
-- ("REDWOOD HAMMOCKS", drawn in display 16) and six players with the longest
-- player names (packed by width, two lines), 2 a name that still fits display 32
-- ("THE KINGS").
import "core/tw"
import "render/cards"
import "render/ui"

local rcards, ui = tw.render.cards, tw.render.ui

local function card(name, players)
	return { winnerName = name, turns = 24, minutes = 31, thrown = 60, hits = 25, players = players }
end

local SIX = {
	{ name = "Northern Redwood", hits = 22, thrown = 29 }, { name = "Agreeable Ginkgo", hits = 15, thrown = 28 },
	{ name = "Zealous Tamarack", hits = 9, thrown = 12 }, { name = "Agreeable Baobab", hits = 11, thrown = 20 },
	{ name = "Mighty Maple", hits = 3, thrown = 9 }, { name = "Lucky Larch", hits = 18, thrown = 30 },
}

tw.selftest.scenarios["cards-fit"] = {
	step = function(ctx)
		if ctx.frame == 1 then
			local t = rcards.tune
			if ui.display(32):getTextWidth("REDWOOD HAMMOCKS") <= t.winNameRoom then
				error("the long name fits display 32: the scenario does not test the fallback")
			end
			rcards.winner(card("Redwood Hammocks", SIX), "Redwood Hammocks toppled the king", true):draw(0, 0)
			ctx:capture()
		elseif ctx.frame == 2 then
			rcards.winner(card("The Kings", { SIX[1], SIX[2], SIX[3] }), "The Kings toppled the king", true):draw(0, 0)
			ctx:capture()
			return true
		end
		return false
	end,
}
