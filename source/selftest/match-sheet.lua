-- Scenario "match-sheet": the score sheet of a match in progress (System
-- Menu "Match: sheet", scenes/match.showSheet). A scripted match (seed 5,
-- each throw at rest at once) is played to turn 4; the sheet is asked for
-- and must open while Team B aims, with the game file so far (its turn
-- lines through turn 3, the current turn last), scrolled to its last line.
-- The crank scrolls it back up, the match waits under it (no throw), and B
-- goes back to the same throw, after which the match carries on. Frames: 1
-- the sheet at its end, 2 scrolled to the top.
import "selftest/_match"

local st = tw.selftest
local scene, sheet = tw.scenes.match, tw.scenes.sheet

local stage, at = 1, nil

st.scenarios["match-sheet"] = st.matchScenario {
	opts = { seed = 5, instant = true, skipHandoff = true, names = { A = "Ash", B = "Birch" } },
	refreshRate = 0,
	maxFrames = 6000,
	step = function(ms, ctx, h)
		local ts = ms.ts
		if stage == 1 then
			if ms.phase == "play" and ms.m.game.turn >= 4 and ts.mode == "aim" and ms.setup then
				scene.showSheet(ms)
				at = { throws = ms.throws, turn = ms.m.game.turn, label = ms.setup.label, frame = ctx.frame }
				stage = 2
			end
		elseif stage == 2 then
			local sh = ms.sheet
			if not sh then
				if ctx.frame > at.frame + 3 then error("the sheet did not open") end
				return false
			end
			local text = table.concat(sh.lines, "\n")
			if not text:find('%[Team A "Ash"%]') or not text:find('%[Team B "Birch"%]') then
				error("the sheet has no team headers")
			end
			if not text:find("\n3%. ") then error("the sheet has no turn 3 line") end
			if sh.title ~= "ASH V BIRCH" then error("rail " .. tostring(sh.title)) end
			sheet.draw(sh)   -- (builds the text, which puts it at its end)
			if sh.y <= 0 then error("the sheet did not open at its end") end
			at.y = sh.y
			ctx:capture()
			h.feed { { cranks = { -20, -20, -20, -20, -20, -20, -20, -20, -20, -20 } }, { n = 3 } }
			stage = 3
		elseif stage == 3 and h.idle() then
			if not ms.sheet or ms.sheet.y >= at.y then error("the crank did not scroll the sheet") end
			if ms.throws ~= at.throws then error("a throw was made under the sheet") end
			ctx:capture()
			h.feed { { press = { "b" } }, { n = 2 } }
			stage = 4
		elseif stage == 4 and h.idle() then
			if ms.sheet then error("B did not close the sheet") end
			if ms.m.game.turn ~= at.turn or ms.setup.label ~= at.label then
				error("the match moved on under the sheet: " .. ms.setup.label)
			end
			stage = 5
		elseif stage == 5 and ms.throws >= at.throws + 2 then
			ctx.note = ctx.note .. string.format(" turn=%d lines=%d", at.turn, #ms.m.game.sheet.turns)
			return true
		end
		return false
	end,
}
