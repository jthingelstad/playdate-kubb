-- Scenario "match-kid": a Kid match (engine 0.15, kubb-engine docs/notes/kid-mode.md)
-- against the Kid computer to a winner, as the options screen makes it (COMPUTER: KID
-- sets opts.rules = "kid"). The player's throws come from core/autothrow (seed 5), the
-- Playdate's through its own path; every throw is shown at rest at once.
-- Frames: 1 the hand-off card saying KID RULES, 2 the player's kubb thrown in from the
-- Kid line (KID LINE 2.0 M, the line drawn on the pitch and the minimap), 3 the
-- player's baton at a base kubb from the Kid line (three base kubbs), 4 the score
-- sheet, 5 the winner card.
-- The check: the game's rules are Kid, three base kubbs a side, every kubb and baton at
-- a kubb thrown from the Kid line (the king from the baseline), a person's throw planned
-- on the Kid meter, the computer at kid, the flag's words for the Kid rulings, and the
-- game file: [Base kubbs "3"], the Kid [Rules], [Throw Levels] naming the computer
-- only. Its game file is gated (file=...).
import "selftest/_match"
import "scenes/options"
import "render/hud"
import "core/throwplan"

local st = tw.selftest
local throw, hud, plan = tw.scenes.throw, tw.render.hud, tw.plan
local shot = { handoff = false, toss = false, baton = false, sheet = false }
local seen = {}
local sheetFrame = nil

-- the options screen's choice with COMPUTER on KID (the first value a press reaches)
local function kidOpts()
	local o = tw.scenes.options.new(tw.input.scripted({}), "vs", { scripted = true })
	o.choice.computer = 4
	local opts = tw.scenes.options.apply(o, { vs = "B", seed = 5, cpuSeed = 7, instant = true, maxTurns = 20,
		cpuThink = 0.12 })
	if opts.rules ~= "kid" or opts.computer ~= "kid" then error("KID did not make a Kid match") end
	-- PASS + PLAY keeps the standard rules whatever was kept
	o.mode = "match"
	local pp = tw.scenes.options.apply(o, {})
	if pp.rules ~= nil then error("pass and play took the Kid rules") end
	return opts
end

local function bases(s, half)
	local n = 0
	for _, p in ipairs(s.pieces) do if p.role == "base" and p.half == half then n = n + 1 end end
	return n
end

local function near(a, b) return a and b and math.abs(a - b) < 1e-6 end

local def = {
	refreshRate = 0,
	maxFrames = 30000,
	step = function(ms, ctx, h)
		local s, ts = ms.setup, ms.ts
		local g = ms.m.game
		if g.rules ~= "kid" then error("the match is not a Kid match") end
		if ms.m.ruling and ms.throws ~= seen.at then
			seen.at = ms.throws
			for _, part in ipairs(ms.m.ruling.parts or {}) do seen[part.code] = (seen[part.code] or 0) + 1 end
		end
		if ms.phase == "handoff" then
			if s and s.side == "B" then error("a hand-off card before the Playdate's turn") end
			if not ms.handoff.kid then error("the hand-off card does not say KID RULES") end
			if not shot.handoff then ctx:capture(); shot.handoff = true end
			if h.idle() then h.pressA() end
		end
		if ms.cpuAim and ms.cpuAim.plan.level ~= tw.autothrow.cpuLevel("kid") then
			error("the computer is not at kid")
		end
		if ms.phase == "play" and s and ts.mode == "aim" then
			if not s.kid or not ts.kid then error("the throw is not set up as a Kid throw") end
			if bases(s, "A") > 3 or bases(s, "B") > 3 then error("more than three base kubbs a side") end
			if not seen.first then
				seen.first = true
				if bases(s, "A") ~= 3 or bases(s, "B") ~= 3 then error("not three base kubbs a side at the start") end
			end
			if s.kingShot then
				if not near(s.forwardY, s.lineY) then error("a king shot from the Kid line") end
			elseif not (s.forwardY + 1e-6 >= s.kidY or near(s.forwardY, s.advY)) then
				error(string.format("thrown from %.2f, the Kid line is at %.2f", s.forwardY, s.kidY))
			end
			if s.side == "A" then
				local m, lv = throw.planBy(ts)
				if m ~= plan.meter("kid") or lv then error("a person's Kid throw is not on the Kid meter") end
				if not s.kingShot and not near(ts.playerY, s.forwardY) and not ts.stanceSet then
					error(string.format("the player stands at %.2f, not the line at %.2f", ts.playerY, s.forwardY))
				end
				if s.kind == "toss" and not shot.toss then
					if ts.advText ~= "KID LINE  2.0 M" then error("the flag says " .. tostring(ts.advText)) end
					ctx:capture(); shot.toss = true
				elseif s.kind == "baton" and not s.kingShot and not shot.baton and bases(s, "B") == 3 then
					ctx:capture(); shot.baton = true
				end
			end
		end
		if ms.phase == "over" then
			if not shot.sheet then
				if not sheetFrame then
					tw.scenes.match.showSheet(ms)
					sheetFrame = ctx.frame
				elseif ms.sheet then
					ctx:capture(); shot.sheet = true
					ms.sheet.done = true
					ms.sheet = nil
				end
				return false
			end
			if not ms.file then error("no game file: " .. tostring(ms.fileError)) end
			local f = playdate.file.open(ms.file)
			local text = f and f:read(8192) or ""
			if f then f:close() end
			if not text:find('[Base kubbs "3"]', 1, true) then error("the game file's base kubbs") end
			if not text:find('[Rules "Kid rules', 1, true) then error("the game file's rules") end
			local lv = text:match('%[Throw Levels "([^"]*)"%]')
			if not lv or not lv:find(" kid$") or lv:find(",") then error("[Throw Levels] " .. tostring(lv)) end
			-- the flag's words for the Kid rulings (whichever this match happened to make)
			local function want(line, flag)
				if hud.short(line) ~= flag then error(line .. " -> " .. tostring(hud.short(line))) end
			end
			want("king down: stood back up; kubb in for now", "KING STOOD BACK UP")
			want("out twice: stood at the fair spot", "OUT TWICE: STOOD UP FAIR")
			want("missed; king down early: stood back up", "KING STOOD BACK UP")
			want("field kubb down; king down early: stood back up", "1 DOWN: KING BACK UP")
			want("missed; helicopter: counted", "MISS")
			ctx:capture()
			local codes = {}
			for k, n in pairs(seen) do
				if k == "kingUp" or k == "placed" or k == "helicopterCounts" then codes[#codes + 1] = k .. "=" .. n end
			end
			table.sort(codes)
			ctx.note = ctx.note .. string.format(" turns=%d cpu=%d winner=%s kid=%s levels=%s file=%s", g.turn,
				ms.cpuThrows, g.winner, #codes > 0 and table.concat(codes, ",") or "none", lv:gsub(" ", "_"), ms.file)
			if not (shot.handoff and shot.toss and shot.baton) then
				error("missed a frame: handoff " .. tostring(shot.handoff) .. " toss " .. tostring(shot.toss)
					.. " baton " .. tostring(shot.baton))
			end
			return true
		end
		return false
	end,
}

-- the options are made when the scenario starts (the options screen's own code)
local inner = nil
st.scenarios["match-kid"] = {
	step = function(ctx)
		if not inner then
			def.opts = kidOpts()
			inner = st.matchScenario(def)
		end
		return inner.step(ctx)
	end,
}
