-- The System Menu "Pitch: bench" screen. Runs core/bench (the same scenario
-- as `make bench` on the desktop) a chunk of steps per frame, then times
-- `drawFrames` draws of the throw scene as it stood when the menu opened,
-- shows the figures and appends one line to bench.txt in the Data folder.
-- Any button returns to the game.
import "CoreLibs/graphics"
import "core/tw"
import "core/bench"

local gfx <const> = playdate.graphics
local bench = tw.bench

local screen = {}

screen.chunk = 24       -- physics steps between redraws of the progress line
screen.drawFrames = 30  -- draws of the scene timed for the draw figure

local clock = playdate.getElapsedTime

-- Start the bench. draw() redraws the scene being measured.
function screen.start(draw)
	local s = { phase = "physics", draw = draw, progress = 0, drawn = 0, drawTime = 0, lines = nil }
	s.co = coroutine.create(function()
		return bench.run(clock, screen.chunk, function(done, steps)
			coroutine.yield(done / steps)
		end)
	end)
	return s
end

local function finish(s)
	local r = s.result
	local drawMs = s.drawTime * 1000 / s.drawn
	s.lines = {
		"Bench (A or B to return)",
		string.format("%d steps, %.1f s simulated, %.2f s", r.steps, r.simSeconds, r.seconds),
		string.format("%.2f ms/step, %.1f steps per 20 ms frame", r.msPerStep, 20 / r.msPerStep),
		string.format("collisions: %d steps at %.2f ms/step", r.hotSteps, r.hotMsPerStep),
		string.format("(%.1f steps per 20 ms frame)", r.hotMsPerStep > 0 and 20 / r.hotMsPerStep or 0),
		string.format("real time needs %.1f steps per frame", 0.02 / tw.world.tune.dt),
		string.format("draw: %.1f ms per frame (%d frames)", drawMs, s.drawn),
		"appended to bench.txt",
	}
	local f = playdate.file.open("bench.txt", playdate.file.kFileAppend)
	if f then
		f:write(bench.line(r, "device") .. string.format("; draw %.1f ms/frame\n", drawMs))
		f:close()
	else
		s.lines[#s.lines] = "could not write bench.txt"
	end
	s.phase = "done"
end

-- One frame. Returns true when the player leaves the screen.
function screen.update(s)
	if s.phase == "physics" then
		local ok, v = coroutine.resume(s.co)
		if not ok then error(v) end
		if coroutine.status(s.co) == "dead" then
			s.result = v
			s.phase = "draw"
		else
			s.progress = v
		end
		gfx.clear(gfx.kColorWhite)
		gfx.drawText(string.format("Bench: physics %d%%", math.floor(s.progress * 100)), 10, 10)
	elseif s.phase == "draw" then
		local t0 = clock()
		s.draw()
		s.drawTime = s.drawTime + (clock() - t0)
		s.drawn = s.drawn + 1
		if s.drawn >= screen.drawFrames then finish(s) end
	else
		gfx.clear(gfx.kColorWhite)
		for i, l in ipairs(s.lines) do gfx.drawText(l, 10, 6 + (i - 1) * 22) end
		if playdate.buttonJustPressed(playdate.kButtonB) or playdate.buttonJustPressed(playdate.kButtonA) then
			return true
		end
	end
	return false
end

tw.benchscreen = screen
