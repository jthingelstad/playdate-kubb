-- The match scene (stage 3): two teams, one Playdate, pass and play. The
-- rules engine (core/match over core/rules) decides what each throw is and
-- what it did; the throw scene (scenes/throw) aims, swings and runs the
-- physics, the same as on the practice pitch.
--
-- Phases:
--   handoff  a card "Team B" / "press A": the Playdate goes to the other team.
--            Shown before a team's first throw of each turn (and the match's
--            first throw).
--   play     the throw scene, set up for this throw (throw.prepare): Team B
--            sees the pitch turned 180 degrees (core/frame), so every throw is
--            made from the bottom of the screen. When the throw comes to rest
--            the match resolves it (the result line shows during the rest
--            hold); then the next throw is set up from the engine's state, so
--            the pitch shown is exactly the engine's (toppled kubbs leave it,
--            thrown kubbs lie where they stopped, in or out, until their round
--            is judged; out ones are then picked up for the rethrows, raised
--            kubbs stand, punishment kubbs appear).
--   over     the winner card; the game file has been written to games/ in the
--            Data folder (DESIGN 7). A goes back to the title.
--
-- System Menu "Match": resign (the team on turn gives up: G on its own turn;
-- it waits until no throw is in the air) or title (leave: the match is
-- dropped, no file written).
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

local gfx <const> = playdate.graphics
local cmatch, autothrow = tw.match, tw.autothrow
local throw, hud = tw.scenes.throw, tw.render.hud

tw.scenes = tw.scenes or {}
local scene = {}

scene.version = playdate.metadata and playdate.metadata.version or "0.0.1"

-- The time now as notation wants it.
local function now()
	local t = playdate.getTime()
	return { year = t.year, month = t.month, day = t.day, hour = t.hour, min = t.minute }
end

-- Write the game file; returns its path in the Data folder, or nil and why.
local function writeFile(s)
	local text, name = cmatch.file(s.m, now(), scene.version)
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
	s.winTitle = cmatch.teamName(s.m.game.winner) .. " wins"
	s.winHow = cmatch.howText(s.m)
	s.file, s.fileError = writeFile(s)
end

-- Set the next throw up (or end the match).
local function nextThrow(s)
	local m = s.m
	if s.opts.maxTurns and m.game.turn > s.opts.maxTurns and not cmatch.over(m) then cmatch.resign(m) end
	local setup = (not cmatch.over(m)) and cmatch.setup(m) or nil
	if not setup then return over(s) end
	s.setup = setup
	s.resolved = false
	throw.prepare(s.ts, setup)
	s.ts.instant = s.opts.instant
	if setup.side ~= s.side then
		-- a new turn: the other team takes the Playdate
		s.side = setup.side
		s.result = nil
		s.handoffTitle = cmatch.teamName(setup.side)
		s.phase = s.opts.skipHandoff and "play" or "handoff"
	else
		s.phase = "play"
	end
end

function scene.new(provider, opts)
	local s = {
		input = provider,
		opts = opts or {},
		m = nil,
		ts = throw.new(provider),
		phase = "handoff",       -- "handoff" | "play" | "over"
		side = nil,              -- the team the Playdate was last handed to
		setup = nil,             -- the current throw (core/match setup)
		resolved = false,        -- the current throw has been given to the engine
		result = nil,            -- what the last throw did (the HUD's second line)
		resignWanted = false,
		exit = nil,              -- "title" when the scene is done
		throws = 0,
	}
	s.m = cmatch.new { start = now(), surface = "Grass" }
	if s.opts.seed then s.rng = autothrow.rng(s.opts.seed) end
	s.ts.readoutY = hud.belowStatus(2)
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
		s.resignSide = s.setup.side
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
			cmatch.resign(s.m)
			return over(s)
		end
	end
	if s.phase == "handoff" then
		s.input:advance()
		if s.input:pressed("a") then s.phase = "play" end
		return
	end
	if s.phase == "over" then
		s.input:advance()
		if s.input:pressed("a") then s.exit = "title" end
		return
	end
	if ts.mode == "aim" and s.rng then
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
		s.throws = s.throws + 1
	end
	if ts.mode == "done" then nextThrow(s) end
end

function scene.draw(s)
	s.ts.covered = (s.phase ~= "play")
	if s.phase == "over" then
		throw.draw(s.ts)
		hud.card(s.winTitle, s.winHow, "press A")
		return
	end
	throw.draw(s.ts)
	if s.setup then hud.status(s.setup.label, s.result) end
	if s.phase == "handoff" then hud.card(s.handoffTitle, "your turn: press A") end
end

function scene.enter()
	throw.enter()
end

tw.scenes.match = scene
