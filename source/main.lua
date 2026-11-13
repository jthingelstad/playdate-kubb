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

import "CoreLibs/graphics"

import "core/tw"
import "core/vec"
import "input"
import "recorder"
import "scenes/title"
import "scenes/throw"
import "selftest/runner"
import "selftest/hello"
import "selftest/aim-center"
import "selftest/aim-walk-swivel"
import "selftest/loft"
import "selftest/windup"
import "selftest/flight"
import "selftest/helicopter"
import "selftest/gauge"

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

	function playdate.update()
		throw.update(scene)
		throw.draw(scene)
	end
end
