-- Scenario "players": the PLAYERS screens (scenes/players) driven by hand,
-- the keyboard scripted. From an empty self-test roster: Kim made (+ NEW
-- PLAYER, typed, straight to LEVEL, right: pro), Max and Montgomery (a long
-- name beside its level) made, a "kim" refused as taken, Max renamed to
-- Maxine, then removed.
-- Frames: 1 the keyboard step with "kim" refused, 2 the list (Kim chosen),
-- 3 Kim's page on LEVEL, 4 the remove card. The check: the roster saved
-- and read back has Kim at pro and no Maxine, and the scene went to the
-- title on B.
import "core/tw"
import "scenes/players"
import "scenes/names"
import "players"
import "core/history"

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
				function() if s.mode ~= "name" then return "no keyboard step" end names.type(s.sub, "Kim"); names.ok(s.sub) end,
				function() if s.mode ~= "player" or s.row ~= 2 then return "not on Kim's LEVEL" end inp.want = "right" end,
				function() if s.player.level ~= "pro" then return "level " .. s.player.level end inp.want = "b" end,
				function() inp.want = "up" end,                         -- + NEW PLAYER
				function() if s.choice ~= 1 then return "choice " .. s.choice end inp.want = "a" end,
				function() names.type(s.sub, "Max"); names.ok(s.sub) end,
				function() inp.want = "b" end,
				function() s.choice = 1; s.img = nil; inp.want = "a" end,
				function() names.type(s.sub, "Montgomery"); names.ok(s.sub) end,   -- a long name beside its level
				function() inp.want = "b" end,
				function() s.choice = 1; s.img = nil; inp.want = "a" end,
				function()
					names.type(s.sub, "kim")
					if names.ok(s.sub) then return "a second kim was taken" end
					if s.sub.why ~= "taken" then return "why " .. tostring(s.sub.why) end
				end,
				"capture3",
				function() names.back(s.sub) end,
				function() if s.mode ~= "list" then return "back from the keyboard: " .. s.mode end
					if names_(s.list) ~= "Kim,Max,Montgomery" then return "list " .. names_(s.list) end
					s.choice = 2; s.img = nil end,                     -- Kim
				"capture1",
				function() inp.want = "a" end,
				function() inp.want = "down" end,                       -- LEVEL
				"capture2",
				-- GAMES: a recent game whose file is not here opens its sheet, and B comes back
				function()
					s.hs[s.player.key] = s.hs[s.player.key] or tw.history.new()
					s.hs[s.player.key].games[1] = { d = "2026-11-15 10:00", f = "none.txt", team = "Kim", vs = "Max",
						res = "won", b = 6, h = 3 }
					inp.want = "down"
				end,
				function() if s.row ~= 3 then return "not on GAMES" end inp.want = "a" end,
				function() if s.mode ~= "games" then return "no games list" end inp.want = "a" end,
				function() if s.mode ~= "sheet" then return "no score sheet" end inp.want = "b" end,
				function() if s.mode ~= "games" then return "B left the sheet for " .. s.mode end inp.want = "b" end,
				function() if s.mode ~= "player" then return "B left the games for " .. s.mode end inp.want = "b" end,
				function() s.choice = 3; s.img = nil; inp.want = "a" end, -- Max
				function() inp.want = "a" end,                          -- NAME: rename
				function() names.type(s.sub, "Maxine"); names.ok(s.sub) end,
				function() if s.player.name ~= "Maxine" then return "rename gave " .. s.player.name end
					inp.want = "up" end,                                -- REMOVE (wraps)
				function() if s.row ~= 4 then return "row " .. s.row end inp.want = "a" end,
				"capture4",
				function() if s.mode ~= "confirm" then return "no remove card" end inp.want = "a" end,
				function()
					local back = tw.roster.valid(playdate.datastore.read(players.fileKey("players")))
					if names_(back.players) ~= "Kim,Montgomery" then return "saved roster " .. names_(back.players) end
					if back.players[1].level ~= "pro" then return "Kim saved at " .. back.players[1].level end
					inp.want = "b"
				end,
				function() if s.exit ~= "title" then return "B went to " .. tostring(s.exit) end end,
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
