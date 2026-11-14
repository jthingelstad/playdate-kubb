-- Kubb: Throwing Wood. Playdate shell.
--
-- Launch arguments (Simulator only), read from playdate.argv:
--   selftest=<scenario> out=<absolute dir>   run a self-test scenario and quit
-- Without them the game opens the title: "PASS + PLAY" (two teams pass and
-- play, scenes/match) or "PRACTICE" (scenes/throw: endless practice from the
-- baseline).
--
-- System Menu (at most three items; the third is the scene's own):
--   "Readout"  the debug line after each throw (power, smoothness, tilt,
--              LEGAL/HELICOPTER, distance), for tuning on hardware
--   "Record"   append each swing's crank samples to traces.jsonl in the
--              Data folder (replay with tools/replay_traces.lua). On by
--              default while the throw is being tuned; self-tests leave it off.
--   "Pitch"    practice only: play (nothing) / reset (stand every piece back
--              up and clear the drilled kubbs) / drill (aim kubbs at the far
--              half with a landing marker; they stay where they end) / batons
--              (back to throwing batons) / bench (the physics benchmark of core/bench plus the
--              scene's draw time; shows the figures and appends a line to
--              bench.txt) / title (back to the title)
--   "Match"    match only: play (nothing) / resign (the team on turn gives
--              up, once nothing is in the air) / title (leave: the match is
--              dropped and no game file is written)

import "CoreLibs/graphics"

import "core/tw"
-- first, so it can count the graphics calls of every module (selftest=drawcalls only)
import "selftest/_drawcount"
import "core/vec"
import "input"
import "recorder"
import "framelog"
import "scenes/title"
import "scenes/throw"
import "scenes/match"
import "scenes/names"
import "core/save"
import "scenes/games"
import "benchscreen"
import "autobench"
import "selftest/runner"
import "selftest/hello"
import "selftest/title"
import "selftest/settle"
import "selftest/settle-resign"
import "selftest/settle-crank"
import "selftest/names"
import "selftest/resume"
import "selftest/games"
import "selftest/aim-center"
import "selftest/aim-walk-swivel"
import "selftest/loft"
import "selftest/windup"
import "selftest/flight"
import "selftest/helicopter"
import "selftest/gauge"
import "selftest/gauge-ghost"
import "selftest/rearm"
import "selftest/hit"
import "selftest/burst"
import "selftest/bursts"
import "selftest/burst-reset"
import "selftest/layer"
import "selftest/miss"
import "selftest/field"
import "selftest/king"
import "selftest/skid"
import "selftest/skid-sand"
import "selftest/autoreset"
import "selftest/bench"
import "selftest/match-opening"
import "selftest/match-toss"
import "selftest/match-whole"
import "selftest/match-vs"
import "selftest/match-debris"
import "selftest/drill"
import "selftest/cards"
import "selftest/hud-drill"
import "selftest/drawcalls"

local function launchArgs()
	local args = {}
	for i, a in ipairs(playdate.argv or {}) do
		local k, v = a:match("^([%w_]+)=(.*)$")
		if k then args[k] = v end
	end
	return args
end

local args = launchArgs()

if args.selftest then
	tw.sound.on = false      -- no knocks from the Simulator during self-tests
	tw.selftestRun = true    -- saves go to their own key (scenes/match.saveKey)
	tw.selftest.start(args.selftest, args.out)
	function playdate.update()
		tw.selftest.update()
	end
else
	local throw, match, title = tw.scenes.throw, tw.scenes.match, tw.scenes.title
	local names, games = tw.scenes.names, tw.scenes.games
	local lastMatch = nil            -- the options of the last match (a rematch plays them again)
	local device = tw.input.device()
	local current, kind = nil, nil   -- the scene and which: "title" | "practice" | "match"
	local showReadout = false        -- System Menu "Readout": off in normal play
	local benchRun = nil
	local pending = nil              -- a scene to open on the next frame (from a menu callback)
	local open, savedMatch

	tw.recorder.on = true
	tw.framelog.on = true
	local menu = playdate.getSystemMenu()

	-- The throw scene of the current scene (the match keeps one inside).
	local function throwScene()
		if kind == "practice" then return current end
		if kind == "match" then return current.ts end
		return nil
	end

	-- Readout and Record on every scene, then the scene's own options item,
	-- whose choice acts when the menu closes and then reads "play" again.
	local function sceneMenu()
		menu:removeAllMenuItems()
		menu:addCheckmarkMenuItem("Readout", showReadout, function(on)
			showReadout = on
			local ts = throwScene()
			if ts then ts.showReadout = on end
		end)
		menu:addCheckmarkMenuItem("Record", tw.recorder.on, function(on)
			tw.recorder.on = on
			tw.recorder.clear()
		end)
		local item
		if kind == "practice" then
			item = menu:addOptionsMenuItem("Pitch", { "play", "reset", "drill", "batons", "bench", "title" }, "play", function(v)
				if v == "reset" then
					throw.reset(current)
				elseif v == "drill" or v == "batons" then
					throw.setDrill(current, v == "drill")
				elseif v == "bench" then
					local scene = current
					benchRun = tw.benchscreen.start(function() throw.draw(scene) end)
				elseif v == "title" then
					pending = "title"
				end
				item:setValue("play")
			end)
		elseif kind == "title" then
			menu:addMenuItem("Games", function() pending = "games" end)
		elseif kind == "match" then
			item = menu:addOptionsMenuItem("Match", { "play", "resign", "title" }, "play", function(v)
				if v == "resign" then
					match.resign(current)
				elseif v == "title" then
					pending = "title"
				end
				item:setValue("play")
			end)
		end
	end

	-- A line about the match saved in progress ("ASH V BIRCH, TURN 7"), or
	-- nil when there is none (or it cannot be read back).
	function savedMatch()
		local d = playdate.datastore.read("match")
		if not tw.save.unpack(d) then return nil end
		local t = d.game.teams
		return string.upper(t.A.name .. " V " .. t.B.name) .. ", TURN " .. d.game.turn
	end

	function open(which)
		kind = which
		-- a scene left during the king burst's flash must not leave the
		-- screen inverted (render/burst)
		playdate.display.setInverted(false)
		if which == "practice" then
			current = throw.new(device)
			throw.enter()
		elseif which == "match" or which == "vs" then
			-- PASS + PLAY or VS PLAYDATE: the names first (scenes/names)
			kind = "names"
			current = names.new(device, which)
			names.enter(current)
		elseif which == "games" then
			-- the games list and score sheets (scenes/games)
			kind = "games"
			current = games.new(device)
			games.enter()
		elseif which == "play" or which == "rematch" then
			-- the match itself: the names just entered, or the last match's again
			kind = "match"
			current = match.new(device, lastMatch)
			match.enter()
		elseif which == "resume" and savedMatch() then
			-- the match saved in progress (core/save), on from where it was left
			local m, opts = tw.save.unpack(playdate.datastore.read("match"))
			lastMatch = { vs = opts.vs, names = opts.names }
			kind = "match"
			current = match.new(device, { vs = opts.vs, names = opts.names, resume = m })
			match.enter()
		else
			kind = "title"
			current = title.new(device, savedMatch())
			title.enter()
		end
		local ts = throwScene()
		if ts then ts.showReadout = showReadout end
		sceneMenu()
	end

	open("title")

	-- Testing on the device over hours (a bench, installs): a file named
	-- "nolock" in the Data folder keeps the game from auto-locking. Read once
	-- at launch; delete the file when the testing is done.
	tw.noLock = playdate.file.exists("nolock")
	if tw.noLock then playdate.setAutoLockDisabled(true) end

	-- the device autobench (autobench.lua): a file named "autobench" in the
	-- Data folder at launch runs it once before the game
	local autoRun = playdate.file.exists(tw.autobench.flag) and tw.autobench.start() or nil

	function playdate.update()
		if autoRun then
			if tw.autobench.update(autoRun) then autoRun = nil end
			return
		end
		if benchRun then
			if tw.benchscreen.update(benchRun) then benchRun = nil end
			return
		end
		if pending then
			local which = pending
			pending = nil
			open(which)
		end
		if kind == "practice" then
			throw.update(current)
			throw.draw(current)
		elseif kind == "match" then
			match.update(current)
			if current.exit then return open(current.exit) end
			match.draw(current)
		elseif kind == "games" then
			games.update(current)
			if current.exit then return open(current.exit) end
			games.draw(current)
		elseif kind == "names" then
			names.update(current)
			if current.done then
				lastMatch = { vs = (current.mode == "vs") and "B" or nil, names = current.list }
				return open("play")
			end
			if current.exit then return open(current.exit) end
			names.draw(current)
		else
			title.update(current)
			if current.exit then return open(current.exit) end
			title.draw(current)
		end
	end
end
