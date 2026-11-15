-- Scenario "match-teams": a whole scripted match (core/autothrow, shown at
-- rest at once) of three players against two (docs/PLAYERS.md section 5).
-- Every hand-off and pass card is passed with A, but once a pass card's
-- baton is handed to another player through the change list (B, down to
-- the first player the rules allow, A).
-- Frames: 1 the first hand-off of Team A naming its first thrower and the
-- turn's order, 2 the first pass card, 3 the change list, 4 the winner
-- card with each player's hits.
-- The check: each pass card names the thrower set up and the throw is at
-- their level, the change took, every turn keeps Rules V4.0 II.A.4 and
-- II.B.5 (core/order.checkSheet), and the game file names the levels.
import "selftest/_match"
import "core/order"

local st = tw.selftest

local shot = { handoff = false, pass = false, change = false, winner = false }
local changedTo, changeDone, pressed = nil, false, false
local notes = ""

local TEAMS = {
	A = { name = "Snow Kubbs", players = { { name = "Kim", level = "pro" }, { name = "Max" }, { name = "Alex" } } },
	B = { name = "Baton Rouge", players = { { name = "Sam" }, { name = "Lee", level = "beginner" } } },
}

st.scenarios["match-teams"] = st.matchScenario {
	opts = { seed = 7, instant = true, maxTurns = 30, teams = TEAMS },
	refreshRate = 0,
	maxFrames = 8000,
	step = function(ms, ctx, h)
		if not h.idle() then return false end
		if ms.changing then
			if not shot.change then ctx:capture(); shot.change = true end
			local c = ms.changing
			local target
			for j, e in ipairs(c.list) do if e.ok and not e.current and not target then target = j end end
			if not target then error("nobody else may take the baton") end
			local steps = {}
			for _ = 1, (target - c.i) % #c.list do steps[#steps + 1] = { press = { "down" } } end
			steps[#steps + 1] = { press = { "a" } }
			changedTo = c.list[target].id
			h.feed(steps)
		elseif ms.phase == "handoff" then
			local c = ms.handoff
			if c.to == "A" and not shot.handoff then
				if not c.thrower or not c.order or #c.order < 2 then error("the hand-off card names no order") end
				ctx:capture()
				shot.handoff = true
			end
			h.pressA()
		elseif ms.phase == "pass" then
			if ms.pass.name ~= ms.setup.thrower.name then error("the pass card names " .. ms.pass.name) end
			-- the throw is at the thrower's own level (nil: the System Menu's)
			if ms.ts.level ~= ms.setup.thrower.level then
				error("the throw's level is " .. tostring(ms.ts.level) .. ", " .. ms.setup.thrower.name .. "'s "
					.. tostring(ms.setup.thrower.level))
			end
			if not shot.pass then ctx:capture(); shot.pass = true end
			if changedTo and not changeDone then
				if ms.setup.thrower.id ~= changedTo then
					error("the change gave " .. ms.setup.thrower.id .. ", not " .. changedTo)
				end
				if ms.m.order.deal[ms.setup.n] ~= changedTo then error("the order did not take the change") end
				notes = notes .. " changed=" .. changedTo
				changeDone = true
			end
			if not changedTo and ms.setup.kind == "baton" then
				h.feed { { press = { "b" } } }
			else
				h.pressA()
			end
		elseif ms.phase == "over" then
			if not shot.winner then
				if not changeDone then error("no pass card with a baton changed") end
				if not ms.win.players then error("the winner card has no players") end
				ctx:capture()
				shot.winner = true
				local bad = tw.order.checkSheet(ms.m.game)
				if #bad > 0 then error(bad[1]) end
				local text = tw.match.file(ms.m, nil, "0.0.1")
				if not text:find('[Throw Levels "kim pro, lee beginner"]', 1, true) then
					error("the game file's levels")
				end
				notes = notes .. string.format(" winner=%s turns=%d", ms.win.winner, ms.win.turns)
				h.pressA()
				pressed = true
			elseif pressed then
				if ms.exit ~= "rematch" then error("A on the winner card gave " .. tostring(ms.exit)) end
				ctx.note = ctx.note .. notes
				return true
			end
		end
		return false
	end,
}
