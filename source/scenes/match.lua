-- The match scene (stage 3): two teams, one Playdate, pass and play. The
-- rules engine (core/match over core/rules) decides what each throw is and
-- what it did; the throw scene (scenes/throw) aims, swings and runs the
-- physics, the same as on the practice pitch.
--
-- Phases:
--   handoff  the hand-off card (render/cards, from core/cards): pass the
--            Playdate to Team B, what Team A's batons took last turn, what
--            Team B throws now, the pitch as it stands; A: ready. Shown
--            before a team's first throw of each turn (and the match's first
--            throw).
--   play     the throw scene, set up for this throw (throw.prepare): Team B
--            sees the pitch turned 180 degrees (core/frame), so every throw is
--            made from the bottom of the screen. When the throw comes to rest
--            the match resolves it (the result line shows during the rest
--            hold); then the next throw is set up from the engine's state, so
--            the pitch shown is exactly the engine's (toppled kubbs leave it,
--            thrown kubbs lie where they stopped, in or out, until their round
--            is judged; out ones are then picked up for the rethrows, raised
--            kubbs stand, punishment kubbs appear).
--   settle   the defender raises the kubbs thrown in and places punishment
--            kubbs by hand (scenes/settle), between the attacker's kubb
--            tosses and its batons; scripted matches (seed, instant,
--            autoSettle) leave it to the engine
--   over     the winner card: who won and how, turns, minutes, the winner's
--            baton hit rate, whether the game file was written to games/ in
--            the Data folder (DESIGN 7). A: a new match (rematch), B: the
--            title.
--
-- The cards are full screen and drawn once into an image (render/cards);
-- while one shows, the pitch is not drawn.
--
-- System Menu "Match": resign (the team on turn gives up: G on its own turn;
-- it waits until no throw is in the air; chosen while the defender settles,
-- it is the defender's and waits for its turn) or title (leave: the match is
-- dropped, no file written).
--
-- VS PLAYDATE (opts.vs = "B"): the Playdate is Team B. Its throws come from
-- core/autothrow (scene.tune.cpuScatter, after scene.tune.cpuThink s of its
-- aim on screen), it raises and places punishment kubbs with the engine's
-- policies, there is no hand-off card before its turn, and the System Menu
-- resign always means the player (on the player's own turn).
--
-- Self-test options (scenes/match.new opts): seed (throws come from
-- core/autothrow, not the crank), instant (each throw is shown at rest at
-- once), skipHandoff, maxTurns (the attacker resigns past it).
import "CoreLibs/graphics"
import "core/tw"
import "core/match"
import "core/autothrow"
import "scenes/throw"
import "render/hud"
import "core/cards"
import "render/cards"
import "scenes/settle"
import "core/names"

local gfx <const> = playdate.graphics
local cmatch, autothrow = tw.match, tw.autothrow
local throw, hud = tw.scenes.throw, tw.render.hud
local cards, rcards = tw.cards, tw.render.cards
local settle = tw.scenes.settle

tw.scenes = tw.scenes or {}
local scene = {}

scene.version = playdate.metadata and playdate.metadata.version or "0.0.1"

scene.tune = {
	cpuThink = 0.9,      -- s the Playdate's aim shows before it throws
	cpuScatter = 1.0,    -- times core/autothrow's scatter (lower: a steadier opponent)
}

-- the teams: opts.names = { A = name, B = name } (scenes/names), else
-- "You" against "Playdate", or "Team A" and "Team B"
local function teams(opts)
	local n = opts.names or {}
	if opts.vs then return tw.names.teams { A = n.A or "You", B = "Playdate" } end
	if n.A and n.B then return tw.names.teams(n) end
	return nil
end

-- The time now as notation wants it.
local function now()
	local t = playdate.getTime()
	return { year = t.year, month = t.month, day = t.day, hour = t.hour, min = t.minute }
end

-- Write the game file; returns its path in the Data folder, or nil and why.
local function writeFile(s, finish)
	local text, name = cmatch.file(s.m, finish, scene.version)
	playdate.file.mkdir("games")
	local path = "games/" .. name
	-- two matches that start in the same minute share a name: keep both
	local n = 1
	while playdate.file.exists(path) do
		n = n + 1
		path = "games/" .. name:gsub("%.txt$", "") .. "-" .. n .. ".txt"
	end
	local f, err = playdate.file.open(path, playdate.file.kFileWrite)
	if not f then return nil, err end
	f:write(text)
	f:close()
	return path
end

local function over(s)
	s.phase = "over"
	s.setup = nil
	s.ts.readout = nil
	local finish = now()
	s.file, s.fileError = writeFile(s, finish)
	s.win = cards.winner(s.m, finish)
	s.winHow = cmatch.howText(s.m)
	s.card = nil
end

-- Set the next throw up (or end the match).
local function nextThrow(s)
	local m = s.m
	if s.opts.maxTurns and m.game.turn > s.opts.maxTurns and not cmatch.over(m) then cmatch.resign(m) end
	-- the defender raises kubbs and places punishment kubbs by hand first
	-- (scenes/settle); scripted matches leave it to the engine (match.setup)
	if s.byHand and not cmatch.over(m) then
		local n = m.game:need()
		if (n.kind == "raise" or n.kind == "punish") and n.side ~= s.cpu then
			s.phase = "settle"
			s.settle = settle.new(m.game, function(side) return string.upper(cmatch.teamName(side, m.game)) end, s.input)
			return
		end
	end
	local setup = (not cmatch.over(m)) and cmatch.setup(m) or nil
	if not setup then return over(s) end
	s.setup = setup
	s.resolved = false
	throw.prepare(s.ts, setup)
	s.ts.instant = s.opts.instant
	-- the rail: the team, this throw's pips and what is left to knock down
	local r1, r2
	if setup.kingShot then
		r1 = "KING"
	elseif setup.kind ~= "toss" then
		local field, base = 0, 0
		for _, p in ipairs(setup.pieces) do
			if not p.toppled and p.half ~= setup.side then
				if p.role == "field" then field = field + 1 elseif p.role == "base" then base = base + 1 end
			end
		end
		if field > 0 then r1 = throw.railField[field] or ("FIELD " .. field) end
		r2 = throw.railBase[base] or ("BASE " .. base)
		if not r1 then r1, r2 = r2, nil end
	end
	throw.setRail(s.ts, string.upper(cmatch.teamName(setup.side, m.game)), setup.projectile, setup.n, setup.of, r1, r2)
	if setup.side ~= s.side then
		-- a new turn: the other team takes the Playdate
		s.side = setup.side
		s.result = nil
		-- (no card before the Playdate's own turn)
		s.phase = (s.opts.skipHandoff or setup.side == s.cpu) and "play" or "handoff"
		if s.phase == "handoff" then
			s.handoff = cards.handoff(m, setup)
			s.card = nil
		end
	else
		s.phase = "play"
	end
	s.cpuWait, s.cpuAim = 0, nil
	s.ts.watching = s.cpu ~= nil and setup.side == s.cpu
end

function scene.new(provider, opts)
	local s = {
		input = provider,
		opts = opts or {},
		m = nil,
		ts = throw.new(provider),
		phase = "handoff",       -- "handoff" | "play" | "settle" | "over"
		side = nil,              -- the team the Playdate was last handed to
		setup = nil,             -- the current throw (core/match setup)
		resolved = false,        -- the current throw has been given to the engine
		result = nil,            -- what the last throw did (the HUD's second line)
		resignWanted = false,
		exit = nil,              -- "title" or "match" (a rematch) when the scene is done
		throws = 0,
		cpuThrows = 0,           -- the Playdate's throws (VS PLAYDATE)
	}
	-- raising and punishment kubbs by hand, except in scripted matches
	s.byHand = not (s.opts.seed or s.opts.instant or s.opts.autoSettle)
	s.cpu = s.opts.vs        -- the Playdate's side, or nil
	if s.cpu then
		s.m = cmatch.new { start = now(), surface = "Grass", teams = teams(s.opts), mode = "Vs Playdate" }
		s.cpuRng = autothrow.rng(s.opts.cpuSeed or playdate.getSecondsSinceEpoch())
	else
		s.m = cmatch.new { start = now(), surface = "Grass", teams = teams(s.opts) }
	end
	if s.opts.seed then s.rng = autothrow.rng(s.opts.seed) end
	s.ts.sceneName = "match"
	nextThrow(s)
	return s
end

-- System Menu "Match: resign": the team holding the Playdate resigns once
-- nothing is in the air. If that throw was its last and the turn has passed
-- by then, the request is dropped: a team resigns only on its own turn.
function scene.resign(s)
	if s.phase ~= "over" and s.setup then
		s.resignWanted = true
		if s.cpu then
			-- against the Playdate it is always the player who resigns, on
			-- the player's own turn
			s.resignSide, s.resignWait = (s.cpu == "A") and "B" or "A", true
		else
			-- while the defender raises it holds the Playdate: the resign is
			-- theirs, and waits for their own turn (the rules allow no other)
			s.resignSide = (s.phase == "settle") and s.settle.side or s.setup.side
			s.resignWait = s.phase == "settle"
		end
	end
end

function scene.update(s)
	local ts = s.ts
	if s.resignWanted and (s.phase == "handoff" or ts.mode == "aim" or ts.mode == "done") then
		s.resignWanted = false
		if not s.resolved and ts.mode == "done" then
			cmatch.resolve(s.m, ts.result, not ts.last.legal)
		end
		if cmatch.over(s.m) then return over(s) end
		if s.m.game.attacker == s.resignSide then
			s.resignWait = false
			cmatch.resign(s.m)
			return over(s)
		elseif s.resignWait then
			s.resignWanted = true   -- not that side's turn yet: wait for it
		end
	end
	if s.phase == "handoff" then
		s.input:advance()
		if s.input:pressed("a") then s.phase = "play" end
		return
	end
	if s.phase == "settle" then
		settle.update(s.settle)
		if s.settle.done then
			s.settle = nil
			nextThrow(s)
		end
		return
	end
	if s.phase == "over" then
		s.input:advance()
		if s.input:pressed("a") then s.exit = "rematch" elseif s.input:pressed("b") then s.exit = "title" end
		return
	end
	if ts.mode == "aim" and s.cpu and s.setup.side == s.cpu then
		-- the Playdate's throw: its aim shows a moment, then it throws
		ts.input:advance()
		if not s.cpuAim then
			-- choose now and show it: its stance and aim stay on screen while it thinks
			s.cpuAim = autothrow.choose(s.setup, s.cpuRng, scene.tune.cpuScatter)
			ts.watching = true
			throw.showAim(ts, s.cpuAim)
		end
		s.cpuWait = s.cpuWait + ts.input:dt()
		if s.cpuWait >= (s.opts.cpuThink or scene.tune.cpuThink) then
			s.cpuWait = 0
			s.cpuThrows = s.cpuThrows + 1
			local a = s.cpuAim
			s.cpuAim = nil
			throw.autoLaunch(ts, a)
		end
	elseif ts.mode == "aim" and s.rng then
		ts.input:advance()
		throw.autoLaunch(ts, autothrow.choose(s.setup, s.rng))
	else
		throw.update(ts)
	end
	if (ts.mode == "rest" or ts.mode == "done") and not s.resolved then
		-- the throw is at rest: the engine rules on it now, so its result
		-- shows during the rest hold
		cmatch.resolve(s.m, ts.result, not ts.last.legal)
		s.resolved = true
		s.result = s.m.text
		throw.setFlag(ts, hud.short(s.result))
		s.throws = s.throws + 1
	end
	if ts.mode == "done" then nextThrow(s) end
end

function scene.draw(s)
	s.ts.covered = (s.phase ~= "play")
	if s.phase == "over" or s.phase == "handoff" then
		-- a full-screen card, built once
		if not s.card then
			if s.phase == "over" then
				s.card = rcards.winner(s.win, s.winHow, s.file ~= nil)
			else
				s.card = rcards.handoff(s.handoff)
			end
		end
		s.card:draw(0, 0)
		return
	end
	s.card = nil
	if s.phase == "settle" then
		settle.draw(s.settle)
		return
	end
	throw.draw(s.ts)
end

function scene.enter()
	throw.enter()
end

tw.scenes.match = scene
