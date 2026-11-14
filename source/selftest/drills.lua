-- Scenario "drills": the drills menu and a whole run (scenes/drills). Down
-- three times to KING SHOTS (frame 1: the menu on it), A starts; each throw is
-- a straight baton at the king (throw.autoLaunch) shown at rest at once.
-- Frame 2: the result card; B back to the menu (frame 3: its BEST and LAST
-- TEN). The check: six throws were tallied, the record holds the run, and a
-- second run left part way (scene.quit) goes back to the menu unrecorded.
import "core/tw"
import "core/autothrow"
import "scenes/drills"
import "input"

local scene = tw.scenes.drills
local s, launched = nil, 0

tw.selftest.scenarios.drills = {
	step = function(ctx)
		local f = ctx.frame
		if not s then
			s = scene.new(tw.input.scripted {
				{ n = 1 }, { press = { "down" } }, { n = 1 }, { press = { "down" } }, { n = 1 }, { press = { "down" } },
				{ n = 2 }, { press = { "a" } }, { n = 4000 },
			}, { scripted = true })
			scene.enter()
		end
		if s.phase == "run" then
			local ts = s.ts
			ts.instant = true
			if ts.mode == "aim" then
				ts.input:advance()
				launched = launched + 1

				tw.scenes.throw.autoLaunch(ts, { x = 0, y = 0, swivel = 0, loftDeg = 30,
					speed = tw.autothrow.speedFor(4, 30), tumbleRate = 5.5, tilt = 0 })
			end
		end
		scene.update(s)
		scene.draw(s)
		if f == 8 then
			if s.items[s.choice].id ~= "king" then error("down three times chose " .. s.items[s.choice].id) end
			ctx:capture()
		end
		if s.phase == "result" and not ctx.done1 then
			ctx.done1 = true
			if s.run.n ~= 6 then error("throws tallied " .. s.run.n) end
			ctx:capture()
			s.phase, s.img = "menu", nil
			ctx.note = string.format("king %d/6 launched %d", s.run.score, launched)
		elseif ctx.done1 then
			local r = s.records.king
			if not r or r.runs ~= 1 or r.best ~= s.run.score then error("record") end
			-- the System Menu's "Drill: menu" leaves a run part way, unrecorded
			scene.startRun(s, s.drill)
			scene.quit(s)
			if s.phase ~= "menu" or s.records.king.runs ~= 1 then error("quit: " .. s.phase) end
			scene.draw(s)
			ctx:capture()
			return true
		end
		if f > 3000 then error("no result by frame 3000 (" .. s.phase .. ", " .. tostring(s.ts and s.ts.mode) .. ")") end
		return false
	end,
}
