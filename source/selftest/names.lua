-- Scenario "names": the Names screen (scenes/names) through the input provider, as a
-- player works it. A player's name starts on "Mighty Maple"; the crank steps the first
-- word (frame 1), down and left/right the second (frame 2), SHUFFLE rolls a new one;
-- a team name's first word runs from "The" through the adjectives (frame 3); a name the
-- check refuses stays with the reason (frame 4); A takes it, B goes back.
-- The check: every name shown is a generated name of its kind (core/namegen), the
-- rows step as asked, the taken one is refused, and a match takes the names given.
import "core/tw"
import "core/namegen"
import "scenes/names"
import "scenes/match"
import "input"

local names, namegen = tw.scenes.names, tw.namegen

-- An input provider pressed by the scenario: press(name) or crank(d) for the next frame.
local function manual()
	local p = { want = nil, now = nil, c = 0, cnow = 0 }
	function p:advance() self.now, self.want = self.want, nil; self.cnow, self.c = self.c, 0 end
	function p:pressed(name) return self.now == name end
	function p:held(name) return self.now == name end
	function p:crank() return self.cnow end
	function p:crankPos() return 180 end
	function p:docked() return false end
	function p:dt() return 1 / 30 end
	return p
end

local s, inp, script, team, taken

local function valid(kind)
	local t = names.text(kind == "team" and team or s)
	if not namegen.valid(kind, t) then error("not a " .. kind .. " name: " .. tostring(t)) end
	return t
end

tw.selftest.scenarios.names = {
	step = function(ctx)
		if not s then
			inp = manual()
			s = names.new(inp, "player", { scripted = true, kind = "player", initial = "Mighty Maple",
				label = "NEW PLAYER", nxt = "THEN THEIR PAGE",
				check = function(n) if n == taken then return nil, "taken" end return n end })
			names.enter(s)
			script = {
				function() if names.text(s) ~= "Mighty Maple" then return "started on " .. names.text(s) end
					inp.c = 30 end,                                          -- the crank: one word
				function() if s.pick.parts[1] == "Mighty" then return "the crank did not step" end
					if s.pick.parts[2] ~= "Maple" then return "the crank moved the second word" end
					valid("player") end,
				"capture",
				function() inp.want = "down" end,
				function() if s.row ~= 2 then return "row " .. s.row end inp.want = "right" end,
				function() if s.pick.parts[2] == "Maple" then return "right did not step the wood" end
					valid("player"); inp.c = -30 end,
				function() valid("player") end,
				"capture",
				function() inp.want = "down" end,                           -- SHUFFLE
				function() inp.want = "right"; s.before = names.text(s) end,
				function() if names.text(s) == s.before then return "shuffle gave the same name" end
					valid("player")
					taken = names.text(s); inp.want = "a" end,             -- refused: taken
				function() if s.done then return "a taken name was accepted" end
					if s.why ~= "taken" then return "why " .. tostring(s.why) end end,
				"capture4",
				function() inp.want = "left" end,                           -- another name
				function() inp.want = "a" end,
				function() if not s.done then return "A did not take " .. names.text(s) end
					if s.list.A ~= names.text(s) then return "list " .. tostring(s.list.A) end end,
				-- a team name: "The" first, then the crank onto an adjective
				function()
					team = names.new(inp, "player", { scripted = true, kind = "team", initial = "The Lumberjacks",
						label = "TEAM NAME", nxt = "THEN BACK TO TEAMS" })
					names.enter(team)
					if names.text(team) ~= "The Lumberjacks" then return "team started on " .. names.text(team) end
					inp.c = 25
				end,
				function()
					if team.pick.parts.shape ~= "adj" then return "the first word after The is " .. tostring(team.pick.parts[1]) end
					valid("team")
				end,
				"captureTeam",
				function() inp.want = "b" end,
				function() if team.exit ~= "back" then return "B gave " .. tostring(team.exit) end
					-- a typed name kept from before is not offered: a generated one in its place
					local r = names.new(inp, "player", { scripted = true, kind = "player", initial = "Montgomery" })
					if not namegen.valid("player", names.text(r)) then return "typed name kept: " .. names.text(r) end
					local ms = tw.scenes.match.new(tw.input.scripted({}), { names = { A = s.list.A, B = names.text(r) },
						seed = 1, instant = true })
					if ms.m.game.teams.A.name ~= s.list.A then return "match team " .. ms.m.game.teams.A.name end
					ctx.note = (ctx.note or "") .. " took=" .. s.list.A:gsub(" ", "_")
				end,
			}
		end
		local a = table.remove(script, 1)
		if type(a) == "string" then
			names.draw((a == "captureTeam") and team or s)
			ctx:capture()
			return false
		end
		if a then
			local err = a()
			if err then error(err) end
		end
		local cur = team or s
		names.update(cur)
		names.draw(cur)
		return #script == 0
	end,
}
