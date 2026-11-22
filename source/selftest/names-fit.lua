-- Scenario "names-fit": every generated name (core/namegen.all, both kinds) measured
-- in the game's own faces, before the Playdate shows 16-letter names (kubb-engine
-- docs/NAMES.md 8.3: "each client measures its widest name in its own font"). The
-- widest of each kind in the label face, display 16 and display 32 go in the note.
-- Frames: 1 the rail of a match throw with the widest player name, 2 the hand-off card
-- with the widest team name, 3 the hand-off card with the widest typed name (the
-- owner, 2026-11-22: typed names on the Playdate), 4 its rail.
-- The check: in the label face (every place's last fallback) each name fits the
-- rail's room before the pips, the TEAMS column, the PLAYERS list and the Names
-- screen's panel.
import "core/tw"
import "core/namegen"
import "render/ui"
import "render/hud"
import "render/cards"
import "scenes/teams"
import "scenes/players"
import "scenes/names"
import "core/match"
import "core/cards"

local namegen, ui, hud = tw.namegen, tw.render.ui, tw.render.hud
local gfx <const> = playdate.graphics

local widest = {}

local function measure(kind)
	local fonts = { label = ui.label(), d16 = ui.display(16), d32 = ui.display(32) }
	local out = {}
	for _, n in ipairs(namegen.all(kind)) do
		local up = string.upper(n)
		for k, f in pairs(fonts) do
			local w = f:getTextWidth(up)
			if not out[k] or w > out[k].w then out[k] = { w = w, name = n } end
		end
	end
	return out
end

tw.selftest.scenarios["names-fit"] = {
	step = function(ctx)
		if ctx.frame == 1 then
			widest.player, widest.team = measure("player"), measure("team")
			local rooms = {
				rail = hud.railRoom("baton", 6),
				railKubbs = hud.railRoom("kubb", 5),
				teams = tw.scenes.teams.tune.colW - 14,
				players = tw.scenes.players.tune.panelW - 30,
				names = tw.scenes.names.tune.panelW - 2 * tw.scenes.names.tune.x,
			}
			local notes = {}
			for _, kind in ipairs { "player", "team" } do
				local w = widest[kind]
				notes[#notes + 1] = string.format("%s:label=%d(%s),d16=%d,d32=%d", kind, w.label.w,
					w.label.name:gsub(" ", "_"), w.d16.w, w.d32.w)
				for place, room in pairs(rooms) do
					local lw = w.label.w
					-- the rail shows a team's name only when it fits, else who throws (scenes/match
					-- railName), and the PLAYERS list holds players only
					if kind == "team" and (place == "rail" or place == "railKubbs" or place == "players") then lw = 0 end
					-- TEAMS cuts the first word to its initial when the whole name is too wide
					if place == "teams" then
						for _, n in ipairs(namegen.all(kind)) do
							local cut = tw.scenes.teams.fitName(n, room)
							local cw = ui.label():getTextWidth(string.upper(cut))
							if cw > room then error(string.format("TEAMS: %q is %d px cut, %d room", cut, cw, room)) end
						end
						lw = 0
					end
					if lw > room then
						error(string.format("%s %q is %d px in the label face; %s has %d", kind, w.label.name, w.label.w, place, room))
					end
				end
			end
			-- typed names (the owner, 2026-11-22): the widest the Names screen allows,
			-- typedMax letters of the widest capitals, with a space and the marks it takes
			local tm = tw.scenes.names.tune.typedMax
			local label, d16 = ui.label(), ui.display(16)
			local typedRooms = {
				rail = rooms.rail, railKubbs = rooms.railKubbs, players = rooms.players,
				names = rooms.names, winner = tw.render.cards.tune.winNameRoom, cards = tw.render.cards.tune.nameRoom,
			}
			local widestTyped, ww = nil, 0
			for _, base in ipairs { string.rep("W", tm), string.rep("M", tm), "WWWW WWWWW", "W'WWW-WWWW" } do
				local t = tw.scenes.names.clean(base)
				if #t ~= tm then error("typed " .. base .. " cleaned to " .. t) end
				local w = label:getTextWidth(string.upper(t))
				if w > ww then widestTyped, ww = t, w end
				for place, room in pairs(typedRooms) do
					if w > room then error(string.format("typed %q is %d px in the label face; %s has %d", t, w, place, room)) end
				end
				local cut = tw.scenes.teams.fitName("2 " .. t, rooms.teams)
				local cw = label:getTextWidth(string.upper(cut))
				if cw > rooms.teams then error(string.format("TEAMS: typed %q is %d px, %d room", cut, cw, rooms.teams)) end
				widest.typedCut = widest.typedCut or {}
				if cut ~= "2 " .. t then widest.typedCut[#widest.typedCut + 1] = cut end
			end
			widest.typed = widestTyped
			notes[#notes + 1] = string.format("typed:label=%d(%s),d16=%d", ww, widestTyped:gsub(" ", "_"),
				d16:getTextWidth(string.upper(widestTyped)))
			if widest.typedCut and #widest.typedCut > 0 then
				notes[#notes + 1] = "teamsCut=" .. table.concat(widest.typedCut, "|"):gsub(" ", "_")
			end
			ctx.note = table.concat(notes, " ") .. string.format(" rail=%d teams=%d", rooms.rail, rooms.teams)
			hud.rail(string.upper(widest.player.label.name), "baton", 3, 6, "FIELD 2", "BASE 3")
			ctx:capture()
		elseif ctx.frame == 2 then
			local name = widest.team.d32.name
			local m = tw.match.new { start = { year = 2026, month = 11, day = 22, hour = 12, min = 0 },
				teams = { A = { name = name, players = { { name = widest.player.d32.name } } },
					B = { name = "Playdate", players = { { name = "Playdate" } } } },
				mode = "Vs Playdate", cpu = { "B" }, rules = "kid" }
			local setup = tw.match.setup(m)
			local c = tw.cards.handoff(m, setup)
			c.kid = true
			tw.render.cards.handoff(c):draw(0, 0)
			ctx:capture()
		elseif ctx.frame == 3 then
			-- the widest typed name as a team of one: the hand-off card, then its rail
			local t = widest.typed
			local m = tw.match.new { start = { year = 2026, month = 11, day = 22, hour = 12, min = 0 },
				teams = { A = { name = t, players = { { name = t } } },
					B = { name = "Playdate", players = { { name = "Playdate" } } } },
				mode = "Vs Playdate", cpu = { "B" } }
			local c = tw.cards.handoff(m, tw.match.setup(m))
			tw.render.cards.handoff(c):draw(0, 0)
			ctx:capture()
		elseif ctx.frame == 4 then
			gfx.clear(gfx.kColorWhite)
			hud.rail(string.upper(widest.typed), "baton", 3, 6, "FIELD 2", "BASE 3")
			ctx:capture()
			return true
		end
		return false
	end,
}
