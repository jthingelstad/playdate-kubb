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
import "benchscreen"
import "autobench"
import "selftest/runner"
import "selftest/hello"
import "selftest/title"
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
import "selftest/match-debris"
import "selftest/drill"
import "selftest/cards"
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
	tw.selftest.start(args.selftest, args.out)
	function playdate.update()
		tw.selftest.update()
	end
else
	local throw, match, title = tw.scenes.throw, tw.scenes.match, tw.scenes.title
	local device = tw.input.device()
	local current, kind = nil, nil   -- the scene and which: "title" | "practice" | "match"
	local showReadout = true
	local benchRun = nil
	local pending = nil              -- a scene to open on the next frame (from a menu callback)
	local open

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

	function open(which)
		kind = which
		if which == "practice" then
			current = throw.new(device)
			throw.enter()
		elseif which == "match" then
			current = match.new(device)
			match.enter()
		else
			kind = "title"
			current = title.new(device)
			title.enter()
		end
		local ts = throwScene()
		if ts then ts.showReadout = showReadout end
		sceneMenu()
	end

	open("title")

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
		else
			title.update(current)
			if current.exit then return open(current.exit) end
			title.draw(current)
		end
	end
end
