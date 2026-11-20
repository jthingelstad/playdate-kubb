-- Scenario "auto-raise": raising for the rest of the game (scenes/settle's
-- B, REST OF GAME; scenes/match's s.autoRaise and its "-raise" file), six a
-- side in PASS + PLAY, then against the Playdate.
--
-- Part 1, B's raise at turn 3 (A tossed a1 and a2 in, lying): the pass card,
-- A, then B, REST OF GAME: a1 is raised at once, a2 by itself after the
-- wait, and the choice is saved beside the match. Frames: 1 the raise view
-- with REST OF GAME, 2 the automatic view with BY HAND.
-- Part 2, A's raise at turn 4, resumed from the datastore: the match raises
-- by itself with no pass card and no input; after its first kubb B, BY HAND,
-- gives it back: the "-raise" file is gone, the pass card comes, and the
-- rest are raised by hand with A. Frame 3: the automatic view of the resumed
-- match.
-- Part 3, VS PLAYDATE, A's raise at turn 4: no card, B raises them all;
-- Match: resign after it is the player's, as always.
-- Part 4, PASS + PLAY resumed into A's raise at turn 4 while the game raises:
-- no pass card, so B (the attacker) holds the Playdate, and Match: resign
-- is B's (scene.holder): A wins, and the game file is gated (file=...).
-- Frame 4: the automatic raise at the resign.
-- The check, each part: every kubb stands where the same match raised by
-- hand on the engine's ends (g:raise(nil) on a copy) stands it, and the
-- score sheet is the same line for line. Self-test keys only
-- (selftest-match, selftest-match-raise), deleted afterwards.
import "core/tw"
import "core/save"
import "core/match"
import "core/notation"
import "scenes/match"
import "input"

local scene, cmatch, save, notation = tw.scenes.match, tw.match, tw.save, tw.notation
local MISS = {}

local function six(name)
	local p = {}
	for i = 1, 6 do p[i] = { name = name .. i } end
	return { name = name, players = p }
end
local TEAMS = { A = six("Ash"), B = six("Birch") }
local START = { year = 2026, month = 11, day = 20, hour = 21, min = 5 }

local function lying(x, y, a) return { rest = { x = x, y = y, standing = false, angle = a }, moved = {} } end

-- the engine to B's raise at turn 3: a1 and a2 lying in B's half
local function toTurn3(g)
	g:throwBaton(MISS); g:throwBaton(MISS)
	g:throwBaton({ toppled = { "a1" } }); g:throwBaton({ toppled = { "a2" } }); g:throwBaton(MISS); g:throwBaton(MISS)
	g:toss(lying(0.5, 6.0, 0.4))
	g:toss(lying(-0.8, 5.5, 1.2))
	if g:need().kind ~= "raise" or g:need().side ~= "B" then error("expected B's raise, got " .. g:need().kind) end
end

-- from A's batons at turn 3 to A's raise at turn 4: B's kubbs lying in A's half
local function toTurn4(g)
	g:throwBaton({ toppled = { "a1" } }); g:throwBaton({ toppled = { "a2" } }); g:throwBaton({ toppled = { "b1" } })
	g:throwBaton(MISS); g:throwBaton(MISS); g:throwBaton(MISS)
	local xs, i = { 0.3, -0.6, 0.9, 0.0 }, 1
	while g.phase == "toss" do
		g:toss(lying(xs[i] or 0, 1.6 + i * 0.4, 0.7 * i))
		i = i + 1
	end
	if g:need().kind ~= "raise" or g:need().side ~= "A" then error("expected A's raise, got " .. g:need().kind) end
end

-- a copy of match m through the save (the datastore's own JSON round trip
-- is the resume's; this is the same tables), raised by hand on the engine's ends
local function handCopy(m)
	return (save.unpack(save.pack(m, {})))
end
local function raiseAllByHand(c)
	local n = 0
	while c.game:need().kind == "raise" do c.game:raise(nil); n = n + 1 end
	-- (as the match scene does next: the throw set up, the pitch settled)
	cmatch.setup(c)
	return n
end

-- the same pitch and score sheet, or an error
local function same(m, c, what)
	for id, k in pairs(c.game.kubbs) do
		local a, b = m.game.kubbs[id].pose, k.pose
		if a.standing ~= b.standing or math.abs(a.x - b.x) > 1e-9 or math.abs(a.y - b.y) > 1e-9
			or math.abs((a.angle or 0) - (b.angle or 0)) > 1e-9 then
			error(string.format("%s: %s stands at %.3f %.3f %s, by hand %.3f %.3f %s", what, id, a.x, a.y,
				tostring(a.standing), b.x, b.y, tostring(b.standing)))
		end
	end
	local ta, tb = m.game.sheet.turns, c.game.sheet.turns
	if #ta ~= #tb then error(what .. ": " .. #ta .. " turns on the sheet, by hand " .. #tb) end
	for i = 1, #ta do
		if notation.turnLine(ta[i]) ~= notation.turnLine(tb[i]) then
			error(what .. ": turn " .. i .. " reads " .. notation.turnLine(ta[i]) .. ", by hand " .. notation.turnLine(tb[i]))
		end
	end
	if m.game.phase ~= c.game.phase or m.game.turn ~= c.game.turn then error(what .. ": the engine moved on differently") end
end

local function raiseFile() return playdate.datastore.read(scene.raiseKey(scene.saveKey())) end
local function clean()
	playdate.datastore.delete(scene.saveKey())
	playdate.datastore.delete(scene.raiseKey(scene.saveKey()))
end

local A, B = { press = { "a" } }, { press = { "b" } }

tw.selftest.scenarios["auto-raise"] = {
	step = function(ctx)
		local f = ctx.frame
		if f == 1 then
			clean()
			local m = cmatch.new { start = START, teams = TEAMS }
			toTurn3(m.game)
			ctx.hand = handCopy(m)
			ctx.ms = scene.new(tw.input.scripted { { n = 2 }, A, { n = 3 }, B },
				{ teams = TEAMS, resume = m })
			scene.enter()
			if ctx.ms.phase ~= "settle" or not ctx.ms.settleCard then error("no pass card before B's raise") end
			if ctx.ms.autoRaise.on then error("raising for itself before REST OF GAME") end
			ctx.part = 1
			return false
		end
		local ms = ctx.ms
		scene.update(ms)
		scene.draw(ms)
		if ctx.part == 1 then
			local st = ms.settle
			if f == 7 then
				if ms.settleCard or not st or st.auto.on then error("not on the raise view by hand at frame 7") end
				ctx:capture()
			end
			if f == 8 then
				if not ms.autoRaise.on then error("REST OF GAME did not turn it on") end
				if st.raised ~= 1 then error("REST OF GAME did not raise the kubb on screen at once") end
				local d = raiseFile()
				if not (d and d.raise == "auto" and d.start) then error("the choice was not saved beside the match") end
			end
			if f == 11 then ctx:capture() end
			if ms.phase ~= "settle" then
				if f < 30 then error("the second kubb was raised before the wait") end
				ctx.note = "B: " .. raiseAllByHand(ctx.hand) .. " raised, 1 at once"
				same(ms.m, ctx.hand, "B's raise")
				local m = save.unpack(playdate.datastore.read(scene.saveKey()))
				if not (m and m.game.kubbs.a1.pose.standing and m.game.kubbs.a2.pose.standing) then
					error("the raises were not saved")
				end
				-- part 2: on to A's raise at turn 4 and saved, as a device left mid-match
				toTurn4(m.game)
				tw.save.write(m, { teams = TEAMS }, function(d) playdate.datastore.write(d, scene.saveKey()) end)
				local r = save.unpack(playdate.datastore.read(scene.saveKey()))
				ctx.hand = handCopy(r)
				ctx.ms = scene.new(tw.input.scripted { { n = 40 }, B, { n = 3 }, A, { n = 3 }, A, { n = 3 }, A, { n = 3 }, A },
					{ teams = TEAMS, resume = r })
				scene.enter()
				if not ctx.ms.autoRaise.on then error("the resumed match forgot REST OF GAME") end
				if ctx.ms.phase ~= "settle" or ctx.ms.settleCard then error("a pass card before the game's own raise") end
				ctx.part, ctx.p2 = 2, f
			end
			if f > 80 then error("B's raise not done by frame 80") end
			return false
		end
		if ctx.part == 2 then
			local st, k = ms.settle, f - ctx.p2
			if k == 5 then ctx:capture() end
			if k == 39 then
				if not st or st.raised ~= 1 then error("the resumed match did not raise its first kubb by itself") end
				if not raiseFile() then error("the -raise file went early") end
			end
			if k == 41 then
				if ms.autoRaise.on then error("BY HAND did not turn it off") end
				if raiseFile() then error("BY HAND left the -raise file") end
				if not ms.settleCard then error("no pass card after BY HAND") end
				if st.raised ~= 1 then error("BY HAND raised a kubb") end
			end
			if ms.phase ~= "settle" then
				local n = raiseAllByHand(ctx.hand)
				same(ms.m, ctx.hand, "A's raise")
				ctx.note = ctx.note .. "; A resumed: 1 of " .. n .. " by itself"
				clean()
				-- part 3: VS PLAYDATE, A's raise at turn 4
				local m = cmatch.new { start = START, teams = TEAMS, mode = "Vs Playdate" }
				toTurn3(m.game)
				while m.game:need().kind == "raise" do m.game:raise(nil) end
				toTurn4(m.game)
				ctx.hand = handCopy(m)
				ctx.ms = scene.new(tw.input.scripted { { n = 2 }, B },
					{ teams = TEAMS, vs = "B", resume = m, cpuSeed = 1 })
				scene.enter()
				if ctx.ms.phase ~= "settle" or ctx.ms.settleCard then error("VS PLAYDATE: not straight to the raise") end
				ctx.part, ctx.p3 = 3, f
			end
			if k > 200 then error("A's raise not done") end
			return false
		end
		if ctx.part == 3 then
			if ms.settleCard then error("VS PLAYDATE: a pass card") end
			if ms.phase ~= "settle" then
				if not raiseFile() then error("VS PLAYDATE: REST OF GAME not saved") end
				local n = raiseAllByHand(ctx.hand)
				same(ms.m, ctx.hand, "VS PLAYDATE")
				ctx.note = ctx.note .. "; vs Playdate: " .. n .. " by itself"
				-- VS PLAYDATE: a resign while the Playdate raises is still the player's
				scene.resign(ms)
				if ms.resignSide ~= "A" then error("VS PLAYDATE: the resign went to " .. tostring(ms.resignSide)) end
				ms.resignWanted = false
				clean()
				-- part 4: PASS + PLAY, a match resumed into A's raise at turn 4 while the
				-- game raises (no pass card: B, the attacker, still holds the Playdate);
				-- Match: resign then is B's, and A wins
				local m4 = cmatch.new { start = START, teams = TEAMS }
				toTurn3(m4.game)
				while m4.game:need().kind == "raise" do m4.game:raise(nil) end
				toTurn4(m4.game)
				playdate.datastore.write({ start = "2026-11-20 21:5", raise = "auto" }, scene.raiseKey(scene.saveKey()))
				ctx.ms = scene.new(tw.input.scripted { { n = 400 } }, { teams = TEAMS, resume = m4 })
				scene.enter()
				if not ctx.ms.autoRaise.on or ctx.ms.settleCard then error("resign part: not raising by itself") end
				if scene.holder(ctx.ms) ~= "B" then error("resign part: the holder is " .. tostring(scene.holder(ctx.ms))) end
				ctx.part, ctx.p4 = 4, f
			end
			if f - ctx.p3 > 200 then error("VS PLAYDATE: A's raise not done") end
			return false
		end
		if ctx.part == 4 then
			local k = f - ctx.p4
			if k == 3 then
				if ms.phase ~= "settle" then error("resign part: the raise ended before the resign") end
				scene.resign(ms)
				if ms.resignSide ~= "B" then error("resign during the game's raise went to " .. tostring(ms.resignSide)) end
				ctx:capture()
			end
			if ms.settleCard then error("resign part: a pass card") end
			if ms.phase == "over" then
				local g = ms.m.game
				if g.winner ~= "A" then error("B resigned, but the winner is " .. tostring(g.winner)) end
				if not ms.file then error("no game file: " .. tostring(ms.fileError)) end
				if raiseFile() then error("the finished match left its -raise file") end
				ctx.note = ctx.note .. "; resign in the game's raise: B's, A won, file=" .. ms.file
				clean()
				return true
			end
			if k > 300 then error("resign part: not over (" .. ms.phase .. ")") end
			return false
		end
	end,
}
