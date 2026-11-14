-- Scenario "match-whole": a whole match to a winner with scripted throws
-- (core/autothrow), every throw run by the physics and shown at rest at once,
-- the Simulator as fast as it goes. The match writes its game file to
-- games/ in the Data folder; the marker names it (file=...) and the Makefile
-- copies it to build/selftest/games/ and runs the notation gate over it.
-- After 30 turns the team on turn resigns, so the scenario always ends.
--
-- On the way, the first time a baton may be thrown from an advantage line,
-- the thrower must start on the line (a turn's first baton) with the
-- ADVANTAGE LINE flag up; the scripted thrower is paused, the d-pad steps
-- back (held down) and walks up again (held up), which must stop there.
-- Frames: 1 a Team B aim view mid-match, 2 at the advantage line (when the
-- match had one), 3 the winner card.
import "selftest/_match"

local st = tw.selftest

local midShot, advDone, walking, advNote = false, false, nil, " adv=none"

st.scenarios["match-whole"] = st.matchScenario {
	opts = { seed = 5, instant = true, skipHandoff = true, maxTurns = 30 },
	refreshRate = 0,
	maxFrames = 20000,
	step = function(ms, ctx, h)
		local s, ts = ms.setup, ms.ts
		if not midShot and ms.phase == "play" and s and s.side == "B" and s.kind == "baton"
			and ms.m.game.turn >= 4 and ts.mode == "aim" then
			local err = st.pitchMatchesEngine(ms)
			if err then error(err) end
			ctx:capture()
			midShot = true
		end
		if not advDone and ms.phase == "play" and s and s.kind == "baton" and s.forwardY > 0
			and ts.mode == "aim" and midShot then
			if not walking then
				if s.n == 1 and math.abs(ts.playerY - s.forwardY) > 1e-6 then
					error(string.format("started at %.3f, the line is at %.3f", ts.playerY, s.forwardY))
				end
				if not ts.advText then error("no advantage line flag") end
				-- take the controls: step back, then hold up well past the time the walk needs
				walking = { rng = ms.rng }
				ms.rng = nil
				local frames = math.ceil(s.forwardY / tw.scenes.throw.tune.walkSpeed * 50) + 30
				h.feed { { hold = { "down" }, n = 20 }, { hold = { "up" }, n = frames } }
			elseif h.idle() then
				if math.abs(ts.playerY - s.forwardY) > 1e-6 then
					error(string.format("walked to %.3f, the line is at %.3f", ts.playerY, s.forwardY))
				end
				ctx:capture()
				advNote = string.format(" adv=%.2f", s.forwardY)
				ms.rng = walking.rng
				advDone = true
			end
		end
		if ms.phase == "over" then
			if not ms.file then error("no game file: " .. tostring(ms.fileError)) end
			if not playdate.file.exists(ms.file) then error(ms.file .. " missing") end
			if not midShot then ctx:capture() end
			ctx:capture()
			local g = ms.m.game
			ctx.note = ctx.note .. advNote .. string.format(" turns=%d throws=%d winner=%s how=%s file=%s", g.turn, ms.throws,
				g.winner, ((g.how or ""):gsub(" ", "_")), ms.file)
			return true
		end
		return false
	end,
}
