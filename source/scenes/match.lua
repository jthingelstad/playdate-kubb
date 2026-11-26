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
--   settle   (PASS + PLAY: after a card that passes the Playdate to the
--            defender, A to start) the defender raises the kubbs thrown in and places punishment
--            kubbs by hand (scenes/settle), between the attacker's kubb
--            tosses and its batons; scripted matches (seed, instant,
--            autoSettle) leave it to the engine. The System Menu's "Auto
--            raise" (main.lua, scene.setAutoRaise; B REST OF GAME in the raise
--            view before 1.1.0) hands every raise to the game, both teams',
--            until it is turned off (s.autoRaise, kept in the save: "Auto
--            raise" in docs/notes/match.md); no pass card then while there
--            are only raises to make. Against the Playdate its own raises are
--            shown too (1.1.0: scenes/settle's watch, from the player's end)
--   togo     (1.1.0) the throw to go, before turn 1 (core/togo; match option THROW
--            TO GO, on by default; never in a Kid match): each team's first player
--            throws one baton from its own baseline at the king, A's then B's
--            (against the Playdate the player's, then the Playdate's, seen from
--            the player's end), each on a world of its own (throw.prepare from
--            match.togoSetup); a card before each person's baton (PASS + PLAY: it
--            passes the Playdate), the verdict card after both (togo.decide:
--            "<TEAM> THROWS FIRST: 0.42 M AGAINST 0.88 M", "TIE: THROW AGAIN",
--            "BOTH KINGS DOWN: THROW AGAIN"), then match.setFirst and turn 1. A
--            save made then is the match as it starts, marked `togo` beside
--            core/save's fields: a resume throws to go again from round 1.
--   over     the winner card: who won and how, turns, minutes, the winner's
--            baton hit rate, whether the game file was written to games/ in
--            the Data folder (DESIGN 7). A: a new match (rematch), B: the
--            title.
--
-- The cards are full screen and drawn once into an image (render/cards);
-- while one shows, the pitch is not drawn.
--
-- System Menu "Match": sheet (the score sheet so far, scenes/sheet, over the
-- match once no throw is in the air; B goes back to the match as it was),
-- resign (the team on turn gives up: G on its own turn;
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
-- Since 1.1.0 the view stays on the player's side all match: the Playdate's
-- throws are seen from the player's end, coming toward the player (throw's
-- s.turned, core/camera.fromEnd), and so are its raises. While it throws or
-- raises, B steps its SPEED (1X, 2X, 4X: s.watch.speed, kept across turns and
-- matches in the datastore file "watch") and A SKIPS the rest of its turn
-- (s.watch.skipping: its throws are run to rest at once, with the same seeds, so
-- the match is the one it would have been; a card says SKIPPING while they run).
-- Skipping ends when a person's throw is set up.
--
-- Self-test options (scenes/match.new opts): seed (throws come from
-- core/autothrow, not the crank), instant (each throw is shown at rest at
-- once), skipHandoff, maxTurns (the attacker resigns past it), byHand (settle
-- as a played match does, though the throws are scripted), instantPlayer (only
-- the player's throws at once: the Playdate's are watched).
import "CoreLibs/graphics"
import "core/tw"
import "core/match"
import "core/autothrow"
import "core/togo"
import "scenes/throw"
import "render/hud"
import "core/cards"
import "render/cards"
import "scenes/settle"
import "core/names"
import "core/save"
import "scenes/sheet"
import "core/wind"
import "core/history"
import "players"
import "device/enginetune"

local gfx <const> = playdate.graphics
local cmatch, autothrow, togo = tw.match, tw.autothrow, tw.togo
local throw, hud = tw.scenes.throw, tw.render.hud
local cards, rcards = tw.cards, tw.render.cards
local settle, sheet = tw.scenes.settle, tw.scenes.sheet
local wind = tw.wind

tw.scenes = tw.scenes or {}
local scene = {}

scene.version = playdate.metadata and playdate.metadata.version or "0.0.1"

scene.tune = {
	cpuThink = 0.9,      -- s the Playdate's aim shows before it throws
	skipSpeed = 1000,    -- the speed a skipped swing and rest hold run at (one frame)
	cpuScatter = 1.0,    -- times core/autothrow's scatter (lower: a steadier opponent)
}

-- the teams: opts.teams (scenes/teams: core/lineup's, players with their
-- roster keys and levels), else opts.names = { A = name, B = name } (one
-- player a team, named as it), else "You" against "Playdate", or "Team A"
-- and "Team B"
local function teams(opts)
	if opts.teams then return opts.teams end
	local n = opts.names or {}
	if opts.vs then return tw.names.teams { A = n.A or "You", B = "Playdate" } end
	if n.A and n.B then return tw.names.teams(n) end
	return nil
end

-- The computer's level (match option COMPUTER, opts.computer) on each of its
-- players, so its throws (throw.levelFor), the game file's [Throw Levels]
-- and a resume all carry it. A copy: the teams given are left as they were.
-- With no level given (a scripted match), and in a match saved before core
-- 0.9, the computer throws at the System Menu's level, as it did.
local function cpuLevel(tm, side, level)
	if not (tm and side and level and tm[side]) then return tm end
	local out = {}
	for k, t in pairs(tm) do out[k] = t end
	local ps = {}
	for i, p in ipairs(tm[side].players) do
		local q = {}
		for k, v in pairs(p) do q[k] = v end
		q.level = level
		ps[i] = q
	end
	local t = {}
	for k, v in pairs(tm[side]) do t[k] = v end
	t.players = ps
	out[side] = t
	return out
end

-- The sides the computer plays, for core/match's raising by side (engine 0.12,
-- match.raisePolicy): the Playdate's side against the Playdate, none in PASS +
-- PLAY. Said outright both ways: without it PASS + PLAY raises a person's kubbs
-- `apart`, not by the engine's advice (cpu.advice). Not saved: a resume sets it
-- again.
local function cpuSides(side)
	if side then return { side } end
	return {}
end

-- The raising core/match uses for a person's sides when the engine raises them in
-- one call (match.setup: RAISING: AUTOMATIC, scripted matches), named outright
-- (core/match `raising`, not saved: set again on a resume): device/enginetune's
-- autoRaising, not the advice, which would stall that frame on the device. nil
-- when the scene raises a person's kubbs itself (scenes/settle, by hand or REST OF
-- GAME), where the advice stays.
local function personRaising(s)
	if s.byHand then return nil end
	local r = {}
	for _, side in ipairs { "A", "B" } do
		if side ~= s.cpu then r[side] = tw.enginetune.autoRaising end
	end
	return r
end

-- SPEED for the Playdate's turn (1.1.0), kept across matches in the datastore
-- file "watch" ({ speed = 1 | 2 | 4 }). Self-test runs neither read nor write it.
scene.watchKey = "watch"
local function loadSpeed()
	if tw.selftestRun then return 1 end
	local ok, d = pcall(playdate.datastore.read, scene.watchKey)
	local v = ok and type(d) == "table" and tonumber(d.speed) or 1
	if v == 2 or v == 4 then return v end
	return 1
end
local function saveSpeed(speed)
	if tw.selftestRun then return end
	pcall(playdate.datastore.write, { speed = speed }, scene.watchKey)
end

-- The player's side against the Playdate (the view's), or nil in PASS + PLAY.
local function personSide(s)
	if not s.cpu then return nil end
	return (s.cpu == "A") and "B" or "A"
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

-- The match in progress, saved for a resume (core/save, playdate.datastore)
-- before every throw and after every raise and punishment kubb placed; a
-- finished match deletes it. Self-test runs (tw.selftestRun) use their own
-- key, so they never touch a player's saved match; scripted matches (seed,
-- instant, noSave) do not save at all.
function scene.saveKey()
	return tw.selftestRun and "selftest-match" or "match"
end

-- opts.saveKey (the device soak) saves a scripted match too, under that key.
local function saveKeyOf(s)
	local key = s.opts.saveKey
	if not key and (s.opts.seed or s.opts.instant) or s.opts.noSave then return nil end
	return key or scene.saveKey()
end

-- Raising for the rest of the game (scenes/settle's REST OF GAME) is kept in
-- the save itself since core 0.9 (core/save's autoRaise), written at once when
-- it is turned on or off. Builds before it kept it beside the match, in the
-- datastore file "<save key>-raise": { start = the match's start, raise =
-- "auto" }. A match resumed from such a build reads that file once (only when
-- it names the match's start, so a file left from another match is ignored);
-- the next save carries the choice and the file is deleted after it, so the
-- choice is never in neither place.
function scene.raiseKey(key) return key .. "-raise" end
local function startText(m)
	-- (numbers read back from the datastore's JSON may be floats: 2026.0)
	local t = m.start
	if type(t) ~= "table" then return "?" end
	local function n(v)
		v = tonumber(v)
		return v and string.format("%d", math.floor(v)) or "?"
	end
	return n(t.year) .. "-" .. n(t.month) .. "-" .. n(t.day) .. " " .. n(t.hour) .. ":" .. n(t.min)
end
-- the old side file: true when it is there and names this match
local function oldRaiseFile(s)
	local key = saveKeyOf(s)
	local d = key and playdate.datastore.read(scene.raiseKey(key))
	if d == nil then return false, false end
	return type(d) == "table" and d.raise == "auto" and d.start == startText(s.m), true
end

local function persist(s)
	local key = saveKeyOf(s)
	if not key then return end
	if cmatch.over(s.m) then
		playdate.datastore.delete(key)
		if s.oldRaise then playdate.datastore.delete(scene.raiseKey(key)) end
	else
		tw.save.write(s.m, { vs = s.opts.vs, names = s.opts.names, teams = s.opts.teams, autoSettle = s.opts.autoSettle,
			set = s.opts.set, wind = s.opts.wind, autoRaise = s.autoRaise.on or nil },
			function(d)
				-- (1.1.0, the Playdate's own fields beside core/save's, which unpack
				-- leaves be) togo: saved during the throw to go, so a resume throws it
				-- again; togoOff: THROW TO GO was OFF, for a rematch
				d.togo = s.tg and true or nil
				d.togoOff = (s.opts.togo == false) or nil
				playdate.datastore.write(d, key)
			end)
		-- the old build's side file, once the save carries what it said
		if s.oldRaise then
			s.oldRaise = false
			playdate.datastore.delete(scene.raiseKey(key))
		end
	end
end
scene.persist = persist

-- The system is about to quit the game or put the device to sleep (main.lua's
-- playdate.gameWillTerminate, deviceWillSleep): write the save once more. A
-- finished match is left alone, so its save is never deleted before archive
-- has written its game file.
function scene.saveNow(s)
	if s and s.m and not cmatch.over(s.m) then persist(s) end
end

-- The game file of a finished match, written once, before its resume save
-- is deleted: the match is never in neither place.
local function archive(s)
	if s.archived then return end
	s.archived = true
	s.finish = now()
	-- opts.noFile (the device soak): no game file, games/ is left alone
	if not s.opts.noFile then s.file, s.fileError = writeFile(s, s.finish) end
end

-- A finished match goes into its saved players' histories (core/history:
-- totals, recent games, at the level each played). Not for scripted
-- matches; guests and the Playdate are not saved. A failure here must not
-- stop the winner card.
local function foldHistory(s)
	if s.opts.seed or s.opts.instant or s.folded then return end
	s.folded = true
	local m = s.m
	local keys, levels, any = {}, {}, false
	for _, side in ipairs { "A", "B" } do
		for _, e in ipairs(m.lineup and m.lineup[side] or {}) do
			if e.key then keys[e.id], levels[e.id], any = e.key, e.level, true end
		end
	end
	if not any then return end
	pcall(function()
		local r = tw.players.load()
		local hs = {}
		for _, key in pairs(keys) do hs[key] = tw.players.history(key) end
		local done = tw.history.foldGame(r, hs, m.game, { keys = keys, levels = levels, date = tw.players.now(),
			file = s.file and s.file:match("[^/]+$") })
		tw.players.save(r)
		for _, key in ipairs(done) do tw.players.saveHistory(key, hs[key]) end
	end)
end

local function over(s)
	-- (a resign from the System Menu may end the match under the change list)
	s.changing = nil
	archive(s)
	foldHistory(s)
	persist(s)
	s.phase = "over"
	s.setup = nil
	s.ts.readout = nil
	local finish = s.finish
	s.win = cards.winner(s.m, finish)
	s.winHow = cmatch.howText(s.m)
	s.card = nil
end

-- The rail's first text: the team, and for a team of several who throws; when the
-- two do not fit before the pips (generated names run to 16 letters), who throws.
local function railName(s, setup)
	local name = string.upper(cmatch.teamName(setup.side, s.m.game))
	local room = hud.railRoom(setup.projectile, setup.of)
	local f = hud.labelFont()
	if setup.thrower then
		local who = string.upper(setup.thrower.name)
		if #s.m.game.teams[setup.side].players > 1 then
			local both = name .. ": " .. who
			name = (f:getTextWidth(both) <= room) and both or who
		elseif f:getTextWidth(name) > room then
			-- a team of one with a long team name: its player
			name = who
		end
	end
	return name
end

-- Whether the Playdate is passed inside this team (pass card, change):
-- a team of several players on the Playdate's own screen, not the
-- Playdate's team, and not a scripted match without cards.
local function passes(s, setup)
	return not s.opts.skipHandoff and setup.side ~= s.cpu and #s.m.game.teams[setup.side].players > 1
end

-- The card that passes the Playdate to the defender, once per settle, when
-- the defender has something to do by hand (PASS + PLAY only).
local function settleCard(s)
	if s.cpu or s.settleCarded or not s.settle or s.settle.done then return end
	if s.autoRaise.on and s.settle.mode == "raise" then return end
	s.settleCard, s.settleCarded, s.settleImg = cards.settle(s.m.game), true, nil
end

-- The hand-off card (core/cards), saying KID RULES in a Kid match (engine 0.15).
local function handoffCard(m, setup)
	local c = cards.handoff(m, setup)
	c.kid = m.game.rules == "kid" or nil
	return c
end

-- Set the next throw up (or end the match).
local function nextThrow(s)
	local m = s.m
	if s.opts.maxTurns and m.game.turn > s.opts.maxTurns and not cmatch.over(m) then cmatch.resign(m) end
	-- (not again when the throw just ruled on was saved at rest: nothing has
	-- changed since)
	if not cmatch.over(m) and not s.savedAtRest then persist(s) end
	s.savedAtRest = false
	-- the defender raises kubbs and places punishment kubbs by hand first
	-- (scenes/settle); scripted matches leave it to the engine (match.setup)
	if s.byHand and not cmatch.over(m) then
		local n = m.game:need()
		if n.kind == "raise" and n.side == s.cpu and not s.watch.skipping then
			-- the Playdate's own raises, shown from the player's end at SPEED
			-- (scenes/settle's watch: the calls core/match.settle would make)
			s.phase = "settle"
			s.settle = settle.new(m.game, function(side) return string.upper(cmatch.teamName(side, m.game)) end, s.input,
				s.autoRaise, function(side) return cmatch.raisePolicy(m, side) end,
				{ watch = s.watch, view = personSide(s) })
			s.settleCard, s.settleCarded, s.settleImg = nil, true, nil
			return
		end
		if (n.kind == "raise" or n.kind == "punish") and n.side ~= s.cpu then
			s.phase = "settle"
			s.settle = settle.new(m.game, function(side) return string.upper(cmatch.teamName(side, m.game)) end, s.input,
				s.autoRaise, function(side) return cmatch.raisePolicy(m, side) end)
			-- PASS + PLAY: the attacker hands the Playdate to the defender
			-- first (a card, A to start); against the Playdate the player
			-- holds it already. Raises the game makes need no one to hold it:
			-- the card waits for a punishment kubb, or for BY HAND
			s.settleCard, s.settleCarded, s.settleImg = nil, false, nil
			settleCard(s)
			return
		end
	end
	local setup = (not cmatch.over(m)) and cmatch.setup(m) or nil
	if not setup then return over(s) end
	s.setup = setup
	s.resolved = false
	-- the turn, so a kubb's spin is kept for the side's next kubb in it (throw.prepare)
	setup.turn = m.game.turn
	-- against the Playdate: its throws seen from the player's end (throw.endCamera),
	-- with SPEED and SKIP on screen; a person's throw ends a skip
	local cpuThrow = s.cpu ~= nil and setup.side == s.cpu
	if not cpuThrow and s.watch.skipping then s.watch.skipping = false end
	s.ts.turned = cpuThrow
	s.ts.watchBar = cpuThrow
	s.ts.speed = s.watch.skipping and scene.tune.skipSpeed or s.watch.speed
	throw.prepare(s.ts, setup)
	-- the thrower's own throw level (docs/PLAYERS.md section 6); nil (a
	-- match without saved players) is the System Menu's
	s.ts.level = setup.thrower and setup.thrower.level or nil
	-- and a person's throw level (engine 1.3: the meter's bars; nil standard)
	s.ts.throwLevel = setup.thrower and setup.thrower.throw or nil
	s.ts.instant = s.opts.instant or (cpuThrow and s.watch.skipping) or (not cpuThrow and s.opts.instantPlayer) or nil
	-- the wind (match option WIND): a direction and speed for each turn, a
	-- gust of it for each throw, in this side's view frame
	if s.windLevel then
		local turn = m.game.turn
		if s.windTurn ~= turn then
			s.windTurn = turn
			s.windDir, s.windSpeed = wind.turn(s.windRng, s.windLevel)
		end
		local d, sp = wind.gust(s.windRng, s.windDir, s.windSpeed)
		local wx, wy = wind.vector(d, sp, setup.side)
		throw.setWind(s.ts, wx, wy, wind.text(sp))
	end
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
	s.rail = { r1, r2 }
	throw.setRail(s.ts, railName(s, setup), setup.projectile, setup.n, setup.of, r1, r2)
	if setup.side ~= s.side then
		-- a new turn: the other team takes the Playdate
		s.side = setup.side
		s.result = nil
		-- (no card before the Playdate's own turn)
		s.phase = (s.opts.skipHandoff or setup.side == s.cpu) and "play" or "handoff"
		if s.phase == "handoff" then
			s.handoff = handoffCard(m, setup)
			s.card = nil
		end
	else
		s.phase = "play"
	end
	-- a team of several: the pass card when another of its players throws
	-- next (the hand-off card names the turn's first thrower)
	local th = setup.thrower
	if s.phase == "play" and passes(s, setup) and th and th.id ~= s.lastThrower then
		s.phase = "pass"
		s.pass = cards.pass(m, setup)
		s.card = nil
	end
	s.lastThrower = th and th.id
	s.cpuWait, s.cpuAim = 0, nil
	s.ts.watching = s.cpu ~= nil and setup.side == s.cpu
end

local watchInput   -- (below, with the System Menu's)

-- ---------- the throw to go (1.1.0) ----------

-- Whether this match starts with one: THROW TO GO on (the options give true or
-- false; scripted matches give nothing, and have none unless asked), never in a Kid
-- match, and only when a person throws one of the batons (each team's first
-- player, match.togoThrower). A resumed match only when it was saved during one.
local function togoWanted(s)
	if s.opts.resume then
		if not s.opts.togoPending then return false end
	elseif s.opts.togo ~= true then
		return false
	end
	local m = s.m
	if m.game.rules == "kid" then return false end
	if m.game.turn ~= 1 or (m.tossed or 0) > 0 then return false end
	for _, side in ipairs { "A", "B" } do
		if side ~= s.cpu and not cmatch.togoThrower(m, side).cpu then return true end
	end
	return false
end

local function togoCpu(s, side)
	return side == s.cpu or cmatch.togoThrower(s.m, side).cpu == true
end

-- The words for the verdict card and the result line.
scene.togoWords = {
	first = "%s THROWS FIRST",
	firstYou = "YOU THROW FIRST",   -- (VS PLAYDATE's player is "You")
	closer = "%.2f M AGAINST %.2f M",
	king = "%s FELLED THE KING",
	tie = "TIE: THROW AGAIN",
	bothKing = "BOTH KINGS DOWN: THROW AGAIN",
}

-- The next baton to go, or the verdict once both are in.
local togoNext
local function togoVerdict(s)
	local tg, m = s.tg, s.m
	local v = togo.decide(tg.e)
	tg.v, tg.mode, s.card = v, "verdict", nil
	local W = scene.togoWords
	if v.how == "again" then
		tg.card = { head = (v.why == "both king") and W.bothKing or W.tie, again = true }
		s.result = tg.card.head
		return
	end
	local first = string.upper(cmatch.teamName(v.first, m.game))
	local other = (v.first == "A") and "B" or "A"
	local line
	if v.how == "king" then
		line = string.format(W.king, string.upper(cmatch.teamName(other, m.game)))
	else
		line = string.format(W.closer, togo.mm(tg.e[v.first].gap) / 1000, togo.mm(tg.e[other].gap) / 1000)
	end
	tg.card = { head = (first == "YOU") and W.firstYou or string.format(W.first, first), line = line }
	s.result = tg.card.head .. ": " .. line
	tg.how = togo.text(tg.e, v, tg.round)
end

scene.togoVerdict = function(s) return togoVerdict(s) end   -- (self-tests: a forced tie)

togoNext = function(s)
	local tg, m = s.tg, s.m
	tg.i = tg.i + 1
	local side = tg.order[tg.i]
	if not side then return togoVerdict(s) end
	local setup = cmatch.togoSetup(m, side)
	tg.setup, tg.side, tg.measured = setup, side, false
	local cpu = togoCpu(s, side)
	tg.cpu = cpu
	if not cpu and s.watch.skipping then s.watch.skipping = false end
	local ts = s.ts
	ts.turned = cpu and s.cpu ~= nil
	ts.watchBar = cpu and s.cpu ~= nil
	ts.speed = s.watch.skipping and scene.tune.skipSpeed or s.watch.speed
	throw.prepare(ts, setup)
	ts.level = setup.thrower.level
	ts.throwLevel = setup.thrower.throw
	ts.instant = s.opts.instant or (cpu and s.watch.skipping) or (not cpu and s.opts.instantPlayer) or nil
	-- no wind: the two batons are judged against each other
	throw.setWind(ts, 0, 0, nil)
	if not cpu then throw.setTogo(ts) end
	throw.setRail(ts, string.upper(setup.thrower.name or cmatch.teamName(side, m.game)), "baton", 1, 1, "TO GO", nil)
	ts.watching = cpu
	s.cpuWait, s.cpuAim = 0, nil
	s.setup = nil
	-- a card before each person's baton (PASS + PLAY: the Playdate changes hands)
	if cpu or s.opts.skipHandoff then
		tg.mode = "throw"
	else
		tg.mode = "card"
		tg.card = { round = tg.round, pass = s.cpu == nil and (tg.i > 1 or tg.round > 1),
			name = setup.thrower.name or cmatch.teamName(side, m.game) }
	end
	s.card = nil
end

local function togoBegin(s, round)
	local order = { "A", "B" }
	-- against the Playdate the player throws first
	if s.cpu == "A" then order = { "B", "A" } end
	s.tg = { round = round or 1, e = {}, i = 0, order = order }
	s.phase = "togo"
	s.side, s.result = nil, nil
	togoNext(s)
end

local function togoUpdate(s)
	local tg, ts, p = s.tg, s.ts, s.input
	if tg.mode == "card" then
		p:advance()
		if p:pressed("a") then tg.mode, s.card = "throw", nil end
		return false
	end
	if tg.mode == "verdict" then
		p:advance()
		if not (p:pressed("a") or s.opts.skipHandoff) then return false end
		s.card = nil
		if tg.v.how == "again" then
			togoBegin(s, tg.round + 1)
			return false
		end
		cmatch.setFirst(s.m, tg.v.first, tg.how)
		s.tg = nil
		s.watch.skipping = false
		s.lastThrower = nil
		return true
	end
	local setup = tg.setup
	if ts.mode == "aim" and tg.cpu then
		ts.input:advance()
		watchInput(s)
		if not s.cpuAim then
			local level = setup.thrower.level or s.opts.computer
			s.cpuAim = togo.cpuThrow(setup, s.cpuRng or autothrow.rng(1), level, scene.tune.cpuScatter)
			ts.watching = true
			throw.showAim(ts, s.cpuAim)
		end
		s.cpuWait = s.cpuWait + ts.input:dt() * s.watch.speed
		if s.watch.skipping or s.cpuWait >= (s.opts.cpuThink or scene.tune.cpuThink) then
			s.cpuWait = 0
			local a = s.cpuAim
			s.cpuAim = nil
			throw.autoLaunch(ts, a)
		end
	elseif ts.mode == "aim" and s.rng then
		-- scripted matches (self-tests): the person's baton from the seed
		ts.input:advance()
		throw.autoLaunch(ts, togo.cpuThrow(setup, s.rng, "club"))
	else
		throw.update(ts)
		if tg.cpu and ts.watching and s.cpu then watchInput(s) end
	end
	if (ts.mode == "rest" or ts.mode == "done") and not tg.measured then
		tg.measured = true
		local gap, toppled = togo.gap(ts.result, setup.batonId)
		tg.e[tg.side] = { gap = gap, toppled = toppled }
		throw.setFlag(ts, toppled and "KING DOWN" or string.format("%.2f M", togo.mm(gap) / 1000))
	end
	if ts.mode == "done" then togoNext(s) end
	return false
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
		sheetWanted = false,     -- System Menu "Match: sheet", waiting for nothing in the air
		sheet = nil,             -- the score sheet on screen (scenes/sheet)
		exit = nil,              -- "title" or "match" (a rematch) when the scene is done
		throws = 0,
		cpuThrows = 0,           -- the Playdate's throws (VS PLAYDATE)
	}
	-- raising and punishment kubbs by hand, except in scripted matches
	-- (opts.byHand: a scripted match that settles as a played one does, self-tests)
	s.byHand = s.opts.byHand or not (s.opts.seed or s.opts.instant or s.opts.autoSettle)
	-- REST OF GAME (scenes/settle): every raise by the game from then on
	s.autoRaise = { on = false, changed = false }
	-- SPEED and SKIP for the Playdate's turn (1.1.0; scenes/settle reads it too)
	s.watch = { speed = loadSpeed(), skipping = false, changed = false }
	s.cpu = s.opts.vs        -- the Playdate's side, or nil
	if s.cpu then s.cpuRng = autothrow.rng(s.opts.cpuSeed or playdate.getSecondsSinceEpoch()) end
	if s.opts.resume then
		-- a saved match (core/save.unpack): on from where it was left
		s.m = s.opts.resume
		-- the computer's sides are not saved (core/match m.cpu): set them again
		s.m.cpu = cpuSides(s.cpu)
		s.m.raising = personRaising(s)
	else
		-- the surface and opening from the match options (scenes/options)
		-- opts.rules: "kid" for a Kid match (the KID computer, scenes/options; engine 0.15),
		-- else nil, the standard rules. The game keeps it (g.rules), so a resume does too
		s.m = cmatch.new { start = now(), surface = s.opts.surface or "Grass", opening = s.opts.opening,
			teams = cpuLevel(teams(s.opts), s.cpu, s.opts.computer), mode = s.cpu and "Vs Playdate" or nil,
			cpu = cpuSides(s.cpu), raising = personRaising(s), rules = s.opts.rules }
	end
	if s.opts.seed then s.rng = autothrow.rng(s.opts.seed) end
	-- a resumed match raising for itself goes on doing so: the save's autoRaise
	-- (opts.autoRaise, from core/save.unpack), or an older build's side file
	if s.opts.resume then
		local named, there = oldRaiseFile(s)
		s.oldRaise = there
		if s.byHand and (s.opts.autoRaise or named) then s.autoRaise.on = true end
	end
	s.ts.sceneName = "match"
	-- the wind (match option WIND; off or absent: still air)
	if s.opts.wind and s.opts.wind ~= "off" and (wind.levels[s.opts.wind] or 0) > 0 then
		s.windLevel = s.opts.wind
		s.windRng = autothrow.rng(s.opts.windSeed or s.opts.seed or playdate.getSecondsSinceEpoch())
	end
	if togoWanted(s) then
		togoBegin(s)
		persist(s)
	else
		nextThrow(s)
	end
	return s
end

-- System Menu "Auto raise" (1.1.0; B REST OF GAME in the raise view before):
-- every raise by the game from now on, both teams', or by hand again. Kept with
-- the match at once; a raise on screen starts again from the game's kubb.
function scene.setAutoRaise(s, on)
	if not (s and s.byHand) or s.autoRaise.on == on then return end
	s.autoRaise.on, s.autoRaise.changed = on, true
	if s.phase ~= "settle" then
		s.autoRaise.changed = false
		persist(s)
	end
end

-- The Playdate's turn: B steps SPEED, A skips (the throw on screen and the rest
-- of the turn are run at once). Read after the frame's input has advanced.
watchInput = function(s)
	local p, w, ts = s.input, s.watch, s.ts
	if w.skipping then return end
	if p:pressed("b") then
		w.speed = tw.render.watchbar.nextSpeed(w.speed)
		ts.speed = w.speed
		saveSpeed(w.speed)
	end
	if p:pressed("a") then
		w.skipping = true
		ts.speed, ts.instant = scene.tune.skipSpeed, true
		if playdate.display then playdate.display.setRefreshRate(throw.tune.refreshRate) end
	end
end

-- System Menu "Match: sheet" (Jamie, 2026-11-14: "an option to see the
-- scoresheet for a game in progress"): the game file so far, shown once
-- nothing is in the air. The match waits under it (a throw, the Playdate's
-- think, a card) and carries on where it was after B.
function scene.showSheet(s)
	if s.m then s.sheetWanted = true end
end

local function openSheet(s)
	local m = s.m
	local g = m.game
	local text = cmatch.file(m, nil, scene.version)
	local right = { "TURN " .. g.turn, string.upper(g.surface or "") }
	if g.winner then right[1] = string.upper(cmatch.teamName(g.winner, g)) .. " WON" end
	s.sheet = sheet.new(s.input, sheet.split(text),
		string.upper(cmatch.teamName("A", g) .. " V " .. cmatch.teamName("B", g)), right, true)
end

-- The team holding the Playdate in PASS + PLAY: the thrower's, but in the
-- settle phase the defender's only once its pass card has been shown (the
-- Playdate goes to the defender with it). While REST OF GAME raises with no
-- card (scenes/settle), and in a match resumed into such a raise, the
-- Playdate has not changed hands: the attacker's.
function scene.holder(s)
	if s.phase == "settle" then
		if s.settleCarded then return s.settle.side end
		return s.m.game.attacker
	end
	if s.phase == "togo" then return s.tg and s.tg.side end
	return s.setup and s.setup.side
end

-- System Menu "Match: resign": the team holding the Playdate resigns once
-- nothing is in the air. If that throw was its last and the turn has passed
-- by then, the request is dropped: a team resigns only on its own turn.
function scene.resign(s)
	-- (a match resumed mid-settle has no throw set up yet: its defender may
	-- still resign)
	if s.phase ~= "over" and (s.setup or s.phase == "settle" or s.phase == "togo") then
		s.resignWanted = true
		if s.cpu then
			-- against the Playdate it is always the player who resigns, on
			-- the player's own turn
			s.resignSide, s.resignWait = (s.cpu == "A") and "B" or "A", true
		else
			-- the team holding the Playdate (scene.holder): while the defender
			-- raises by hand it is the defender's, and waits for its own turn
			-- (the rules allow no other); while the game raises with no pass
			-- card the attacker still holds it, and it is the attacker's
			s.resignSide = scene.holder(s)
			s.resignWait = s.phase == "settle" or s.phase == "togo"
		end
	end
end

function scene.update(s)
	local ts = s.ts
	if s.sheet then
		sheet.update(s.sheet)
		if s.sheet.done then s.sheet = nil end
		return
	end
	if s.sheetWanted and (s.phase ~= "play" or ts.mode == "aim" or ts.mode == "done") then
		s.sheetWanted = false
		openSheet(s)
		return
	end
	if s.resignWanted and s.phase ~= "togo"
		and (s.phase == "handoff" or s.phase == "pass" or ts.mode == "aim" or ts.mode == "done") then
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
	if s.phase == "togo" then
		-- the throw to go: decided, the match starts with the side it gave
		if togoUpdate(s) then
			persist(s)
			nextThrow(s)
		end
		return
	end
	if s.phase == "handoff" or s.phase == "pass" then
		s.input:advance()
		local p = s.input
		if s.changing then
			-- who throws instead (core/match.candidates)
			local c = s.changing
			if p:pressed("up") then c.i = (c.i - 2) % #c.list + 1; s.card = nil end
			if p:pressed("down") then c.i = c.i % #c.list + 1; s.card = nil end
			if p:pressed("a") and c.list[c.i].ok then
				cmatch.changeThrower(s.m, c.list[c.i].id)
				local setup = s.setup
				s.lastThrower = setup.thrower.id
				s.ts.level = setup.thrower.level
				s.ts.throwLevel = setup.thrower.throw
				throw.setRail(s.ts, railName(s, setup), setup.projectile, setup.n, setup.of, s.rail[1], s.rail[2])
				if s.phase == "handoff" then s.handoff = handoffCard(s.m, setup)
				else s.pass = cards.pass(s.m, setup) end
				persist(s)
				s.changing, s.card = nil, nil
			elseif p:pressed("b") then
				s.changing, s.card = nil, nil
			end
			return
		end
		if p:pressed("a") then
			s.phase, s.card = "play", nil
		elseif p:pressed("b") and s.setup and passes(s, s.setup) then
			local list = cmatch.candidates(s.m)
			local i = 1
			for k, e in ipairs(list) do if e.current then i = k end end
			s.changing, s.card = { list = list, i = i }, nil
		end
		return
	end
	if s.phase == "settle" then
		if s.settleCard then
			s.input:advance()
			if s.input:pressed("a") then s.settleCard, s.settleImg = nil, nil end
			return
		end
		local before = s.settle.raised + s.settle.placed
		settle.update(s.settle)
		-- SPEED stepped while the Playdate raises: kept for next time
		if s.watch.changed then
			s.watch.changed = false
			saveSpeed(s.watch.speed)
		end
		-- REST OF GAME or BY HAND: kept with the match at once
		if s.autoRaise.changed then
			s.autoRaise.changed = false
			persist(s)
		end
		-- each raise and placement is saved as it is made
		if s.settle.raised + s.settle.placed ~= before and not s.settle.done then persist(s) end
		-- a punishment kubb or BY HAND: now the defender holds it
		settleCard(s)
		if s.settle.done then
			s.settle = nil
			nextThrow(s)
		end
		return
	end
	-- Auto raise turned on or off from the System Menu outside a settle: kept now
	if s.autoRaise.changed and s.phase ~= "settle" then
		s.autoRaise.changed = false
		persist(s)
	end
	if s.phase == "over" then
		s.input:advance()
		if s.input:pressed("a") then s.exit = "rematch" elseif s.input:pressed("b") then s.exit = "title" end
		return
	end
	if ts.mode == "aim" and s.cpu and s.setup.side == s.cpu then
		-- the Playdate's throw: its aim shows a moment, then it throws
		ts.input:advance()
		watchInput(s)
		if not s.cpuAim then
			-- choose now and show it: its stance and aim stay on screen while it thinks
			s.cpuAim = autothrow.choose(s.setup, s.cpuRng, scene.tune.cpuScatter, throw.levelFor(ts))
			ts.watching = true
			throw.showAim(ts, s.cpuAim)
		end
		s.cpuWait = s.cpuWait + ts.input:dt() * s.watch.speed
		if s.watch.skipping or s.cpuWait >= (s.opts.cpuThink or scene.tune.cpuThink) then
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
		if ts.watching and s.cpu and s.setup.side == s.cpu then watchInput(s) end
	end
	if (ts.mode == "rest" or ts.mode == "done") and not s.resolved then
		-- the throw is at rest: the engine rules on it now, so its result
		-- shows during the rest hold
		cmatch.resolve(s.m, ts.result, not ts.last.legal)
		-- saved now, not at the next setup: leaving for the title during the
		-- rest hold must not give the throw back on resume. A throw that ended
		-- the match writes its game file first, then the save is deleted.
		if cmatch.over(s.m) then archive(s) end
		persist(s)
		s.savedAtRest = true
		s.resolved = true
		s.result = s.m.text
		throw.setFlag(ts, hud.short(s.result))
		s.throws = s.throws + 1
	end
	if ts.mode == "done" then nextThrow(s) end
end

function scene.draw(s)
	if s.sheet then return sheet.draw(s.sheet) end
	s.ts.covered = not (s.phase == "play" or s.phase == "togo" and s.tg.mode == "throw")
	if s.phase == "togo" and s.tg.mode ~= "throw" then
		if not s.card then
			s.card = (s.tg.mode == "card") and rcards.togo(s.tg.card) or rcards.togoVerdict(s.tg.card)
		end
		s.card:draw(0, 0)
		return
	end
	if s.phase == "over" or s.phase == "handoff" or s.phase == "pass" then
		-- a full-screen card, built once
		if not s.card then
			if s.changing then
				local st = s.setup
				s.card = rcards.change(s.changing.list, s.changing.i,
					st.kind == "toss" and "the kubbs" or ("baton " .. st.n))
			elseif s.phase == "over" then
				s.card = rcards.winner(s.win, s.winHow, s.file ~= nil)
			elseif s.phase == "pass" then
				s.card = rcards.pass(s.pass)
			else
				s.card = rcards.handoff(s.handoff)
			end
		end
		s.card:draw(0, 0)
		return
	end
	s.card = nil
	if s.watch.skipping and (s.phase == "play" or s.phase == "togo" or s.phase == "settle" and s.settle.watch) then
		-- the Playdate's turn, skipped: a card while its throws run to rest
		s.skipImg = s.skipImg or rcards.skipping()
		s.skipImg:draw(0, 0)
		return
	end
	if s.phase == "settle" then
		if s.settleCard then
			-- the pass card, built once
			s.settleImg = s.settleImg or rcards.settle(s.settleCard)
			s.settleImg:draw(0, 0)
			return
		end
		settle.draw(s.settle)
		return
	end
	throw.draw(s.ts)
end

function scene.enter()
	throw.enter()
end

tw.scenes.match = scene
