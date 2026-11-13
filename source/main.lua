-- Kubb: Throwing Wood. Playdate shell.
--
-- Launch arguments (Simulator only), read from playdate.argv:
--   selftest=<scenario> out=<absolute dir>   run a self-test scenario and quit
-- Without them the game opens the throw scene (stage 1: endless practice
-- from the baseline).
--
-- System Menu:
--   "Readout"  the debug line after each throw (power, smoothness, tilt,
--              LEGAL/HELICOPTER, distance), for tuning on hardware
--   "Record"   append each swing's crank samples to traces.jsonl in the
--              Data folder (replay with tools/replay_traces.lua). On by
--              default while the throw is being tuned; self-tests leave it off.
--   "Pitch"    play (nothing) / reset (stand every piece back up) / bench
--              (the physics benchmark of core/bench plus the scene's draw
--              time; shows the figures and appends a line to bench.txt)

import "CoreLibs/graphics"

import "core/tw"
import "core/vec"
import "input"
import "recorder"
import "scenes/title"
import "scenes/throw"
import "benchscreen"
import "selftest/runner"
import "selftest/hello"
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
import "selftest/miss"
import "selftest/field"
import "selftest/skid"
import "selftest/skid-sand"
import "selftest/autoreset"
import "selftest/bench"

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
	local throw = tw.scenes.throw
	local scene = throw.new(tw.input.device())
	throw.enter()

	tw.recorder.on = true
	local menu = playdate.getSystemMenu()
	menu:addCheckmarkMenuItem("Readout", scene.showReadout, function(on)
		scene.showReadout = on
	end)
	menu:addCheckmarkMenuItem("Record", tw.recorder.on, function(on)
		tw.recorder.on = on
		tw.recorder.clear()
	end)

	-- The third (and last: the System Menu takes three) item: an options
	-- item whose choice acts when the menu closes, then reads "play" again.
	local benchRun = nil
	local pitchItem
	pitchItem = menu:addOptionsMenuItem("Pitch", { "play", "reset", "bench" }, "play", function(v)
		if v == "reset" then
			throw.reset(scene)
		elseif v == "bench" then
			benchRun = tw.benchscreen.start(function() throw.draw(scene) end)
		end
		pitchItem:setValue("play")
	end)

	function playdate.update()
		if benchRun then
			if tw.benchscreen.update(benchRun) then benchRun = nil end
			return
		end
		throw.update(scene)
		throw.draw(scene)
	end
end
