-- A match: the rules engine (core/rules) driven by physics throws, as the
-- match scene plays it. Pure Lua: no playdate.*. Not a per-frame path.
--
-- The engine is the truth for the layout between throws; physics is the
-- truth during a throw. match.setup says what the next throw is and gives
-- the pitch as physics pieces in the thrower's view frame (core/frame: the
-- thrower always throws from y = 0 toward +y); match.resolve takes the
-- finished physics throw, turns it into the engine's outcome record
-- (core/outcome) and applies it. Raising and punishment placement are
-- automatic (the engine's policies) and happen in match.setup.
--
--   local m = match.new{ surface = "Grass", start = {year, month, day, hour, min} }
--   while not match.over(m) do
--     local s = match.setup(m)          -- s.kind "toss" | "baton"
--     ... build tw.world from s.pieces, launch s.projectile, run to rest ...
--     match.resolve(m, tw.world.result(w), illegal)   -- m.text says what happened
--   end
--   local text, name = match.file(m, finish, version)
--
-- Everything a resume needs (stage 5) is in the one table m: the engine
-- game (plain fields and a metatable), the start time, the surface and the
-- per-turn counters.
import "core/tw"
import "core/rules"
import "core/notation"
import "core/frame"
import "core/outcome"
import "core/debris"

local rules, notation, frame, outcome, debris = tw.rules, tw.notation, tw.frame, tw.outcome, tw.debris
local fmt = string.format

local match = {}

function match.teamName(side) return "Team " .. side end

function match.new(opts)
	opts = opts or {}
	local g = rules.new {
		teams = {
			A = { name = "Team A", players = { { name = "Player A", id = "a" } } },
			B = { name = "Team B", players = { { name = "Player B", id = "b" } } },
		},
		surface = opts.surface or "Grass", opening = opts.opening or "2-4-6", first = opts.first or "A",
	}
	return {
		game = g,
		start = opts.start,       -- {year, month, day, hour, min}
		mode = opts.mode or "Pass and Play",
		turn = g.turn,            -- the turn the counters below belong to
		tossed = 0,               -- kubbs thrown (and rethrown) this turn
		text = nil,               -- what the last throw (or the automatic steps) did
		settled = nil,            -- raised and punishment kubbs placed before this throw
		setup = nil,              -- the current throw (match.setup)
		debris = debris.new(),    -- batons and downed kubbs lying on the pitch this turn
	}
end

function match.over(m) return m.game.phase == "over" end

local function countTurn(m)
	if m.game.turn ~= m.turn then m.turn, m.tossed = m.game.turn, 0 end
end

-- Raise every lying kubb and place every punishment kubb (automatically,
-- with the engine's policies). Returns how many of each.
function match.settle(m)
	local g = m.game
	local raised, punished = 0, 0
	while true do
		local n = g:need()
		if n.kind == "raise" then
			g:raise(nil)
			raised = raised + 1
		elseif n.kind == "punish" then
			g:autoPunishment()
			punished = punished + 1
		else
			break
		end
	end
	return raised, punished
end

-- The next throw, in the thrower's view frame:
--   kind        "toss" | "baton"
--   side        the attacker ("A" | "B")
--   projectile  "kubb" | "baton"; kubb = the id of the kubb thrown
--   pieces      outcome.pieces: what is on the pitch (view frame)
--   lineY       the baseline (0)
--   forwardY    how far forward the thrower may stand: the advantage line
--               for batons at kubbs when there is one, else the baseline
--   advY        the advantage line to draw (view frame), or nil
--   targets     ids to frame: standing field kubbs, else base kubbs, else
--               the king (batons); nil for a toss
--   n, of       this throw's number and the throws of its kind this turn
--   label       "Team A  baton 2 of 6", "Team B  kubb 1 of 3"
--   debris      core/debris pieces: the batons thrown and the kubbs knocked
--               down earlier this turn, lying where they came to rest (view
--               frame; physics bodies, not engine pieces)
--   batonId     the body id of this baton ("baton1" .. "baton6"), so it can
--               lie on the pitch as debris after it
-- Returns nil when the game is over.
function match.setup(m)
	local g = m.game
	local raised, punished = match.settle(m)
	if raised > 0 or punished > 0 then m.settled = { raised = raised, punished = punished } else m.settled = nil end
	countTurn(m)
	local n = g:need()
	if n.kind == "over" then
		m.setup = nil
		return nil
	end
	local side = n.side
	debris.begin(m.debris, g.turn)
	-- out kubbs waiting on the pitch: the one about to be rethrown is picked
	-- up, and all of them once the kubb throwing is over
	debris.prune(m.debris, function(e)
		if not e.waiting then return true end
		local k = g.kubbs[e.id]
		return n.kind == "toss" and e.id ~= n.kubb and k ~= nil and (k.where == "out" or k.where == "punish")
	end)
	local s = { kind = n.kind, side = side, pieces = outcome.pieces(g, side), lineY = 0, forwardY = 0 }
	debris.applyExact(m.debris, s.pieces, side)
	s.debris = debris.pieces(m.debris, side)
	if g.advantageY then s.advY = frame.y(side, g.advantageY) end
	if n.kind == "toss" then
		s.projectile, s.kubb = "kubb", n.kubb
		s.rethrow = n.rethrow
		s.n, s.of = m.tossed + 1, m.tossed + n.left
		s.label = fmt("%s  %s %d of %d", match.teamName(side), n.rethrow and "rethrow" or "kubb", s.n, s.of)
	else
		s.projectile = "baton"
		s.kingShot = n.kingShot
		if n.advantageY and not n.kingShot then s.forwardY = frame.y(side, n.advantageY) end
		s.targets = n.targets
		s.n, s.of = n.n, n.of
		s.batonId = "baton" .. n.n
		s.label = fmt("%s  %s %d of %d", match.teamName(side), n.kingShot and "king shot, baton" or "baton", n.n, n.of)
	end
	m.setup = s
	return s
end

-- Every body a throw's physics world starts with: the engine's pieces, then
-- the debris (a new list; once per throw).
function match.worldPieces(s)
	local out = {}
	for i, p in ipairs(s.pieces) do out[i] = p end
	for _, p in ipairs(s.debris or {}) do out[#out + 1] = p end
	return out
end

-- ---------- what happened, in words ----------

local function plural(n, one, many) return n == 1 and one or (n .. " " .. many) end

local function hasNote(notes, from, pattern)
	for i = from, #notes do
		if notes[i]:find(pattern, 1, true) then return true end
	end
	return false
end

local function wins(g)
	return match.teamName(g.winner) .. " wins"
end

-- A short line for a baton token (and the notes the throw added).
local function batonText(g, token, notes, from)
	local parts = {}
	if token == "K" then return "king down: " .. wins(g) end
	if token:sub(-1) == "E" then return "king down early: " .. wins(g) end
	if token == "G" then return "resigned: " .. wins(g) end
	if token == "=" then
		parts[1] = "missed the king"
	elseif token == "Z" then
		if hasNote(notes, from, "II.B.11") then parts[1] = "own-half kubb hit: all put back"
		else parts[1] = "helicopter: illegal" end
	elseif token == "-" then
		parts[1] = "missed"
	else
		local function n(c) if not c then return 0 end return c == "" and 1 or tonumber(c) end
		local f, b = n(token:match("^(%d*)F")), n(token:match("(%d*)B$"))
		if f > 0 then parts[#parts + 1] = plural(f, "field kubb", "field kubbs") end
		if b > 0 then parts[#parts + 1] = plural(b, "base kubb", "base kubbs") end
		parts = { table.concat(parts, " and ") .. " down" }
	end
	if hasNote(notes, from, "II.B.4a") then parts[#parts + 1] = "base kubb early: raised" end
	if hasNote(notes, from, "II.B.7") then parts[#parts + 1] = "pushed out: put back" end
	return table.concat(parts, "; ")
end

-- Apply a finished physics throw. `res` is tw.world.result of a world
-- built from m.setup.pieces with the projectile launched (a kubb toss's
-- projectile body has the kubb's id); `illegal` is true for a helicopter
-- baton. Sets m.text and returns the outcome record given to the engine.
function match.resolve(m, res, illegal)
	local g, s = m.game, m.setup
	assert(s, "no throw set up")
	local turn = g.turn
	local sheetTurn = g.sheet.turns[turn]
	local nb, nn = #sheetTurn.batons, #sheetTurn.notes
	local o
	if s.kind == "toss" then
		local before = {}
		local ink = sheetTurn.inkast
		local function inkCount(code)
			local c = 0
			for _, k in pairs(ink) do c = c + (k[code] or 0) end
			return c
		end
		before.Q, before.N = inkCount("Q"), inkCount("N")
		o = outcome.toss(res, s.pieces, s.side, s.kubb)
		g:toss(o)
		m.tossed = m.tossed + 1
		local k = g.kubbs[s.kubb]
		local parts = {}
		if g.phase == "over" then
			parts[1] = "king down: " .. wins(g)
		else
			if k.where == "pitch" then parts[1] = "kubb in"
			elseif k.where == "punish" then parts[1] = "out twice: punishment kubb"
			else parts[1] = "kubb out: rethrown last" end
			if hasNote(sheetTurn.notes, nn + 1, "II.C.4b") then parts[1] = "own half hit: kubb out" end
			if inkCount("N") > before.N then parts[#parts + 1] = "on a kubb: lowered" end
			local q = inkCount("Q") - before.Q
			if q > 0 then parts[#parts + 1] = plural(q, "rescue", "rescues") end
		end
		m.text = table.concat(parts, "; ")
	else
		o = outcome.baton(res, s.pieces, s.side, illegal)
		g:throwBaton(o)
		local b = sheetTurn.batons[nb + 1]
		m.text = batonText(g, b and b.token or "-", sheetTurn.notes, nn + 1)
	end
	match.carryDebris(m, s, res, turn, sheetTurn.batons[nb + 1])
	countTurn(m)
	m.setup = nil
	return o
end

-- After the engine has ruled on a throw: what stays lying on the pitch for
-- the next throw of this turn. The thrown baton lies where it came to rest;
-- every kubb this throw toppled that the engine took off the pitch (into a
-- hand) lies where it fell; the debris already there moves if it was struck.
-- A throw the engine puts back (Z: a helicopter, II.B.11) leaves the earlier
-- debris where it was, as it does the standing pieces; only its baton is
-- added. The turn over (or the game): nothing is carried.
function match.carryDebris(m, s, res, turn, batonRec)
	local g, d = m.game, m.debris
	if g.phase == "over" or g.turn ~= turn then
		debris.clear(d)
		return
	end
	if s.kind == "toss" then
		-- the engine keeps the tossed kubbs (and any it struck): only their
		-- exact rest poses are carried
		debris.recordExact(d, g, res, s.side)
		-- a kubb that is out (to be rethrown, or a punishment kubb) lies where
		-- it stopped while the other kubbs are thrown (Jamie, 2026-11-13);
		-- match.setup lifts it when it is rethrown or the inkast is over
		debris.carry(d, res, s.side)
		for id, k in pairs(g.kubbs) do
			if k.where == "out" or k.where == "punish" then
				local e = debris.add(d, id, "kubb", res, s.side)
				if e then e.waiting = true end
			end
		end
		return
	end
	local putBack = batonRec and batonRec.token == "Z"
	if not putBack then
		debris.carry(d, res, s.side)
		for _, id in ipairs(res.toppled or {}) do
			local k = g.kubbs[id]
			if k and k.where ~= "pitch" then debris.add(d, id, "kubb", res, s.side) end
		end
	end
	if s.batonId then debris.add(d, s.batonId, "baton", res, s.side) end
	debris.recordExact(d, g, res, s.side)
end

-- Resign: the team on turn gives up (DESIGN 7: `G` on its own turn).
function match.resign(m)
	local g = m.game
	if g.phase == "over" then return false end
	local side = g.attacker
	g:resign(side)
	m.setup = nil
	debris.clear(m.debris)
	m.text = match.teamName(side) .. " resigned: " .. wins(g)
	return true
end

-- One line for the winner screen.
function match.howText(m)
	local g = m.game
	local loser = match.teamName(g.winner == "A" and "B" or "A")
	if g.how == "king" then return match.teamName(g.winner) .. " toppled the king"
	elseif g.how == "resigned" then return loser .. " resigned"
	elseif g.how == "king toppled by a thrown kubb" then return loser .. " toppled the king with a kubb"
	elseif g.how == "king toppled early" then return loser .. " toppled the king early" end
	return g.how or ""
end

-- The game file (DESIGN 7): text and file name. finish = {year, month, day,
-- hour, min}; the start is m.start (finish when it was not given).
function match.file(m, finish, version)
	local start = m.start or finish
	local g = m.game
	local text = notation.render(g, { start = start, finish = finish, version = version, mode = m.mode })
	return text, notation.filename(start, g.teams.A.name, g.teams.B.name)
end

-- Standing kubbs of a side's half (field and base), for the HUD.
function match.standing(m, side)
	local g = m.game
	return #g:fieldKubbs(side) + #g:baseKubbs(side)
end

tw.match = match
