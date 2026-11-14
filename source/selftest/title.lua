-- Scenario "title": the title screen as it opens (VS PLAYDATE chosen), then
-- right twice to PRACTICE, then A, which must ask for the practice pitch.
-- Frames: 1 VS PLAYDATE chosen, 2 PRACTICE chosen.
import "core/tw"
import "scenes/title"
import "input"

local title = tw.scenes.title
local s

tw.selftest.scenarios.title = {
	step = function(ctx)
		if not s then
			s = title.new(tw.input.scripted { { n = 2 }, { press = { "right" } }, { n = 1 }, { press = { "right" } }, { press = { "a" } }, { n = 2 } })
			title.enter()
		end
		title.update(s)
		title.draw(s)
		if ctx.frame == 2 then
			if s.choice ~= 1 or title.choices[1].id ~= "vs" then error("expected VS PLAYDATE first") end
			ctx:capture()
		elseif ctx.frame == 5 then
			if title.choices[s.choice].id ~= "practice" then error("right did not choose PRACTICE") end
			ctx:capture()
		elseif ctx.frame >= 7 then
			if s.exit ~= "practice" then error("A chose " .. tostring(s.exit)) end
			return true
		end
		return false
	end,
}
