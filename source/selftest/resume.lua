-- Scenario "resume": a match saved in progress and resumed. A match is
-- driven through the engine to turn 3 (B's turn, a1 and a2 down); the match
-- scene saves it (scene.persist, playdate.datastore "match"); it is read
-- back through the datastore's JSON and resumed. Frame 1: the title with
-- its B RESUME line; frame 2: the resumed match's hand-off card. The check:
-- the resumed engine is at the same turn, phase and score sheet, and the
-- names came back. The save is deleted afterwards.
import "core/tw"
import "core/save"
import "core/match"
import "scenes/match"
import "scenes/title"
import "input"

local scene, title, cmatch, save = tw.scenes.match, tw.scenes.title, tw.match, tw.save
local MISS = {}

tw.selftest.scenarios.resume = {
	step = function(ctx)
		local f = ctx.frame
		if f == 1 then
			local names = { A = "Ash", B = "Birch" }
			local ms = scene.new(tw.input.scripted({}), { names = names, autoSettle = true })
			local g = ms.m.game
			g:throwBaton(MISS); g:throwBaton(MISS)
			g:throwBaton({ toppled = { "a1" } }); g:throwBaton({ toppled = { "a2" } }); g:throwBaton(MISS); g:throwBaton(MISS)
			scene.persist(ms)
			ctx.want = { turn = g.turn, phase = g.phase, line = tw.notation.turnLine(g.sheet.turns[2]) }
			local t = title.new(tw.input.scripted({}), "ASH V BIRCH, TURN " .. g.turn)
			title.enter()
			title.draw(t)
			ctx:capture()
			return false
		end
		if f == 2 then
			local d = playdate.datastore.read("match")
			local m, opts = save.unpack(d)
			if not m then error("no saved match") end
			local g = m.game
			if g.turn ~= ctx.want.turn or g.phase ~= ctx.want.phase then
				error(string.format("resumed at turn %s %s, saved at %s %s", g.turn, g.phase, ctx.want.turn, ctx.want.phase))
			end
			if tw.notation.turnLine(g.sheet.turns[2]) ~= ctx.want.line then error("score sheet differs") end
			if opts.names.B ~= "Birch" or g.teams.A.name ~= "Ash" then error("names lost") end
			ctx.ms = scene.new(tw.input.scripted({}), { names = opts.names, resume = m, autoSettle = true, noSave = true })
			scene.enter()
			if ctx.ms.setup.side ~= "A" then error("resumed with " .. tostring(ctx.ms.setup.side) .. " to throw") end
			scene.draw(ctx.ms)
			ctx:capture()
			playdate.datastore.delete("match")
			ctx.note = "turn " .. g.turn .. " " .. g.phase
			return true
		end
	end,
}
