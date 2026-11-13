-- Scenario "bench": the System Menu "Pitch: bench" screen, run in the
-- Simulator exactly as on the device (it also appends to bench.txt in the
-- Simulator's Data folder). Frame: the result screen. The marker note gives
-- the Simulator's ms per step and draw ms per frame (the Mac, not the device).
import "core/tw"
import "input"
import "scenes/throw"
import "benchscreen"

local throw, screen = tw.scenes.throw, tw.benchscreen

local scene, run = nil, nil

tw.selftest.scenarios.bench = {
	step = function(ctx)
		if not scene then
			scene = throw.new(tw.input.scripted({ { n = 1000 } }))
			throw.enter()
			throw.update(scene)
			run = screen.start(function() throw.draw(scene) end)
		end
		local wasDone = run.phase == "done"
		screen.update(run)
		if wasDone then   -- the result screen has been drawn
			ctx.note = string.format("ms_per_step=%.3f collision_ms_per_step=%.3f draw_ms=%.2f",
				run.result.msPerStep, run.result.hotMsPerStep, run.drawTime * 1000 / run.drawn)
			ctx:capture()
			return true
		end
		if ctx.frame > 400 then error("bench did not finish") end
		return false
	end,
}
