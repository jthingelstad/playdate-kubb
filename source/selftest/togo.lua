-- Scenario "togo" (1.1.0): the throw to go (scenes/match phase "togo", core/togo).
-- Part 1, VS PLAYDATE (the player's baton from seed 5, the Playdate's from cpuSeed 7,
-- each shown at rest at once): the card before the player's baton, A, the player's
-- baton, then the Playdate's from the player's end, the verdict card, A, and turn 1
-- starts with the side it gave (match.setFirst); the match resigns at turn 2 and its
-- game file says how the first thrower was decided ([Engine:first], gated: file=...).
-- Part 2, PASS + PLAY: both batons, a tie forced on the verdict (equal millimetres):
-- "TIE: THROW AGAIN", A, and round 2's card passes the Playdate.
-- Part 3, a save during the throw to go (the self-test key): marked `togo`, and a
-- resume from it throws to go again from round 1; THROW TO GO off saves `togoOff`.
-- Frames: 1 the card before the player's baton, 2 the Playdate's baton to go aimed,
-- 3 the verdict, 4 the tie, 5 round 2's card.
import "core/tw"
import "input"
import "core/save"
import "scenes/match"
import "core/match"
import "core/togo"
import "core/pitch"

local scene, cmatch, save = tw.scenes.match, tw.match, tw.save
local A = { press = { "a" } }

local function feedA(r) r.p.steps, r.p.i, r.p.k = { { n = 1 }, A }, 1, 0 end

local function new(opts)
	local p = tw.input.scripted({})
	local ms = scene.new(p, opts)
	scene.enter()
	playdate.display.setRefreshRate(0)
	return { ms = ms, p = p }
end

tw.selftest.scenarios.togo = {
	step = function(ctx)
		local f = ctx.frame
		if f == 1 then
			ctx.part = 1
			ctx.r = new { vs = "B", seed = 5, cpuSeed = 7, instant = true, cpuThink = 0.12, togo = true, maxTurns = 1,
				computer = "club" }
			local ms = ctx.r.ms
			if ms.phase ~= "togo" or ms.tg.mode ~= "card" or ms.tg.side ~= "A" then
				error("VS PLAYDATE: no card before the player's baton to go")
			end
			-- the circle starts short of the king and may go nearer than the drill area's
			-- 3.5 m (the throw's own markerNear, 2 m; Codex on #169)
			local ts, king = ms.ts, tw.pitch.king
			local y0 = king.y - tw.togo.tune.markerShort
			if math.abs(ts.markerY - y0) > 1e-6 then error(string.format("the circle starts at %.2f, not %.2f", ts.markerY, y0)) end
			tw.scenes.throw.aimAt(ts, 0.3, y0)
			if math.abs(ts.markerY - y0) > 1e-6 then error(string.format("a move across put the circle at %.2f", ts.markerY)) end
			tw.scenes.throw.aimAt(ts, 0, 1)
			if math.abs(ts.markerY - 2) > 1e-6 then error(string.format("the circle went to %.2f, under 2 m", ts.markerY)) end
			tw.scenes.throw.setTogo(ts)
			ctx.got = {}
		end
		local r = ctx.r
		local ms = r.ms
		scene.update(ms)
		scene.draw(ms)
		if ctx.part == 1 then
			local tg = ms.tg
			if tg and tg.mode == "card" and not ctx.got.card then
				ctx.got.card = true
				ctx:capture()
			end
			if ((tg and tg.mode ~= "throw") or ms.phase == "handoff" or ms.phase == "pass") and r.p:finished() then feedA(r) end
			if tg and tg.mode == "throw" and tg.side == "B" then
				if not ms.ts.turned then error("the Playdate's baton to go was not seen from the player's end") end
				if ms.ts.mode == "aim" and ms.cpuWait > 0.05 and not ctx.got.aim then
					ctx.got.aim = true
					ctx:capture()
				end
			end
			if tg and tg.mode == "verdict" and not ctx.got.verdict then
				ctx.got.verdict = true
				ctx.first = tg.v.first
				ctx.again = tg.v.how == "again"
				ctx.text = ms.result
				ctx:capture()
			end
			if ms.phase ~= "togo" and ms.phase ~= "over" and not ctx.started then
				ctx.started = true
				local g = ms.m.game
				if not g.firstBy then error("no firstBy after the throw to go") end
				if g.attacker ~= ctx.first then error("turn 1 is " .. g.attacker .. "'s, the verdict said " .. ctx.first) end
			end
			if ms.phase == "over" then
				if not (ctx.got.card and ctx.got.aim and ctx.got.verdict) then error("part 1 frames missing") end
				if not ms.file then error("no game file: " .. tostring(ms.fileError)) end
				local fh = playdate.file.open(ms.file)
				local text = fh and fh:read(8192) or ""
				if fh then fh:close() end
				if not text:find("%[Engine:first ") then error("the game file has no [Engine:first]") end
				ctx.note = string.format("vs: %s (%s)", ctx.text or "?", ctx.first)
				ctx.file = ms.file
				-- part 2: PASS + PLAY, a tie
				ctx.part = 2
				ctx.r = new { seed = 3, instant = true, togo = true, noSave = true, noFile = true,
					names = { A = "Ash", B = "Birch" } }
				if ctx.r.ms.phase ~= "togo" then error("PASS + PLAY: no throw to go") end
				if ctx.r.ms.tg.card.pass then error("PASS + PLAY: the first card passes the Playdate") end
			end
			if f > 3000 then
				error(string.format("part 1 not done: phase %s tg %s mode %s side %s ts %s turn %d", ms.phase,
					tostring(ms.tg and ms.tg.round), tostring(ms.tg and ms.tg.mode), tostring(ms.tg and ms.tg.side),
					ms.ts.mode, ms.m.game.turn))
			end
			return false
		end
		if ctx.part == 2 then
			local tg = ms.tg
			if tg and tg.mode == "card" and tg.side == "B" and tg.round == 1 and not tg.card.pass then
				error("PASS + PLAY: B's card does not pass the Playdate")
			end
			if tg and tg.mode == "verdict" and not ctx.tied then
				-- equal millimetres: a tie
				ctx.tied = true
				tg.e.A = { gap = 0.5, toppled = false }
				tg.e.B = { gap = 0.5004, toppled = false }
				scene.togoVerdict(ms)
				if ms.tg.v.how ~= "again" or ms.tg.card.head ~= "TIE: THROW AGAIN" then
					error("a tie did not say TIE: THROW AGAIN: " .. tostring(ms.tg.card.head))
				end
				ms.card = nil
				scene.draw(ms)
				ctx:capture()
			end
			if tg and tg.round == 2 and tg.mode == "card" and not ctx.round2 then
				ctx.round2 = true
				if not tg.card.pass then error("round 2's card does not pass the Playdate") end
				ctx:capture()
			end
			if tg and tg.mode ~= "throw" and r.p:finished() then feedA(r) end
			if ctx.round2 then
				-- part 3: a save during the throw to go
				ctx.part = 3
				local key = scene.saveKey()
				playdate.datastore.delete(key)
				local r3 = new { seed = 4, togo = true, saveKey = key, noFile = true, names = { A = "Ash", B = "Birch" } }
				local d = playdate.datastore.read(key)
				if not (type(d) == "table" and d.togo == true) then error("the save made during the throw to go is not marked") end
				local m = save.unpack(d)
				if not m then error("the save does not read back") end
				local r4 = new { seed = 4, togo = true, saveKey = key, noFile = true, names = { A = "Ash", B = "Birch" },
					resume = m, togoPending = d.togo }
				if r4.ms.phase ~= "togo" or r4.ms.tg.round ~= 1 then error("the resume did not throw to go again") end
				local r5 = new { seed = 4, togo = false, saveKey = key, noFile = true, names = { A = "Ash", B = "Birch" } }
				if r5.ms.phase == "togo" then error("THROW TO GO OFF threw to go") end
				d = playdate.datastore.read(key)
				if not (type(d) == "table" and d.togoOff and not d.togo) then error("OFF was not saved as togoOff") end
				playdate.datastore.delete(key)
				ctx.note = ctx.note .. "; tie: throw again, round 2; a save mid-way throws again; file=" .. ctx.file
				return true
			end
			if f > 6000 then error("part 2 not done") end
			return false
		end
		return false
	end,
}
