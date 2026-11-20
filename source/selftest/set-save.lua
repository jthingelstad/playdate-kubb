-- Scenario "set-save": saved data from before the kubb set left the Playdate
-- (Jamie's Settings sheet, 2026-11-20; docs/notes/match.md "Kubb sets").
-- A kept match options choice with SET on USA opens on four rows (no SET),
-- every row stepped through keeps its set as it was, and the options it
-- gives carry no set (frame 1). A match saved in progress with set = "usa"
-- reads back and resumes (frame 2, its hand-off card), draws the pitch
-- (frame 3), saves again with the set it carried untouched, and plays to
-- its end: the team on turn resigns and the game file is written; the
-- marker names it (file=...), so make selftest gates its header and play.
-- Self-test keys only (selftest-match), deleted afterwards.
import "core/tw"
import "core/save"
import "core/match"
import "core/matchopts"
import "core/names"
import "scenes/match"
import "scenes/options"
import "input"

local scene, options, cmatch, save, matchopts = tw.scenes.match, tw.scenes.options, tw.match, tw.save, tw.matchopts
local MISS = {}

tw.selftest.scenarios["set-save"] = {
	step = function(ctx)
		local f = ctx.frame
		if f == 1 then
			-- the options a build with SET kept: USA
			local kept = { surface = 2, opening = 1, raising = 1, set = 2, wind = 1 }
			-- down through every row and back to the first, left/right on each
			local steps = { { n = 1 } }
			for _ = 1, #options.rows do
				steps[#steps + 1] = { press = { "right" } }
				steps[#steps + 1] = { press = { "left" } }
				steps[#steps + 1] = { press = { "down" } }
			end
			local s = options.new(tw.input.scripted(steps), "match", { scripted = true })
			s.choice = matchopts.valid(kept)
			options.enter()
			for _ = 1, #steps + 1 do options.update(s) end
			options.draw(s)
			ctx:capture()
			if #options.rows ~= #matchopts.list - 1 then error(#options.rows .. " rows shown") end
			for _, row in ipairs(options.rows) do
				if row.key == "set" then error("the SET row is shown") end
			end
			if s.row ~= 1 then error("down through every row ended on row " .. s.row) end
			if s.choice.set ~= 2 then error("the kept set was changed to " .. tostring(s.choice.set)) end
			if matchopts.value(s.choice, "surface") ~= "Sand" then error("the kept surface was lost") end
			local o = options.apply(s, {})
			if o.set ~= nil then error("the options gave the match a set: " .. tostring(o.set)) end
			if o.surface ~= "Sand" then error("the options lost the surface") end
			ctx.note = "options: 4 rows, kept set 2 untouched"

			-- a match saved in progress with a set, as a build with SET wrote it
			local m = cmatch.new { start = { year = 2026, month = 11, day = 20, hour = 22, min = 10 },
				teams = tw.names.teams { A = "Ash", B = "Birch" } }
			m.game:throwBaton(MISS); m.game:throwBaton(MISS)
			tw.save.write(m, { names = { A = "Ash", B = "Birch" }, set = "usa", wind = "off" },
				function(d) playdate.datastore.write(d, scene.saveKey()) end)
			return false
		end
		if f == 2 then
			-- read back as main.lua's resume does, its options passed on as they are
			local r, opts = save.unpack(playdate.datastore.read(scene.saveKey()))
			if not r then error("the save with a set did not read back: " .. tostring(opts)) end
			if opts.set ~= "usa" then error("the save's set read back as " .. tostring(opts.set)) end
			ctx.ms = scene.new(tw.input.scripted { { n = 3 }, { press = { "a" } }, { n = 400 } },
				{ names = opts.names, set = opts.set, wind = opts.wind, resume = r })
			scene.enter()
			if ctx.ms.phase ~= "handoff" then error("resumed into " .. ctx.ms.phase) end
			scene.draw(ctx.ms)
			ctx:capture()
			return false
		end
		local ms = ctx.ms
		scene.update(ms)
		scene.draw(ms)
		if f == 8 then
			if ms.phase ~= "play" then error("not playing after the hand-off: " .. ms.phase) end
			ctx:capture()
			-- saved again: the set it carried is still there
			scene.persist(ms)
			local _, o = save.unpack(playdate.datastore.read(scene.saveKey()))
			if not o or o.set ~= "usa" then error("the save dropped or changed the set") end
			scene.resign(ms)
		end
		if ms.phase == "over" then
			if not ms.file then error("no game file: " .. tostring(ms.fileError)) end
			if playdate.datastore.read(scene.saveKey()) then error("the finished match left its save") end
			ctx.note = ctx.note .. "; resumed with set usa, played, resigned: file=" .. ms.file
			return true
		end
		if f > 60 then error("not over by frame 60 (" .. ms.phase .. ")") end
		return false
	end,
}
