-- Scenario "title": the title screen as it opens (VS PLAYDATE chosen), then
-- right twice to PRACTICE, then A, which must ask for the practice pitch.
-- Frames: 1 VS PLAYDATE chosen, 2 PRACTICE chosen, 3 a new player's title
-- (the HOW TO PLAY line), 4 a resume line with long team names cut to the
-- turn (title.resumeText). Every frame shows the version top right.
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
			if not tw.version or tw.version.text ~= tw.version.version .. " (" .. tw.engine.version .. ")" then error("no version text") end
			if playdate.metadata and playdate.metadata.version ~= tw.version.version then error("version " .. tw.version.version .. " is not pdxinfo's " .. tostring(playdate.metadata.version)) end
			if playdate.metadata and tonumber(playdate.metadata.buildNumber) ~= tw.version.build then error("build " .. tw.version.build .. " is not pdxinfo's " .. tostring(playdate.metadata.buildNumber)) end
			if s.choice ~= 1 or title.choices[1].id ~= "vs" then error("expected VS PLAYDATE first") end
			ctx:capture()
		elseif ctx.frame == 5 then
			if title.choices[s.choice].id ~= "practice" then error("right did not choose PRACTICE") end
			ctx:capture()
		elseif ctx.frame == 7 then
			if s.exit ~= "practice" then error("A chose " .. tostring(s.exit)) end
			title.draw(title.new(tw.input.scripted({}), nil, true))
			ctx:capture()
		elseif ctx.frame == 8 then
			local long = "TEAM MONTGOMERY V TEAM ALEXANDRA, TURN 12"
			if title.resumeText(long) ~= "RESUME TURN 12" then error("resume line " .. title.resumeText(long)) end
			if title.resumeText("ASH V BIRCH, TURN 7") ~= "RESUME ASH V BIRCH, TURN 7" then error("short resume line cut") end
			title.draw(title.new(tw.input.scripted({}), long, true))
			ctx:capture()
			return true
		end
		return false
	end,
}
