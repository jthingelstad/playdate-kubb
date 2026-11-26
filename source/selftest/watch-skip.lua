-- Scenario "watch-skip" (1.1.0): the Playdate's turn against the Playdate, watched
-- and skipped. The same match twice to turn 4 (the player's throws from
-- core/autothrow seed 5, the Playdate's cpuSeed 7, raising by hand with Auto raise
-- on, punishment kubbs placed with A): first watched at SPEED 4X (B pressed twice
-- on the Playdate's first throw: 1X -> 2X -> 4X), then with A, SKIP, pressed at the
-- start of every Playdate turn and raise. The check: both game files are the same, line for
-- line (the same seeds, the same throws, the same raises), the view stayed on the
-- player's side (every Playdate throw turned, every player's not), and the
-- Playdate's raises were shown in the watched run and cut short in the skipped one.
-- Frames: 1 the Playdate's aim from the player's end with SPEED and SKIP, 2 its
-- baton in flight, 3 its raise watched from the player's end, 4 the SKIPPING card.
import "core/tw"
import "input"
import "scenes/match"
import "core/match"

local scene, cmatch = tw.scenes.match, tw.match
local B, A = { press = { "b" } }, { press = { "a" } }

local OPTS = { vs = "B", seed = 5, cpuSeed = 7, maxTurns = 4, cpuThink = 0.12, skipHandoff = true, instantPlayer = true,
	byHand = true, noSave = true, noFile = true, computer = "club" }

local function run(ctx, which)
	local p = tw.input.scripted({})
	local ms = scene.new(p, OPTS)
	ms.autoRaise.on = true
	ms.watch.speed = 1
	scene.enter()
	return { ms = ms, p = p, which = which, watched = 0, cpuTurned = 0, wrongTurn = 0, sped = false, shots = {} }
end

local function feed(r, steps) r.p.steps, r.p.i, r.p.k = steps, 1, 0 end

local function stepRun(ctx, r)
	local ms = r.ms
	scene.update(ms)
	scene.draw(ms)
	local s, ts = ms.setup, ms.ts
	local cpuTurn = ms.phase == "play" and s and s.side == "B"
	if ms.phase == "play" and s and ts.mode == "aim" then
		if cpuTurn ~= (ts.turned and true or false) then r.wrongTurn = r.wrongTurn + 1 end
	end
	if ms.phase == "settle" and ms.settle and ms.settle.watch then r.watched = r.watched + 1 end
	-- the player's punishment kubbs: placed at the engine's suggestion
	if ms.phase == "settle" and ms.settle and ms.settle.mode == "punish" and r.p:finished() then feed(r, { A }) end
	if r.which == "watch" then
		if cpuTurn and not r.sped and ts.mode == "aim" then
			r.sped = true
			feed(r, { B, { n = 1 }, B })
		end
		if cpuTurn and ts.mode == "aim" and ms.cpuWait > 0.05 and not r.shots.aim then
			r.shots.aim = true
			ctx:capture()
		end
		if cpuTurn and ts.mode == "flight" and ts.pb and ts.showTime > 0.4 and not r.shots.flight then
			r.shots.flight = true
			ctx:capture()
		end
		if ms.phase == "settle" and ms.settle and ms.settle.watch and ms.settle.mode == "raise"
			and ms.settle.wait < 0.3 and not r.shots.raise then
			r.shots.raise = true
			ctx:capture()
		end
	else
		local cpuRaise = ms.phase == "settle" and ms.settle and ms.settle.watch
		if (cpuTurn or cpuRaise) and not ms.watch.skipping and r.p:finished() then feed(r, { A }) end
		if ms.watch.skipping and cpuTurn and not r.shots.skip then
			r.shots.skip = true
			ctx:capture()
		end
	end
	return ms.phase == "over"
end

tw.selftest.scenarios["watch-skip"] = {
	step = function(ctx)
		if ctx.frame == 1 then
			playdate.display.setRefreshRate(0)
			ctx.run = run(ctx, "watch")
		end
		local r = ctx.run
		if stepRun(ctx, r) then
			local ms = r.ms
			if r.wrongTurn > 0 then error(r.which .. ": the view was on the wrong side " .. r.wrongTurn .. " frames") end
			if r.which == "watch" then
				if ms.watch.speed ~= 4 then error("SPEED did not step to 4X: " .. tostring(ms.watch.speed)) end
				if r.watched == 0 then error("the Playdate's raises were not shown") end
				if not (r.shots.aim and r.shots.flight and r.shots.raise) then error("frames missing in the watched run") end
				ctx.watched = cmatch.file(ms.m, nil, "selftest")
				ctx.watchedTurns, ctx.watchedFrames = ms.m.game.turn, r.watched
				ctx.run = run(ctx, "skip")
				return false
			end
			-- (each watched raise skipped on its first frames: A is pressed at once)
			if r.watched * 4 > ctx.watchedFrames then
				error("skipping still showed the Playdate's raises: " .. r.watched .. " frames")
			end
			if not r.shots.skip then error("no SKIPPING card") end
			local skipped = cmatch.file(ms.m, nil, "selftest")
			-- (the clock tags aside: the two runs start at different minutes)
			local function lines(text)
				local out = {}
				for l in text:gmatch("[^\n]+") do
					if not (l:match("^%[Date") or l:match("^%[Time") or l:match("^%[Duration") or l:match("^%[Start") or l:match("^%[End")) then out[#out + 1] = l end
				end
				return out
			end
			local a, b = lines(ctx.watched), lines(skipped)
			do
				for i = 1, math.max(#a, #b) do
					if a[i] ~= b[i] then
						error("skipped and watched differ at line " .. i .. ": " .. tostring(a[i]) .. " / " .. tostring(b[i]))
					end
				end
			end
			ctx.note = string.format("same file, %d turns, watched raise %d frames", ctx.watchedTurns, ctx.watchedFrames)
			return true
		end
		if ctx.frame > 60000 then error("not done by frame 60000 (" .. r.which .. ", " .. r.ms.phase .. ")") end
		return false
	end,
}
