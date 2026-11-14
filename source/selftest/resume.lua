-- Scenario "resume": a match saved in progress and resumed. A match is
-- driven through the engine to turn 3 (B's turn, a1 and a2 down); the match
-- scene saves it (scene.persist, playdate.datastore "match"); it is read
-- back through the datastore's JSON and resumed. Frame 1: the title with
-- its B RESUME line; frame 2: the resumed match's hand-off card. The check:
-- the resumed engine is at the same turn, phase and score sheet, and the
-- names came back. Self-test runs save under their own key
-- (scene.saveKey), so a player's saved match is never touched; that key is
-- deleted afterwards. Then a raise made by hand is saved at once: the match
-- is resumed at B's raise (turn 3), one kubb raised, and the save read back
-- must hold it.
import "core/tw"
import "core/save"
import "core/match"
import "core/names"
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
			local d = playdate.datastore.read(scene.saveKey())
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
			playdate.datastore.delete(scene.saveKey())
			ctx.note = "turn " .. g.turn .. " " .. g.phase
			return false
		end
		if f == 3 then
			-- B's raise at turn 3, by hand: A tossed a1 and a2 in, lying
			local m = cmatch.new { start = { year = 2026, month = 11, day = 13, hour = 21, min = 0 },
				teams = tw.names.teams { A = "Ash", B = "Birch" } }
			local g = m.game
			g:throwBaton(MISS); g:throwBaton(MISS)
			g:throwBaton({ toppled = { "a1" } }); g:throwBaton({ toppled = { "a2" } }); g:throwBaton(MISS); g:throwBaton(MISS)
			g:toss({ rest = { x = 0.5, y = 6.0, standing = false, angle = 0.4 }, moved = {} })
			g:toss({ rest = { x = -0.8, y = 5.5, standing = false, angle = 1.2 }, moved = {} })
			if g.phase ~= "raise" then error("expected B's raise, got " .. g.phase) end
			ctx.ms2 = scene.new(tw.input.scripted { { n = 2 }, { press = { "a" } }, { n = 4 } },
				{ names = { A = "Ash", B = "Birch" }, resume = m })
			if ctx.ms2.phase ~= "settle" then error("resumed into " .. ctx.ms2.phase .. ", not the raise") end
			ctx.first = ctx.ms2.settle.kubb
			return false
		end
		if f > 3 then
			scene.update(ctx.ms2)
			if ctx.ms2.settle and ctx.ms2.settle.raised >= 1 then
				local m = save.unpack(playdate.datastore.read(scene.saveKey()))
				if not m then error("nothing saved after the raise") end
				local k = m.game.kubbs[ctx.first]
				if not (k and k.pose.standing) then error(ctx.first .. " raised by hand was not saved standing") end
				playdate.datastore.delete(scene.saveKey())
				ctx.note = ctx.note .. "; raise saved (" .. ctx.first .. ")"
				return true
			end
			if f > 30 then error("the raise was not made") end
			return false
		end
	end,
}
