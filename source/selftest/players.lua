-- Scenario "players": the PLAYERS screens (scenes/players) driven by hand,
-- the Names screen scripted (generated names, scenes/names). From an empty
-- self-test roster: Lucky Larch made (+ NEW PLAYER, straight to their page,
-- which has no LEVEL row since engine 0.13), Mighty Maple and Agreeable Ginkgo
-- (16 letters, the longest) made, a second Lucky Larch refused as taken, Mighty
-- Maple renamed Jolly Juniper, then removed. Then a roster saved by 0.11.0 with
-- typed names (oloF, Playdate, Greta, Montgomery) loads unchanged and is not
-- rewritten (the owner, 2026-11-21: "Saved players keep their typed names until
-- someone renames them."), plays a scripted match with those names on its sheet, and
-- only Montgomery's rename (a generated name) changes one.
-- Frames: 1 the Names step with Lucky Larch refused, 2 the list (Lucky Larch
-- chosen), 3 their page, 4 the remove card, 5 the list of typed names. The check:
-- the roster saved and read back has Lucky Larch and Agreeable Ginkgo and no Jolly
-- Juniper, the scene went to the title on B, and the typed names as above.
import "core/tw"
import "scenes/players"
import "scenes/names"
import "players"
import "core/history"
import "core/namegen"
import "core/roster"
import "core/lineup"
import "core/match"
import "scenes/match"
import "input"

local scene, names, players = tw.scenes.players, tw.scenes.names, tw.players

-- An input provider pressed by the scenario: press(name) for the next frame.
local function manual()
	local p = { want = nil, now = nil }
	function p:advance() self.now, self.want = self.want, nil end
	function p:pressed(name) return self.now == name end
	function p:held(name) return self.now == name end
	function p:crank() return 0 end
	function p:crankPos() return 180 end
	function p:docked() return false end
	function p:dt() return 1 / 30 end
	return p
end

local s, inp
local script = nil

local function names_(list) local out = {} for i, p in ipairs(list) do out[i] = p.name end return table.concat(out, ",") end

tw.selftest.scenarios.players = {
	step = function(ctx)
		if not s then
			playdate.datastore.delete(players.fileKey("players"))
			inp = manual()
			s = scene.new(inp, { scripted = true })
			scene.enter()
			-- one action a frame; a function may return an error string
			script = {
				function() inp.want = "a" end,                          -- + NEW PLAYER
				function() if s.mode ~= "name" then return "no Names step" end names.set(s.sub, "Lucky Larch"); names.ok(s.sub) end,
				function() if s.mode ~= "player" or s.row ~= 1 then return "not on Lucky Larch's page" end inp.want = "b" end,
				function() inp.want = "up" end,                         -- + NEW PLAYER
				function() if s.choice ~= 1 then return "choice " .. s.choice end inp.want = "a" end,
				function() names.set(s.sub, "Mighty Maple"); names.ok(s.sub) end,
				function() inp.want = "b" end,
				function() s.choice = 1; s.img = nil; inp.want = "a" end,
				function() names.set(s.sub, "Agreeable Ginkgo"); names.ok(s.sub) end,   -- 16 letters
				function() inp.want = "b" end,
				function() s.choice = 1; s.img = nil; inp.want = "a" end,
				function()
					names.set(s.sub, "Lucky Larch")
					if names.ok(s.sub) then return "a second Lucky Larch was taken" end
					if s.sub.why ~= "taken" then return "why " .. tostring(s.sub.why) end
				end,
				"capture3",
				function() names.back(s.sub) end,
				function() if s.mode ~= "list" then return "back from the keyboard: " .. s.mode end
					if names_(s.list) ~= "Agreeable Ginkgo,Lucky Larch,Mighty Maple" then return "list " .. names_(s.list) end
					s.choice = 3; s.img = nil end,                     -- Lucky Larch
				"capture1",
				function() inp.want = "a" end,
				"capture2",
				-- GAMES: a recent game whose file is not here opens its sheet, and B comes back
				function()
					s.hs[s.player.key] = s.hs[s.player.key] or tw.history.new()
					s.hs[s.player.key].games[1] = { d = "2026-11-15 10:00", f = "none.txt", team = "Lucky Larch",
						vs = "Mighty Maple", res = "won", b = 6, h = 3 }
					inp.want = "down"
				end,
				function() if s.row ~= 2 then return "not on GAMES" end inp.want = "a" end,
				function() if s.mode ~= "games" then return "no games list" end inp.want = "a" end,
				function() if s.mode ~= "sheet" then return "no score sheet" end inp.want = "b" end,
				function() if s.mode ~= "games" then return "B left the sheet for " .. s.mode end inp.want = "b" end,
				function() if s.mode ~= "player" then return "B left the games for " .. s.mode end inp.want = "b" end,
				function() s.choice = 4; s.img = nil; inp.want = "a" end, -- Mighty Maple
				function() inp.want = "a" end,                          -- NAME: rename
				function() if names.text(s.sub) ~= "Mighty Maple" then return "rename starts on " .. names.text(s.sub) end
					names.set(s.sub, "Jolly Juniper"); names.ok(s.sub) end,
				function() if s.player.name ~= "Jolly Juniper" then return "rename gave " .. s.player.name end
					inp.want = "up" end,                                -- REMOVE (wraps)
				function() if s.row ~= 3 then return "row " .. s.row end inp.want = "a" end,
				"capture4",
				function() if s.mode ~= "confirm" then return "no remove card" end inp.want = "a" end,
				function()
					local back = tw.roster.valid(playdate.datastore.read(players.fileKey("players")))
					if names_(back.players) ~= "Lucky Larch,Agreeable Ginkgo" then return "saved roster " .. names_(back.players) end
					inp.want = "b"
				end,
				function() if s.exit ~= "title" then return "B went to " .. tostring(s.exit) end
					-- a roster saved by 0.11.0 with typed names (the owner, 2026-11-21: "Saved players
					-- keep their typed names until someone renames them."): loaded unchanged
					local old = tw.roster.new()
					tw.roster.add(old, "oloF", "club", "2026-11-01")
					tw.roster.add(old, "Playdate", nil, "2026-11-01")
					tw.roster.add(old, "Greta", "pro", "2026-11-01")
					tw.roster.add(old, "Montgomery", nil, "2026-11-01")
					playdate.datastore.write(old, players.fileKey("players"))
					local before = json.encode(playdate.datastore.read(players.fileKey("players")))
					local r1 = players.load()
					players.load()
					if names_(r1.players) ~= "oloF,Playdate,Greta,Montgomery" then return "load changed names: " .. names_(r1.players) end
					if json.encode(playdate.datastore.read(players.fileKey("players"))) ~= before then return "load rewrote the roster" end
					-- PLAYERS shows them as they are
					s = scene.new(inp, { scripted = true })
					s.choice = 2; s.img = nil
				end,
				"capture5",
				function()
					-- a match with those names: on the sheet as typed
					local L = tw.lineup.new(false)
					local r = players.load()
					tw.lineup.add(L, "A", tw.lineup.entry(r.players[1]))
					tw.lineup.add(L, "B", tw.lineup.entry(r.players[3]))
					tw.lineup.add(L, "B", tw.lineup.entry(r.players[4]))
					local ms = tw.scenes.match.new(tw.input.scripted({}), { teams = tw.lineup.teams(L), seed = 3, instant = true,
						skipHandoff = true, maxTurns = 4 })
					for _ = 1, 4000 do
						if ms.phase == "over" then break end
						tw.scenes.match.update(ms)
					end
					if ms.phase ~= "over" then return "the match did not end" end
					local text = tw.match.file(ms.m, nil, "0.0.1")
					if not text:find('[Team A "oloF"]', 1, true) then return "the sheet's Team A" end
					local bp = text:match('%[Team B Players "([^"]*)"%]') or ""
					if not (bp:find("Greta", 1, true) and bp:find("Montgomery", 1, true)) then return "the sheet's Team B players: " .. bp end
					ctx.note = (ctx.note or "") .. " sheet=" .. bp:gsub(" ", "_")
					s.img = nil
				end,
				-- only a rename changes one: Montgomery's NAME row gives a generated name
				function()
					for i, p in ipairs(s.list) do if p.name == "Montgomery" then s.choice = i + 1 end end
					s.img = nil; inp.want = "a"
				end,
				function()
					if s.mode ~= "player" then return "no player page" end
					s.renamedKey = s.player.key
					inp.want = "a"
				end,
				function()
					if s.mode ~= "name" then return "no Names screen" end
					if names.text(s.sub) == s.player.name then return "the rename offered the typed name" end
					names.ok(s.sub)
				end,
				function()
					local r = tw.roster.valid(playdate.datastore.read(players.fileKey("players")))
					local renamed
					for _, p in ipairs(r.players) do if p.key == s.renamedKey then renamed = p end end
					if not renamed or not tw.namegen.valid("player", renamed.name) then return "the rename gave " .. tostring(renamed and renamed.name) end
					local others = {}
					for _, p in ipairs(r.players) do if p.key ~= s.renamedKey then others[#others + 1] = p.name end end
					if table.concat(others, ",") ~= "oloF,Playdate,Greta" then
						return "others changed: " .. table.concat(others, ",")
					end
					ctx.note = ctx.note .. " renamed=" .. renamed.name:gsub(" ", "_")
				end,
			}
		end
		local a = table.remove(script, 1)
		if type(a) == "string" then
			scene.draw(s)
			ctx:capture()
			return false
		end
		if a then
			local err = a()
			if err then error(err) end
		end
		scene.update(s)
		scene.draw(s)
		if #script == 0 then
			playdate.datastore.delete(players.fileKey("players"))
			playdate.datastore.delete(players.fileKey("player-p1"))
			return true
		end
		return false
	end,
}
