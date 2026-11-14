-- Scenario "drills-blast": a BLAST run's rail keeps its score beside the
-- marker distance (scenes/drills, throw's drawRail in drill mode). Frame 1:
-- the first BLAST throw's aim view.
import "core/tw"
import "scenes/drills"
import "core/drills"
import "input"

local scene = tw.scenes.drills

tw.selftest.scenarios["drills-blast"] = {
	step = function(ctx)
		local s = scene.new(tw.input.scripted({ { n = 100 } }), { scripted = true })
		scene.enter()
		scene.startRun(s, tw.drills.byId("blast"))
		scene.update(s)
		scene.draw(s)
		local ts = s.ts
		if not ts.drill then error("BLAST is not in drill mode") end
		if ts.railR1 ~= "SCORE 0" then error("rail score " .. tostring(ts.railR1)) end
		ctx:capture()
		return true
	end,
}
