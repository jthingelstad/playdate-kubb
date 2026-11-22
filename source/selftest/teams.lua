-- Scenario "teams": the TEAMS screen (scenes/teams) for PASS + PLAY, the
-- Names screen scripted, over a roster of five generated names (Agreeable Ginkgo,
-- Brave Birch, Jolly Juniper, Lucky Larch, Mighty Maple). The first three are sent
-- left to Team A, the last two right to Team B; Brave Birch is moved to the top of
-- Team A's order (hold A + up); Team A is named Wobbly Towers (a generated team
-- name); START. Frames: 1 the teams built, 2 the team's Names screen, 3 Team A in
-- its new order with its name. The check: the teams given are
-- core/match's (3 and 2 players, in that order) and a match starts with
-- them.
import "core/tw"
import "core/roster"
import "scenes/teams"
import "scenes/names"
import "scenes/match"

local scene, names = tw.scenes.teams, tw.scenes.names

-- An input provider the scenario presses: p.press and p.hold for the next frame.
local function manual()
	local p = { press = nil, hold = nil }
	function p:advance() self.nowPress, self.nowHold, self.press, self.hold = self.press, self.hold, nil, nil end
	function p:pressed(name) return self.nowPress == name end
	function p:held(name) return self.nowHold == name or self.nowPress == name end
	function p:crank() return 0 end
	function p:crankPos() return 180 end
	function p:docked() return false end
	function p:dt() return 1 / 30 end
	return p
end

local s, inp, script

local function namesOf(list) local o = {} for i, e in ipairs(list) do o[i] = e.name end return table.concat(o, ",") end

tw.selftest.scenarios.teams = {
	step = function(ctx)
		if not s then
			local r = tw.roster.new()
			for _, n in ipairs { "Brave Birch", "Lucky Larch", "Agreeable Ginkgo", "Mighty Maple", "Jolly Juniper" } do
				tw.roster.add(r, n, nil, "2026-11-15")
			end
			inp = manual()
			s = scene.new(inp, "match", { scripted = true, roster = r })
			scene.enter()
			local function press(b) return function() inp.press = b end end
			script = {
				function() if s.col ~= "M" or s.row ~= 4 then return "the cursor starts at " .. s.col .. s.row end inp.press = "left" end,
				press("left"), press("left"),            -- Alex, Kim, Lee to Team A
				press("right"), press("right"),          -- Max, Sam to Team B
				function()
					if namesOf(s.L.A) ~= "Agreeable Ginkgo,Brave Birch,Jolly Juniper" or namesOf(s.L.B) ~= "Lucky Larch,Mighty Maple" then
						return "teams " .. namesOf(s.L.A) .. " / " .. namesOf(s.L.B)
					end
					-- (the bench is START, NEW, GUEST now, the cursor on GUEST)
				end,
				"capture",
				press("left"),                           -- to Team A's column, on its third row: Brave Birch
				function() if s.col ~= "A" then return "column " .. s.col end inp.press, inp.hold = "up", "a" end,
				function() if namesOf(s.L.A) ~= "Brave Birch,Agreeable Ginkgo,Jolly Juniper" then return "order " .. namesOf(s.L.A) end inp.press = "up" end,
				function() if s.row ~= 1 then return "row " .. s.row end inp.press = "a" end,   -- the name row
				function() if not s.sub then return "no Names screen" end
					if s.sub.kind ~= "team" then return "a team name asked as " .. tostring(s.sub.kind) end
					if not names.set(s.sub, "Wobbly Towers") then return "Wobbly Towers refused" end end,
				"capture",
				function() names.ok(s.sub) end,
				function() if s.L.names.A ~= "Wobbly Towers" then return "team name " .. tostring(s.L.names.A) end end,
				"capture",
				press("right"),                          -- the bench, START
				function() if s.col ~= "M" or s.row ~= 1 then return "not on START" end inp.press = "a" end,
				function()
					if not s.done then return "START did not start" end
					local t = scene.teams(s)
					-- a row too wide for its column cuts the name, never the order number
					local cut = scene.fitName("2 Agreeable Ginkgo", scene.tune.colW - 14)
					if cut ~= "2 A. Ginkgo" then return "cut to " .. cut end
					if t.A.name ~= "Wobbly Towers" or t.B.name ~= "Team Lucky Larch" then return "names " .. t.A.name .. ", " .. t.B.name end
					local ms = tw.scenes.match.new(tw.input.scripted({}), { teams = t, seed = 1, instant = true })
					local g = ms.m.game
					if #g.teams.A.players ~= 3 or g.teams.A.players[1].name ~= "Brave Birch" or #g.teams.B.players ~= 2 then
						return "the match's teams"
					end
				end,
			}
		end
		local a = table.remove(script, 1)
		if a == "capture" then
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
		return #script == 0
	end,
}
