-- The turn engine: U.S. National Kubb Championship Rules V4.0 as a pure state
-- machine (DESIGN.md section 6). Pure Lua: no playdate.*.
--
-- The engine knows nothing about physics. It says what is needed next
-- (game:need()) and consumes resolved throws (THROW OUTCOMES, documented in
-- AGENTS.md "Rules engine") and the defender's choices. Everything it does
-- is written to game.sheet (tw.notation) as it happens.
--
--   local g = tw.rules.new{ teams = { A = { name = "Jamie", players = { { name = "Jamie" } } },
--                                     B = { name = "Playdate", players = { { name = "Club" } } } },
--                           surface = "Grass", opening = "2-4-6", first = "A" }
--   local n = g:need()   -- { kind = "toss" | "raise" | "punish" | "baton" | "over", ... }
--   g:toss(outcome) / g:raise(choice) / g:placePunishment(pose) / g:throwBaton(outcome)
--   g:resign(side)
--
-- Kubbs have permanent ids "a1".."a5" (Team A's base kubbs, x = -2..2 on
-- y = 0) and "b1".."b5" (y = 8). The king is "king".
import "core/tw"
import "core/pitch"
import "core/raising"
import "core/notation"

local pitch, raising, notation = tw.pitch, tw.raising, tw.notation
local other = pitch.other
local sort = table.sort

local rules = {}

local Game = {}
Game.__index = Game
rules.Game = Game

local function fail(msg) error("rules: " .. msg, 3) end

local function copyPose(p) return raising.copyPose(p) end

-- Batons for a turn: 2-4-6 opening (II.A) or six from the start.
function rules.batonsFor(opening, turn)
	if opening ~= "six" then
		if turn == 1 then return 2 end
		if turn == 2 then return 4 end
	end
	return 6
end

function rules.new(opts)
	opts = opts or {}
	local g = setmetatable({}, Game)
	g.teams = {}
	for _, side in ipairs { "A", "B" } do
		local t = (opts.teams or {})[side] or {}
		local players = {}
		for i, p in ipairs(t.players or { { name = t.name or ("Team " .. side) } }) do
			if type(p) == "string" then p = { name = p } end
			players[i] = { name = p.name, id = p.id }
		end
		g.teams[side] = { name = t.name or ("Team " .. side), players = players }
	end
	notation.assignIds(g.teams)
	g.surface = opts.surface or "Grass"
	g.opening = opts.opening == "six" and "six" or "2-4-6"
	g.first = opts.first == "B" and "B" or "A"
	g.raisePolicy = opts.raisePolicy or "apart"
	g.kubbs, g.ids = {}, {}
	for _, side in ipairs { "A", "B" } do
		for i, x in ipairs(pitch.baseX) do
			local id = side:lower() .. i
			g.kubbs[id] = {
				id = id, kind = "base", half = side, where = "pitch",
				pose = { x = x, y = pitch.baseline[side], standing = true, angle = 0 },
				thrown = 0, established = false,
			}
			g.ids[#g.ids + 1] = id
		end
	end
	g.king = { id = "king", pose = { x = pitch.king.x, y = pitch.king.y, standing = true, angle = 0 } }
	g.hand = { A = {}, B = {} }
	g.sheet = notation.sheet()
	g.turn = 0
	g.winner, g.how = nil, nil
	g:_startTurn()
	return g
end

-- ---------- queries ----------

function Game:player(side, p)
	local ps = self.teams[side].players
	if p == nil then return ps[1].id end
	for _, q in ipairs(ps) do
		if q.id == p or q.name == p then return q.id end
	end
	fail("no player " .. tostring(p) .. " on Team " .. side)
end

-- Kubbs on the pitch, in id order, optionally filtered.
function Game:onPitch(filter)
	local out = {}
	for _, id in ipairs(self.ids) do
		local k = self.kubbs[id]
		if k.where == "pitch" and (not filter or filter(k)) then out[#out + 1] = k end
	end
	return out
end

-- Standing field kubbs in `side`'s half.
function Game:fieldKubbs(side)
	return self:onPitch(function(k) return k.kind == "field" and k.half == side end)
end

function Game:baseKubbs(side)
	return self:onPitch(function(k) return k.kind == "base" and k.half == side end)
end

-- Every kubb of `side`'s half is down: what a king shot needs.
function Game:allDown(side)
	return #self:fieldKubbs(side) == 0 and #self:baseKubbs(side) == 0
end

-- Context for raising/punishment geometry in `half`, without kubb `except`.
function Game:context(half, except)
	local others = {}
	for _, k in ipairs(self:onPitch()) do
		if k.id ~= except then others[#others + 1] = { id = k.id, pose = k.pose } end
	end
	return { half = half, king = self.king.pose, others = others }
end

-- Where kubbs are: counts by `where` (pitch, hand, out, punish). Ten always.
function Game:census()
	local c = { pitch = 0, hand = 0, out = 0, punish = 0, total = 0 }
	for _, id in ipairs(self.ids) do
		local w = self.kubbs[id].where
		c[w] = (c[w] or 0) + 1
		c.total = c.total + 1
	end
	return c
end

-- What the engine needs next.
function Game:need()
	local ph = self.phase
	if ph == "over" then
		return { kind = "over", winner = self.winner, how = self.how }
	elseif ph == "toss" or ph == "rethrow" then
		return { kind = "toss", side = self.attacker, kubb = self.current, rethrow = ph == "rethrow",
			throwY = pitch.baseline[self.attacker], half = self.defender,
			left = #self.firstQueue + #self.rethrowQueue }
	elseif ph == "raise" then
		local k = self.kubbs[self.current]
		local ctx = self:context(self.defender, k.id)
		return { kind = "raise", side = self.defender, kubb = k.id, pose = copyPose(k.pose),
			decision = raising.options(k.pose, ctx) }
	elseif ph == "punish" then
		return { kind = "punish", side = self.defender, kubb = self.current, half = self.defender }
	elseif ph == "batons" then
		local def = self.defender
		local kingShot = self:allDown(def)
		local targets = {}
		if kingShot then
			targets = { "king" }
		else
			local f = self:fieldKubbs(def)
			if #f == 0 then f = self:baseKubbs(def) end
			for _, k in ipairs(f) do targets[#targets + 1] = k.id end
		end
		local throwY = pitch.baseline[self.attacker]
		if self.advantageY and not kingShot then throwY = self.advantageY end
		return { kind = "baton", side = self.attacker, n = self.batonIndex + 1, of = self.batonsTotal,
			left = self.batonsLeft, kingShot = kingShot, throwY = throwY,
			advantageY = self.advantageY, targets = targets }
	end
end

-- ---------- turn flow ----------

function Game:_startTurn()
	self.turn = self.turn + 1
	local att = (self.turn % 2 == 1) and self.first or other(self.first)
	local def = other(att)
	self.attacker, self.defender = att, def
	self.batonsTotal = rules.batonsFor(self.opening, self.turn)
	self.batonsLeft, self.batonIndex = self.batonsTotal, 0
	-- Every field kubb standing now is established (left from an earlier turn).
	for _, k in ipairs(self:onPitch()) do
		k.thrown = 0
		if k.kind == "field" then k.established = true end
	end
	local q = self.hand[att]
	sort(q)
	for _, id in ipairs(q) do
		local k = self.kubbs[id]
		k.thrown, k.established, k.kind = 0, false, "field"
	end
	self.firstQueue, self.rethrowQueue, self.punishQueue = q, {}, {}
	self.hand[att] = {}
	self.firstThrows = 0
	self.lastTosser = nil
	self.sheet:beginTurn(self.turn, att)
	-- II.B.2: the opponent left field kubbs standing in the attacker's own
	-- half; the line runs through the center of the one closest to the
	-- centerline. The inkast cannot legally move them (II.C.4b puts them
	-- back), so it is fixed for the turn.
	self.advantageY = nil
	local own = self:fieldKubbs(att)
	if #own > 0 then
		local best
		for _, k in ipairs(own) do
			if not best or pitch.fromBaseline(att, k.pose.y) > pitch.fromBaseline(att, best.pose.y) then best = k end
		end
		self.advantageY = best.pose.y
		self.sheet:advantage(pitch.advantageMeters(att, best.pose.y))
	end
	self.phase = "toss"
	self:_next()
end

-- Pick the phase and current piece from the queues.
function Game:_next()
	if self.phase == "over" then return end
	if self.phase == "toss" or self.phase == "rethrow" then
		if #self.firstQueue > 0 then
			self.phase, self.current = "toss", self.firstQueue[1]
			return
		elseif #self.rethrowQueue > 0 then
			self.phase, self.current = "rethrow", self.rethrowQueue[1]
			return
		end
		self.phase = "raise"
	end
	if self.phase == "raise" then
		for _, k in ipairs(self:fieldKubbs(self.defender)) do
			if not k.pose.standing then
				self.current = k.id
				return
			end
		end
		self.phase = "punish"
	end
	if self.phase == "punish" then
		if #self.punishQueue > 0 then
			self.current = self.punishQueue[1]
			return
		end
		self.phase, self.current = "batons", nil
	end
end

local function removeFrom(list, id)
	for i, v in ipairs(list) do
		if v == id then table.remove(list, i) return true end
	end
	return false
end

-- Game over: the rest of this turn's batons are X.
function Game:_finish(winner, how)
	if self.winner then fail("winner already set") end
	self.winner, self.how = winner, how
	self.phase, self.current = "over", nil
	for _ = 1, self.batonsLeft do self.sheet:baton(nil, "X") end
	self.batonsLeft = 0
end

-- When a game ends before the inkast is done (king toppled by a kubb, or a
-- resign), the inkast token still counts every kubb that was to be thrown,
-- so it says how many kubbs the turn had (kubb.js checks I against the
-- kubbs knocked down last turn). Returns how many were added.
function Game:_completeInkast(pid)
	local pending = #self.firstQueue
	if pending > 0 then self.sheet:ink(pid, "I", pending) end
	return pending
end

-- ---------- kubb tossing (II.C) ----------

local function poseFrom(o, fallback)
	if not o then return copyPose(fallback) end
	return { x = o.x, y = o.y, standing = o.standing and true or false, angle = o.angle or 0, onTop = o.onTop }
end

-- A kubb that cannot be raised in bounds after this toss: a rethrow if it
-- has been thrown once, a punishment kubb if twice (II.C.5b/c, II.C.6,
-- II.D.11).
function Game:_out(k, pid)
	if k.thrown <= 1 then
		k.where = "out"
		self.rethrowQueue[#self.rethrowQueue + 1] = k.id
	else
		k.where = "punish"
		self.punishQueue[#self.punishQueue + 1] = k.id
		self.sheet:ink(pid, "P")
	end
end

-- Lower a kubb resting on another (II.D.6) and count N.
function Game:_settle(k, pid)
	if k.pose.onTop then
		local lower = self.kubbs[k.pose.onTop]
		local lp = lower and lower.pose or self.king.pose
		k.pose = raising.lower(k.pose, lp)
		self.sheet:ink(pid, "N")
	end
end

-- outcome: see AGENTS.md "Kubb-toss outcome".
function Game:toss(o, player)
	if self.phase ~= "toss" and self.phase ~= "rethrow" then fail("not tossing now (" .. self.phase .. ")") end
	o = o or {}
	local att, def = self.attacker, self.defender
	local pid = self:player(att, player)
	local k = self.kubbs[self.current]
	removeFrom(self.firstQueue, k.id)
	removeFrom(self.rethrowQueue, k.id)
	k.thrown = k.thrown + 1
	if k.thrown == 1 then
		self.sheet:ink(pid, "I")
		self.firstThrows = self.firstThrows + 1
	else
		self.sheet:ink(pid, "R")
	end
	self.lastTosser = pid

	if o.kingToppled then
		k.where, k.kind, k.half = "pitch", "field", def
		k.pose = poseFrom(o.rest, k.pose)
		self:_completeInkast(pid)
		self.sheet:ink(pid, "E")
		self.sheet:note("king toppled by a thrown kubb")
		self:_finish(def, "king toppled by a thrown kubb")
		return
	end

	-- Other pieces it moved. Base kubbs are stood back where they were; a
	-- piece in the thrower's own half makes it II.C.4b; out-of-play kubbs
	-- (waiting to be rethrown) are ignored.
	local ownHit = false
	for _, id in ipairs(o.ownHalfHit or {}) do
		local p = self.kubbs[id]
		if p and p.where == "pitch" and p.half == att then ownHit = true end
	end
	local struck = {}
	for id, pose in pairs(o.moved or {}) do
		if id == "king" then
			self.king.pose = poseFrom(pose, self.king.pose)
			self.king.pose.standing = true
		else
			local p = self.kubbs[id]
			if not p then fail("unknown piece " .. tostring(id)) end
			if p.where == "pitch" and p.id ~= k.id then
				if p.half == att then
					ownHit = true
				elseif p.kind == "field" then
					struck[#struck + 1] = { p = p, pose = poseFrom(pose, p.pose) }
				end
			end
		end
	end

	-- The thrown kubb.
	if ownHit then
		-- II.C.4b: the own-half kubb is put back (nothing was applied) and
		-- the thrown kubb is out; kubbs it moved in the target half stay
		-- where they came to rest (only own-half kubbs go back).
		k.where = "out"
		self:_out(k, pid)
		self.sheet:note("a kubb hit a field kubb in the thrower's own half (II.C.4b)")
	else
		k.kind, k.half, k.established = "field", def, false
		k.pose = poseFrom(o.rest, k.pose)
		k.where = "pitch"
		self:_settle(k, pid)
		if not raising.canRaise(k.pose, def) then self:_out(k, pid) end
	end

	-- Kubbs it struck (II.C.4, II.C.5).
	sort(struck, function(a, b) return a.p.id < b.p.id end)
	for _, s in ipairs(struck) do
		local p = s.p
		p.pose = s.pose
		self:_settle(p, pid)
		if not raising.canRaise(p.pose, def) then
			if p.established then
				-- II.C.5a, the rescue: back to the attacker as a kubb not
				-- yet thrown this turn.
				p.established, p.thrown, p.where = false, 0, "hand"
				self.firstQueue[#self.firstQueue + 1] = p.id
				self.sheet:ink(pid, "Q")
			else
				self:_out(p, pid)
			end
		end
	end
	self:_next()
end

-- ---------- raising (II.D) ----------

-- choice: an index into need().decision.choices, or nil for the automatic
-- chooser (game.raisePolicy, or `policy`).
function Game:raise(choice, policy)
	if self.phase ~= "raise" then fail("not raising now (" .. self.phase .. ")") end
	local k = self.kubbs[self.current]
	local ctx = self:context(self.defender, k.id)
	local dec = raising.options(k.pose, ctx)
	if #dec.choices == 0 then fail("kubb " .. k.id .. " cannot be raised in bounds") end
	if choice == nil then choice = raising.choose(dec, ctx, policy or self.raisePolicy) end
	local c = dec.choices[choice]
	if not c then fail("no raising choice " .. tostring(choice)) end
	k.pose = copyPose(c.pose)
	k.pose.standing, k.pose.onTop = true, nil
	self:_next()
	return c
end

-- Raise every pending kubb automatically.
function Game:raiseAll(policy)
	while self.phase == "raise" do self:raise(nil, policy) end
end

-- ---------- punishment kubbs (II.D.11) ----------

function Game:placePunishment(pose)
	if self.phase ~= "punish" then fail("no punishment kubb to place (" .. self.phase .. ")") end
	local k = self.kubbs[self.current]
	local p = { x = pose.x, y = pose.y, standing = true, angle = pose.angle or 0 }
	local ok, why = raising.punishmentCheck(p, self:context(self.defender, k.id))
	if not ok then return false, why end
	removeFrom(self.punishQueue, k.id)
	k.pose, k.where, k.kind, k.half = p, "pitch", "field", self.defender
	self:_next()
	return true
end

function Game:autoPunishment(policy)
	local k = self.kubbs[self.current]
	local pose = raising.autoPunishment(self:context(self.defender, k.id), policy)
	if not pose then fail("no valid punishment spot") end
	return self:placePunishment(pose)
end

-- ---------- batons (II.B) ----------

local function set(list)
	local s = {}
	for _, v in ipairs(list or {}) do s[v] = true end
	return s
end

-- outcome: see AGENTS.md "Baton outcome".
function Game:throwBaton(o, player)
	if self.phase ~= "batons" then fail("not throwing batons now (" .. tostring(self.phase) .. ")") end
	o = o or {}
	local att, def = self.attacker, self.defender
	local pid = self:player(att, player)
	local n = self.batonIndex + 1
	self.batonIndex, self.batonsLeft = n, self.batonsLeft - 1
	local kingShot = self:allDown(def)
	local toppled = set(o.toppled)
	local kingDown = o.kingToppled or toppled.king
	toppled.king = nil
	for id in pairs(toppled) do
		local k = self.kubbs[id]
		if not k then fail("unknown piece " .. tostring(id)) end
		if k.where ~= "pitch" then fail("piece " .. id .. " is not on the pitch") end
	end

	local function earlyKing(token, why)
		self.sheet:baton(pid, token)
		self.sheet:note("b" .. n .. " " .. why)
		self:_finish(def, "king toppled early")
	end

	-- II.B.1: an illegal throw (helicopter). Everything is put back and the
	-- baton is forfeited. Interpretation: a king it topples before every
	-- kubb is down still loses the game; on a king shot it is stood up.
	if o.illegal then
		if kingDown and not kingShot then
			return earlyKing("E", "illegal throw toppled the king early")
		end
		self.sheet:baton(pid, "Z")
		return self:_afterBaton()
	end

	-- II.B.11: field kubbs in the attacker's own half hit by its baton.
	local own = false
	for _, id in ipairs(o.ownHalfHit or {}) do
		local k = self.kubbs[id]
		if k and k.where == "pitch" and k.kind == "field" and k.half == att then own = true end
	end
	for id in pairs(toppled) do
		local k = self.kubbs[id]
		if k.kind == "field" and k.half == att then own = true end
	end
	for id in pairs(o.moved or {}) do
		local k = self.kubbs[id]
		if k and k.where == "pitch" and k.kind == "field" and k.half == att then own = true end
	end
	if own then
		if kingDown and not kingShot then
			return earlyKing("E", "baton hit its own half and toppled the king early")
		end
		self.sheet:baton(pid, "Z")
		self.sheet:note("b" .. n .. " hit a field kubb in the thrower's own half; all put back (II.B.11)")
		return self:_afterBaton()
	end

	-- A legal throw.
	local standingAfter = 0
	for _, k in ipairs(self:fieldKubbs(def)) do
		if not toppled[k.id] then standingAfter = standingAfter + 1 end
	end
	local f, b, early = 0, 0, 0
	local ids = {}
	for id in pairs(toppled) do ids[#ids + 1] = id end
	sort(ids)
	for _, id in ipairs(ids) do
		local k = self.kubbs[id]
		if k.half == def and k.kind == "field" then
			f = f + 1
			k.where = "hand"
			self.hand[def][#self.hand[def] + 1] = id
		elseif k.half == def and k.kind == "base" then
			if standingAfter > 0 then
				early = early + 1   -- II.B.4a: raised where it was, still a base kubb
			else
				b = b + 1
				k.where = "hand"
				self.hand[def][#self.hand[def] + 1] = id
			end
		end
		-- An attacker's own base kubb toppled: stood back up (nothing applied).
	end
	-- Pieces moved without toppling stay where they came to rest, unless
	-- pushed out of bounds (II.B.7: returned to where they were).
	local pushedOut = 0
	for id, pose in pairs(o.moved or {}) do
		if not toppled[id] then
			local piece = id == "king" and self.king or self.kubbs[id]
			if piece and (id == "king" or piece.where == "pitch") and not (id == "king" and kingDown) then
				if pitch.onPitch(pose.x, pose.y) then
					piece.pose = { x = pose.x, y = pose.y, standing = true, angle = pose.angle or piece.pose.angle or 0 }
				else
					pushedOut = pushedOut + 1
				end
			end
		end
	end
	if early > 0 then
		self.sheet:note("b" .. n .. " toppled " .. (early == 1 and "a base kubb" or (early .. " base kubbs"))
			.. " early; raised (II.B.4a)")
	end
	if pushedOut > 0 then
		self.sheet:note("b" .. n .. " pushed " .. (pushedOut == 1 and "a kubb" or (pushedOut .. " kubbs"))
			.. " out without toppling; put back (II.B.7)")
	end

	if kingShot then
		if kingDown then
			self.sheet:baton(pid, "K")
			self:_finish(att, "king")
			return
		end
		self.sheet:baton(pid, "=")
		return self:_afterBaton()
	end
	if kingDown then
		return earlyKing(notation.hitToken(f, b, true), "toppled the king early")
	end
	self.sheet:baton(pid, notation.hitToken(f, b, false))
	return self:_afterBaton()
end

function Game:_afterBaton()
	if self.phase == "over" then return end
	if self.batonsLeft <= 0 then self:_startTurn() end
end

-- ---------- resign ----------

-- Resign from the menu, on the resigning team's own turn: `G`, then X for
-- the batons left. An unfinished inkast is written in full (see
-- _completeInkast) with a note.
function Game:resign(side, player)
	if self.phase == "over" then fail("the game is over") end
	side = side or self.attacker
	if side ~= self.attacker then fail("a team resigns on its own turn") end
	local pid = self:player(side, player)
	if self.phase == "toss" or self.phase == "rethrow" then
		local tosser = self.lastTosser or pid
		local added = self:_completeInkast(tosser)
		if added > 0 or #self.rethrowQueue > 0 then self.sheet:note("resigned during the inkast") end
	end
	self.sheet:baton(pid, "G")
	self:_finish(other(side), "resigned")
end

tw.rules = rules
