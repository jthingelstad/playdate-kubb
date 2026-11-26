-- Scenario "throw-level" (1.1.0, Kubb Engine 1.3): a person's throw level on the
-- clock. PASS + PLAY with Ash on HARD (teams.A.players[1].throw), then the same match
-- with Ash on EASY: Ash's first baton aimed by hand. Frames: 1 the aim on HARD (the
-- narrowest bars a person meets), 2 on EASY.
-- The check: each throw is planned on its player's meter (plan.meter(level)), and at
-- the same throw HARD's release bar is narrower than STANDARD's and EASY's bars are
-- wider; the game file's [Throw Levels] names the level.
import "core/tw"
import "core/names"
import "input"
import "scenes/match"
import "core/throwplan"

local scene, throw, plan = tw.scenes.match, tw.scenes.throw, tw.plan

local function make(level)
	local teams = tw.names.teams { A = "Ash", B = "Birch" }
	teams.A.players[1].throw = level
	local ms = scene.new(tw.input.scripted { { n = 200 } },
		{ teams = teams, names = { A = "Ash", B = "Birch" }, skipHandoff = true, noSave = true,
			togo = false, cpuSeed = 7 })
	scene.enter()
	return ms
end

local function check(ms, level)
	local ts, s = ms.ts, ms.setup
	if not s or s.side ~= "A" or s.kind ~= "baton" then error("not Ash's baton") end
	if ts.throwLevel ~= level then error("thrower's level " .. tostring(ts.throwLevel) .. ", not " .. level) end
	if throw.planBy(ts) ~= plan.meter(level) then error("not planned on the " .. level .. " meter") end
	local q = { projectile = "baton", px = ts.playerX, py = ts.playerY, tx = ts.markerX, ty = ts.markerY,
		release = ts.release, meter = plan.meter("standard") }
	local std = plan.solve(q, {})
	local levels = table.concat(tw.match.fileLevels(ms.m), ",")
	if not levels:find(level) then error("[Throw Levels] " .. levels) end
	return ts.sol.powerHi - ts.sol.powerLo, ts.sol.releaseHi - ts.sol.releaseLo,
		std.powerHi - std.powerLo, std.releaseHi - std.releaseLo
end

local ms, notes

tw.selftest.scenarios["throw-level"] = {
	step = function(ctx)
		local f = ctx.frame
		if f == 1 then ms = make("hard") end
		if f == 41 then ms = make("easy") end
		scene.update(ms)
		scene.draw(ms)
		if f == 30 then
			local lp, lr, sp, sr = check(ms, "hard")
			if not (lr < sr and lp <= sp) then error(string.format("HARD's bars %.1f/%.1f against %.1f/%.1f", lp, lr, sp, sr)) end
			notes = string.format("hard power %.1f release %.1f (standard %.1f, %.1f)", lp, lr, sp, sr)
			ctx:capture()
		elseif f == 70 then
			local lp, lr, sp, sr = check(ms, "easy")
			if not (lp > sp and lr > sr) then error("EASY's bars are not wider") end
			notes = notes .. string.format("; easy power %.1f release %.1f", lp, lr)
			ctx:capture()
			ctx.note = notes
			return true
		end
		return false
	end,
}
