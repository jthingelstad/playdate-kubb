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
--   "Pitch"    practice only: play (nothing) / how to (the HOW TO THROW card,
--              also on Match and Drill; shown once by itself before a
--              player's first baton) / reset (stand every piece back
--              up and clear the drilled kubbs) / drill (aim kubbs at the far
--              half with a landing marker; they stay where they end) / batons
--              (back to throwing batons) / grass, sand, snow (the surface) / bench (the physics benchmark of core/bench plus the
--              scene's draw time; shows the figures and appends a line to
--              bench.txt) / title (back to the title)
--   "Match"    match only: play (nothing) / how to / sheet (the score sheet so far,
--              once nothing is in the air; B back) / resign (the team on turn gives
--              up, once nothing is in the air) / title (leave: the match is
--              dropped and no game file is written)
--   "Drill"    drills only: play (nothing) / how to / menu (leave the run part way,
--              unrecorded, for the drills menu) / title

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
import "scenes/options"
import "core/save"
import "scenes/games"
import "scenes/drills"
import "benchscreen"
import "autobench"
import "soak"
import "selftest/runner"
import "selftest/hello"
import "selftest/title"
import "selftest/settle"
import "selftest/settle-resign"
import "selftest/settle-crank"
import "selftest/names"
import "selftest/options"
import "selftest/resume"
import "selftest/soak"
import "selftest/games"
import "selftest/drills"
import "selftest/drills-blast"
import "selftest/aim-center"
import "selftest/aim-walk-swivel"
import "selftest/loft"
import "selftest/windup"
import "selftest/aim-arc"
import "selftest/flight"
import "selftest/helicopter"
import "selftest/gauge"
import "selftest/gauge-ghost"
import "selftest/rearm"
import "selftest/hit"
import "selftest/knocks"
import "selftest/howto"
import "selftest/match-howto"
import "selftest/burst"
import "selftest/bursts"
import "selftest/burst-reset"
import "selftest/layer"
import "selftest/miss"
import "selftest/field"
import "selftest/low-hard"
import "selftest/release-stop"
import "selftest/king"
import "selftest/sets"
import "selftest/skid"
import "selftest/skid-sand"
import "selftest/skid-snow"
import "selftest/autoreset"
import "selftest/bench"
import "selftest/match-opening"
import "selftest/match-toss"
import "selftest/match-whole"
import "selftest/match-sheet"
import "selftest/match-wind"
import "selftest/match-vs"
import "selftest/match-debris"
import "selftest/drill"
import "selftest/drill-stop"
import "selftest/cards"
import "selftest/hud-drill"
import "selftest/drawcalls"
import "selftest/clock-gauge"

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
	local names, games, drillsScene = tw.scenes.names, tw.scenes.games, tw.scenes.drills
	local optionsScene = tw.scenes.options
	local nextMatch = nil            -- names and mode on their way through the options screen
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
		if kind == "drills" then return current.ts end
		return nil
	end

	-- Readout and Record on every scene, then the scene's own options item,
	-- whose choice acts when the menu closes and then reads "play" again.
	local function sceneMenu()
		menu:removeAllMenuItems()
		menu:addCheckmarkMenuItem("Readout", showReadout, function(on)
			showReadout = on
			if kind == "drills" then current.showReadout = on end
			local ts = throwScene()
			if ts then ts.showReadout = on end
		end)
		menu:addCheckmarkMenuItem("Record", tw.recorder.on, function(on)
			tw.recorder.on = on
			tw.recorder.clear()
		end)
		local item
		if kind == "practice" then
			item = menu:addOptionsMenuItem("Pitch", { "play", "how to", "reset", "drill", "batons", "grass", "sand",
				"snow", "bench", "title" }, "play", function(v)
				if v == "how to" then
					throw.showHowTo(current)
				elseif v == "grass" or v == "sand" or v == "snow" then
					throw.setSurface(current, v)
				elseif v == "reset" then
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
		elseif kind == "drills" then
			-- leave a run part way, unrecorded: for the drills menu or the title
			item = menu:addOptionsMenuItem("Drill", { "play", "how to", "menu", "title" }, "play", function(v)
				if v == "how to" then
					local ts = throwScene()
					if ts then throw.showHowTo(ts) end
				elseif v == "menu" then
					drillsScene.quit(current)
				elseif v == "title" then
					pending = "title"
				end
				item:setValue("play")
			end)
		elseif kind == "match" then
			item = menu:addOptionsMenuItem("Match", { "play", "how to", "sheet", "resign", "title" }, "play", function(v)
				if v == "how to" then
					local ts = throwScene()
					if ts then throw.showHowTo(ts) end
				elseif v == "sheet" then
					match.showSheet(current)
				elseif v == "resign" then
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
	-- A save that does not read back as expected (a damaged file) is no
	-- save: nothing here may stop the game launching.
	local function savedLine()
		local d = playdate.datastore.read("match")
		if not tw.save.unpack(d) then return nil end
		local t = d.game.teams
		return string.upper(t.A.name .. " V " .. t.B.name) .. ", TURN " .. d.game.turn
	end
	function savedMatch()
		local ok, line = pcall(savedLine)
		if ok and type(line) == "string" then return line end
		return nil
	end

	function open(which)
		kind = which
		-- a scene left during the king burst's flash must not leave the
		-- screen inverted (render/burst)
		playdate.display.setInverted(false)
		if which == "practice" then
			-- PRACTICE: the drills menu (scenes/drills); its OPEN PITCH is "pitch"
			kind = "drills"
			current = drillsScene.new(device)
			current.showReadout = showReadout
			drillsScene.enter()
		elseif which == "pitch" then
			kind = "practice"
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
		elseif which == "options" then
			-- the match options after the names (scenes/options)
			kind = "options"
			current = optionsScene.new(device, nextMatch.vs and "vs" or "match")
			optionsScene.enter()
		elseif which == "play" or which == "rematch" then
			-- the match itself: the names just entered, or the last match's again
			kind = "match"
			current = match.new(device, lastMatch)
			match.enter()
		elseif which == "resume" and savedMatch() then
			-- the match saved in progress (core/save), on from where it was left
			local m, opts = tw.save.unpack(playdate.datastore.read("match"))
			-- a rematch keeps the resumed match's options (surface and opening
			-- are the engine's own)
			lastMatch = { vs = opts.vs, names = opts.names, autoSettle = opts.autoSettle, set = opts.set, wind = opts.wind,
				surface = m.game.surface, opening = m.game.opening }
			kind = "match"
			current = match.new(device, { vs = opts.vs, names = opts.names, autoSettle = opts.autoSettle, set = opts.set,
				wind = opts.wind, resume = m })
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
	-- the device soak (soak.lua): a file named "soak" runs whole matches
	-- unattended once, after any autobench
	local soakWanted = playdate.file.exists(tw.soak.flag)
	-- HOW TO THROW once by itself before a player's first baton (never in the
	-- self-tests, the autobench or the soak)
	throw.howtoFirst = not tw.selftestRun and not autoRun and not soakWanted
	local soakRun = nil

	function playdate.update()
		if autoRun then
			if tw.autobench.update(autoRun) then autoRun = nil end
			return
		end
		if soakWanted then
			soakWanted = false
			soakRun = tw.soak.start()
		end
		if soakRun then
			if tw.soak.update(soakRun) then soakRun = nil; open("title") end
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
		elseif kind == "drills" then
			drillsScene.update(current)
			if current.exit then return open(current.exit == "practice" and "pitch" or current.exit) end
			drillsScene.draw(current)
		elseif kind == "games" then
			games.update(current)
			if current.exit then return open(current.exit) end
			games.draw(current)
		elseif kind == "names" then
			names.update(current)
			if current.done then
				-- then the match options
				nextMatch = { vs = (current.mode == "vs") and "B" or nil, names = current.list }
				return open("options")
			end
			if current.exit then return open(current.exit) end
			names.draw(current)
		elseif kind == "options" then
			optionsScene.update(current)
			if current.done then
				lastMatch = optionsScene.apply(current, nextMatch)
				return open("play")
			end
			if current.back then return open(nextMatch.vs and "vs" or "match") end
			optionsScene.draw(current)
		else
			title.update(current)
			if current.exit then return open(current.exit) end
			title.draw(current)
		end
	end
end
