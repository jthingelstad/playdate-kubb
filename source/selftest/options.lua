-- Scenario "options": the match options (scenes/options) for PASS + PLAY,
-- driven by the d-pad: right twice on SURFACE (snow), down and right on
-- OPENING (six), down and left on RAISING (automatic), then A. Frames: 1 as
-- it opens (the defaults), 2 the surface on SNOW, 3 RAISING chosen. The
-- check: A is done and the options it gives are snow, six and automatic, and
-- THROW TO GO on (1.1.0: its default).
import "core/tw"
import "scenes/options"
import "input"

local scene = tw.scenes.options
local s

tw.selftest.scenarios.options = {
	step = function(ctx)
		if not s then
			s = scene.new(tw.input.scripted {
				{ n = 2 }, { press = { "right" } }, { n = 1 }, { press = { "right" } }, { n = 2 },
				{ press = { "down" } }, { n = 1 }, { press = { "right" } }, { n = 1 },
				{ press = { "down" } }, { n = 1 }, { press = { "left" } }, { n = 2 },
				{ press = { "a" } }, { n = 2 },
			}, "match", { scripted = true })
			scene.enter()
		end
		scene.update(s)
		scene.draw(s)
		local f = ctx.frame
		if f == 1 then
			if s.row ~= 1 then error("starts on row " .. s.row) end
			ctx:capture()
		elseif f == 5 then
			if tw.matchopts.value(s.choice, "surface") ~= "Snow" then error("surface not snow") end
			ctx:capture()
		elseif f == 13 then
			if s.row ~= 3 then error("row " .. s.row) end
			ctx:capture()
		end
		if s.done then
			local o = scene.apply(s, {})
			if o.togo ~= true then error("THROW TO GO is not on by default") end
			if o.surface ~= "Snow" or o.opening ~= "six" or not o.autoSettle then
				error(string.format("options %s %s %s", tostring(o.surface), tostring(o.opening), tostring(o.autoSettle)))
			end
			return true
		end
		if f > 40 then error("A did not start") end
		return false
	end,
}
