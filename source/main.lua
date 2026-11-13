-- Kubb: Throwing Wood. Playdate shell.
--
-- Launch arguments (Simulator only), read from playdate.argv:
--   selftest=<scenario> out=<absolute dir>   run a self-test scenario and quit
-- Without them the game shows the title screen.

import "CoreLibs/graphics"

import "core/tw"
import "core/vec"
import "scenes/title"
import "selftest/runner"
import "selftest/hello"

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
	function playdate.update()
		tw.scenes.title.draw()
	end
end
