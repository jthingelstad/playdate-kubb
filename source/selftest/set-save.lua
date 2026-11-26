-- Scenario "set-save": saved data from before the kubb set left the Playdate
-- (Jamie's Settings sheet, 2026-11-20; docs/notes/match.md "Kubb sets").
-- A kept match options choice with SET on USA (core 0.9 has no SET row)
-- opens on five rows in PASS + PLAY (four and, since 1.1.0, THROW TO GO) with its other choices kept (core
-- matchopts.valid reads only its rows, so the set is dropped), every row is
-- stepped through, and the options it gives carry no set and no computer level
-- (frame 1); VS PLAYDATE adds COMPUTER, club unless chosen. A match saved in progress with set = "usa"
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
			local rows = options.rowsFor("match")
			for _ = 1, #rows do
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
			if #s.rows ~= 5 or s.rows[5].key ~= "togo" then error(#s.rows .. " rows shown") end   -- (1.1.0: THROW TO GO the fifth)
			for _, row in ipairs(s.rows) do
				if row.key == "set" or row.key == "computer" then error("the " .. row.label .. " row is shown") end
			end
			if s.row ~= 1 then error("down through every row ended on row " .. s.row) end
			if matchopts.value(s.choice, "surface") ~= "Sand" then error("the kept surface was lost") end
			local o = options.apply(s, {})
			if o.set ~= nil then error("the options gave the match a set: " .. tostring(o.set)) end
			if o.surface ~= "Sand" then error("the options lost the surface") end
			if o.computer ~= nil then error("PASS + PLAY gave a computer level") end
			-- VS PLAYDATE: COMPUTER is the sixth row (after THROW TO GO since 1.1.0), club unless chosen; right makes it pro
			local v = options.new(tw.input.scripted { { n = 1 }, { press = { "up" } }, { press = { "right" } } }, "vs",
				{ scripted = true })
			v.choice = matchopts.valid(kept)
			for _ = 1, 4 do options.update(v) end
			if #v.rows ~= 6 or v.rows[6].key ~= "computer" then error("VS PLAYDATE: no COMPUTER row last") end
			if matchopts.value(matchopts.valid(kept), "computer") ~= "club" then error("COMPUTER is not club by default") end
			local ov = options.apply(v, { vs = "B" })
			if ov.computer ~= "pro" then error("VS PLAYDATE: COMPUTER gave " .. tostring(ov.computer)) end
			ctx.note = "options: 5 rows, surface kept, no set; vs: COMPUTER row 6, pro"

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
