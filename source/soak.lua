-- The device soak: whole matches on the Playdate with nobody pressing
-- anything, at the real pace of a match, to catch errors, memory growth and
-- slow frames over a long run (QA, not a benchmark).
--
-- A file named "soak" in the Data folder at launch runs it once before the
-- game (main.lua): soak.tune.matches scripted matches (core/autothrow
-- throws for both teams, seeded from the clock) through scenes/match exactly
-- as a player's: the throw scene's playback, slow motion, camera, bursts and
-- knocks, raising and punishment kubbs by the engine's policies, and the
-- resume save before every throw, under its own key ("soak-match") so a
-- player's saved match is never touched. Every saveCheck throws the save is
-- read back, unpacked and settled as match.setup settles the live one, and
-- must match the live engine. No game file is
-- written (games/ is left alone), and the crank recorder and frame-time log
-- are off, so traces.jsonl and frames.jsonl are not touched either.
--
-- Each frame's update and draw run under pcall: an error ends that match
-- and is logged with its traceback. Appended to soak.txt in the Data folder:
-- per match the turns, throws, how it ended, frames, the slowest frames
-- (wall time from one frame's start to the next, with the scene's phase and
-- the throw's mode), frames over 100 and 200 ms, memory after a full
-- collection before and after, the most memory seen, and the save checks;
-- then a summary and "soak done". Auto-lock is off while it runs.
import "core/tw"
import "core/save"
import "core/match"
import "scenes/match"
import "input"

local soak = {}
soak.flag = "soak"
soak.tune = {
	matches = 3,
	maxTurns = 24,      -- past this the team on turn resigns (a match is bounded)
	saveCheck = 7,      -- read the save back every this many throws
	slowest = 6,        -- slowest frames listed per match
	key = "soak-match", -- its own resume key
	sets = { "classic", "usa", "wisconsin" }, -- the kubb set of match 1, 2, 3, ... (render/world sets)
}

local match = tw.scenes.match

local function out(lines)
	local f = playdate.file.open("soak.txt", playdate.file.kFileAppend)
	if not f then return end
	for _, l in ipairs(lines) do f:write(l .. "\n") end
	f:close()
end

local function kb() return collectgarbage("count") end

local function stamp()
	local t = playdate.getTime()
	return string.format("%04d-%02d-%02d %02d:%02d", t.year, t.month, t.day, t.hour, t.minute)
end

-- The save read back must be the match as it is now.
local function checkSave(st)
	local d = playdate.datastore.read(soak.tune.key)
	if not d then return "no save" end
	local m = tw.save.unpack(d)
	if not m then return "unpack failed" end
	-- the save is made before match.setup settles the kubbs by the engine's
	-- policies (a scripted match); settle the copy the same way to compare
	tw.match.settle(m)
	local a, b = m.game, st.ms.m.game
	if a.turn ~= b.turn or a.attacker ~= b.attacker or a.phase ~= b.phase or a.batonsLeft ~= b.batonsLeft then
		return string.format("save turn %s %s %s %s, live %s %s %s %s", tostring(a.turn), tostring(a.attacker),
			tostring(a.phase), tostring(a.batonsLeft), tostring(b.turn), tostring(b.attacker), tostring(b.phase),
			tostring(b.batonsLeft))
	end
	return nil
end

local function newMatch(st)
	collectgarbage("collect")
	st.n = st.n + 1
	st.memStart, st.memMax = kb(), kb()
	st.frames, st.over100, st.over200, st.slow = 0, 0, 0, {}
	st.info = { update = 0, draw = 0, phys = 0, steps = 0, awake = 0, bodies = 0, mem = 0 }
	st.checks, st.checkFails, st.lastChecked = 0, {}, 0
	st.seed = playdate.getSecondsSinceEpoch() + st.n
	local sets = soak.tune.sets
	st.set = sets[(st.n - 1) % #sets + 1]
	st.ms = match.new(st.input, { seed = st.seed, skipHandoff = true, noFile = true, saveKey = soak.tune.key,
		maxTurns = soak.tune.maxTurns, set = st.set })
	match.enter()
	st.last = nil
end

-- the slowest frames: a short list kept sorted, slowest first
local function noteFrame(st, ms, what)
	local list, k = st.slow, soak.tune.slowest
	if #list == k and ms <= list[k][1] then return end
	local i = #list + 1
	if i > k then i = k end
	list[i] = { ms, what }
	while i > 1 and list[i][1] > list[i - 1][1] do
		list[i], list[i - 1] = list[i - 1], list[i]
		i = i - 1
	end
end

local function endMatch(st, why)
	local ms = st.ms
	local g = ms.m.game
	collectgarbage("collect")
	local lines = {
		string.format("match %d (seed %d, %s set): %s; turn %d, throws %d, winner %s (%s)", st.n, st.seed,
			tostring(st.set), why, g.turn, ms.throws, tostring(g.winner), tostring(g.how)),
		string.format("  frames %d, over 100 ms %d, over 200 ms %d; memory %.0f KB -> %.0f KB after collection, most %.0f KB",
			st.frames, st.over100, st.over200, st.memStart, kb(), st.memMax),
		string.format("  save checks %d, failed %d", st.checks, #st.checkFails),
	}
	for _, f in ipairs(st.checkFails) do lines[#lines + 1] = "    " .. f end
	local parts = {}
	for _, s in ipairs(st.slow) do parts[#parts + 1] = string.format("%.0f %s", s[1], s[2]) end
	lines[#lines + 1] = "  slowest ms:"
	for _, p in ipairs(parts) do lines[#lines + 1] = "    " .. p end
	out(lines)
	st.totalFrames = st.totalFrames + st.frames
	st.totalOver200 = st.totalOver200 + st.over200
	if why ~= "finished" then st.errors = st.errors + 1 end
	playdate.datastore.delete(soak.tune.key)
	playdate.display.setInverted(false)
end

function soak.start()
	playdate.file.delete(soak.flag)
	local rec = tw.recorder
	local st = { n = 0, recOn = rec.on, logOn = tw.framelog.on, input = tw.input.device(),
		totalFrames = 0, totalOver200 = 0, errors = 0, t0 = playdate.getCurrentTimeMilliseconds() }
	rec.on = false
	rec.clear()
	tw.framelog.on = false
	playdate.setAutoLockDisabled(true)
	out { "", string.format("soak %s: %d matches, max %d turns; memory %.0f KB", stamp(), soak.tune.matches,
		soak.tune.maxTurns, kb()) }
	local ok, err = xpcall(newMatch, debug.traceback, st)
	if not ok then
		out { "match 1: error setting up: " .. tostring(err) }
		st.errors = st.errors + 1
		st.failedStart = true
	end
	return st
end

local function finish(st)
	out { string.format("soak summary: %d matches, %d ended by an error, %d frames, %d over 200 ms, %.1f min",
		st.n, st.errors, st.totalFrames, st.totalOver200, (playdate.getCurrentTimeMilliseconds() - st.t0) / 60000),
		"soak done" }
	local rec = tw.recorder
	rec.clear()
	rec.on = st.recOn
	tw.framelog.on = st.logOn
	playdate.setAutoLockDisabled(tw.noLock and true or false)   -- main.lua's "nolock"
	return true
end

-- One frame, and where its time went: the update (of it the physics,
-- playback.busy, and its steps), the draw, the bodies awake and how much
-- the heap grew (allocation less whatever the collector freed in the frame). Numbers only: a label is made only for a frame
-- slow enough to list.
local clockMs = playdate.getCurrentTimeMilliseconds
local function frame(st)
	local ms = st.ms
	local pb = ms.ts and ms.ts.pb
	local b0, s0 = pb and pb.busy or 0, pb and pb.steps or 0
	local m0 = collectgarbage("count")
	local t0 = clockMs()
	match.update(ms)
	local t1 = clockMs()
	match.draw(ms)
	local f = st.info
	f.update, f.draw = t1 - t0, clockMs() - t1
	local pb2 = ms.ts and ms.ts.pb
	if pb2 and pb2 == pb then
		f.phys, f.steps = (pb.busy - b0) * 1000, pb.steps - s0
		f.awake, f.bodies = pb.w.awakeCount or 0, pb.w.n
	else
		f.phys, f.steps, f.awake, f.bodies = 0, 0, 0, 0
	end
	f.mem = collectgarbage("count") - m0  -- KB the heap grew this frame (net)
end

-- One frame. Returns true when finished.
function soak.update(st)
	if st.failedStart then return finish(st) end
	local now = playdate.getCurrentTimeMilliseconds()
	local ms = st.ms
	if st.last then
		local dt = now - st.last
		st.frames = st.frames + 1
		if dt > 100 then st.over100 = st.over100 + 1 end
		if dt > 200 then st.over200 = st.over200 + 1 end
		local list = st.slow
		if #list < soak.tune.slowest or dt > list[#list][1] then
			local f = st.info
			local what = (st.p0 == "play") and ("play/" .. tostring(st.m0)) or tostring(st.p0)
			if st.p1 ~= st.p0 or st.m1 ~= st.m0 then
				what = what .. " -> " .. ((st.p1 == "play") and tostring(st.m1) or tostring(st.p1))
			end
			noteFrame(st, dt, string.format("%s (update %.0f, phys %.0f in %.0f steps, draw %.0f; awake %.0f of %.0f; mem %+.0f KB)",
				what, f.update, f.phys, f.steps, f.draw, f.awake, f.bodies, f.mem))
		end
	end
	st.last = now
	-- what this frame is doing, for the slowest-frames list: the phase and
	-- throw mode at its start and at its end (a throw's landing frame reads
	-- play/flight -> rest). No strings are made unless the frame is listed.
	st.p0, st.m0 = ms.phase, ms.ts and ms.ts.mode
	local ok, err = xpcall(frame, debug.traceback, st)
	st.p1, st.m1 = ms.phase, ms.ts and ms.ts.mode
	local m = kb()
	if m > st.memMax then st.memMax = m end
	if not ok then
		out { "  error: " .. tostring(err) }
		endMatch(st, "error")
	elseif ms.phase == "over" then
		endMatch(st, "finished")
	else
		-- the save read back every saveCheck throws (persist runs before each)
		if ms.throws - st.lastChecked >= soak.tune.saveCheck and ms.ts.mode == "aim" then
			st.lastChecked = ms.throws
			st.checks = st.checks + 1
			local c0 = playdate.getCurrentTimeMilliseconds()
			local ok2, bad = pcall(checkSave, st)
			if not ok2 then bad = "check failed: " .. tostring(bad) end
			if bad then st.checkFails[#st.checkFails + 1] = "throw " .. ms.throws .. ": " .. bad end
			-- the check's own time is not part of this frame (the frame's own
			-- update and draw still are)
			st.last = st.last + (playdate.getCurrentTimeMilliseconds() - c0)
		end
		return false
	end
	-- the next match (its setup under the same guard: an error there is logged
	-- and ends the soak, it does not stop the game)
	while st.n < soak.tune.matches do
		local okNew, errNew = xpcall(newMatch, debug.traceback, st)
		if okNew then return false end
		out { string.format("match %d: error setting up: %s", st.n, tostring(errNew)) }
		st.errors = st.errors + 1
	end
	return finish(st)
end

tw.soak = soak
