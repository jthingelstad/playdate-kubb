-- Scenario "names": the names screen for PASS + PLAY without the keyboard
-- (scripted): frame 1 the first team as typed ("ASH"), 2 the second team
-- with a long name (drawn at cap 16), then OK twice; a name with no letter is
-- refused, and B from the second step goes back to the first. The check: the
-- names given are the match's teams, and the game file id is shown.
import "core/tw"
import "scenes/names"
import "scenes/match"
import "input"

local names = tw.scenes.names
local s

tw.selftest.scenarios.names = {
	step = function(ctx)
		if not s then
			s = names.new(tw.input.scripted({}), "match", { scripted = true })
			names.enter(s)
		end
		names.update(s)
		local f = ctx.frame
		if f == 2 then names.type(s, "Ash!") end
		if f == 3 then
			if s.text ~= "Ash" then error("typed text " .. s.text) end
			names.draw(s); ctx:capture()
			if not names.ok(s) then error("Ash refused") end
		end
		if f == 5 then
			names.back(s)
			if s.i ~= 1 then error("B did not go back") end
		end
		if f == 6 then
			if s.text ~= "Ash" then error("back showed " .. s.text) end
			names.ok(s)
		end
		if f == 8 then
			names.type(s, "--")
			if names.ok(s) then error("a name with no letter was taken") end
			names.type(s, "Birch Grove Kubb")
			names.draw(s); ctx:capture()
			if s.text ~= "Birch Grov" then error("cut to " .. s.text) end
			names.ok(s)
		end
		if f == 9 then
			if not s.done then error("not done after two names") end
			if s.list.A ~= "Ash" or s.list.B ~= "Birch Grov" then error("names " .. s.list.A .. ", " .. s.list.B) end
			local ms = tw.scenes.match.new(tw.input.scripted({}), { names = s.list, seed = 1, instant = true })
			local g = ms.m.game
			if g.teams.A.name ~= "Ash" or g.teams.B.players[1].id ~= "birch_grov" then error("match teams") end
			return true
		end
		names.draw(s)
		return false
	end,
}
