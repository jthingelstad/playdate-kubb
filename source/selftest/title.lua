-- Scenario "title": the title screen as it opens (PASS + PLAY chosen), then
-- right to PRACTICE, then A, which must ask for the practice pitch.
-- Frames: 1 PASS + PLAY chosen, 2 PRACTICE chosen.
import "core/tw"
import "scenes/title"
import "input"

local title = tw.scenes.title
local s

tw.selftest.scenarios.title = {
	step = function(ctx)
		if not s then
			s = title.new(tw.input.scripted { { n = 2 }, { press = { "right" } }, { n = 2 }, { press = { "a" } }, { n = 2 } })
			title.enter()
		end
		title.update(s)
		title.draw(s)
		if ctx.frame == 2 then
			if s.choice ~= 1 or title.choices[1].id ~= "match" then error("expected PASS + PLAY first") end
			ctx:capture()
		elseif ctx.frame == 4 then
			if title.choices[s.choice].id ~= "practice" then error("right did not choose PRACTICE") end
			ctx:capture()
		elseif ctx.frame >= 6 then
			if s.exit ~= "practice" then error("A chose " .. tostring(s.exit)) end
			return true
		end
		return false
	end,
}
