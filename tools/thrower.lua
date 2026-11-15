-- A random thrower for headless games: it invents plausible throw outcomes
-- WITHOUT physics (hit or miss by distance, multi-kubb hits when kubbs are
-- close, inkast landing spots with scatter) and plays whole games through
-- source/core/rules.lua. Seeded and reproducible.
--
-- Loaded with dofile/loadfile after an `import` shim is defined (the test
-- runner's, or tools/games.lua's). Returns the module table.
--
--   local thrower = dofile("tools/thrower.lua")
--   local g, stats = thrower.playGame(seed)   -- a finished tw.rules game
--
-- Rates are tunables below; they aim for a spread of rare events across a
-- few hundred games, not for realism.

import "core/rules"
import "core/raising"
import "core/pitch"
import "core/order"

local rules, raising, pitch, order = tw.rules, tw.raising, tw.pitch, tw.order
local sqrt, log, cos, sin, pi, abs, floor = math.sqrt, math.log, math.cos, math.sin, math.pi, math.abs, math.floor

local thrower = {}

thrower.tune = {
	skill = { 0.12, 0.5 },     -- per-team baton hit chance at 8 m, drawn per game
	closeBonus = 0.06,         -- extra hit chance per meter closer than 8 m
	illegal = 0.015,           -- helicopter chance per baton
	ownHalf = 0.02,            -- chance a baton from an advantage line clips an own-half kubb
	neighbour = 0.35,          -- m: kubbs this close to the struck one may go too
	neighbourTopple = 0.45,
	push = 0.12,               -- chance a nearby kubb is pushed without toppling
	kingNear = 0.6,            -- m: a hit this close to the king may topple it
	kingTopple = 0.05,
	kingShot = 0.15,           -- added to skill for a king shot (4 m from the baseline)
	tossScatter = { 0.45, 0.55 }, -- m, x and y sd of the landing spot
	standOnEnd = 0.06,         -- a tossed kubb lands standing on an end
	onTop = 0.5,               -- landing within 12 cm of a kubb: it rests on top
	rescueTry = 0.12,          -- with established kubbs in the target half, aim at one
	chaseOut = 0.25,           -- with a kubb of this turn lying out near the half, aim at it
	                           -- (kubbs are judged where they lie once the round is over)
	shortTry = 0.03,           -- aim short, into the thrower's own half
	tossKing = 0.25,           -- landing within 15 cm of the king topples it
	resignBaton = 0.0012,      -- per baton, a team behind on kubbs resigns
	resignToss = 0.002,        -- per toss
	maxTurns = 80,             -- then the team on turn resigns
	changeThrower = 0.08,      -- per baton, the team tries another player on it (core/order)
	changeInkaster = 0.15,     -- per turn with kubbs, another player throws them in
}

-- Park-Miller minimal standard generator: integers only, same on every Lua 5.4.
function thrower.rng(seed)
	-- Consecutive seeds give nearly equal first outputs, so scramble the seed
	-- (a 32-bit integer hash) and throw the first few outputs away.
	local h = floor(seed) & 0xffffffff
	h = ((h ~ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h = ((h ~ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h = h ~ (h >> 16)
	local s = h % 2147483647
	if s <= 0 then s = s + 2147483646 end
	local r = {}
	function r.next()
		s = (s * 48271) % 2147483647
		return (s - 1) / 2147483646
	end
	for _ = 1, 8 do r.next() end
	function r.uniform(a, b) return a + (b - a) * r.next() end
	function r.chance(p) return r.next() < p end
	function r.int(a, b) return a + floor(r.next() * (b - a + 1)) end
	function r.pick(list) return list[r.int(1, #list)] end
	function r.normal(sd)
		local u1 = r.next()
		if u1 < 1e-12 then u1 = 1e-12 end
		return sd * sqrt(-2 * log(u1)) * cos(2 * pi * r.next())
	end
	return r
end

local function dist(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return sqrt(dx * dx + dy * dy)
end

local Thrower = {}
Thrower.__index = Thrower

function thrower.new(seed, opts)
	local t = setmetatable({}, Thrower)
	t.r = thrower.rng(seed)
	t.skill = { A = t.r.uniform(thrower.tune.skill[1], thrower.tune.skill[2]),
		B = t.r.uniform(thrower.tune.skill[1], thrower.tune.skill[2]) }
	t.stats = {}
	return t
end

function Thrower:count(what)
	self.stats[what] = (self.stats[what] or 0) + 1
end

-- ---------- kubb tossing ----------

function Thrower:toss(g, need)
	local r, tune = self.r, thrower.tune
	local att, def = need.side, need.half
	local dirY = def == "B" and 1 or -1
	local aim
	local established = {}
	for _, k in ipairs(g:fieldKubbs(def)) do
		if k.established then established[#established + 1] = k end
	end
	-- kubbs thrown this turn that lie out for now, near enough to knock in
	local outNear = {}
	for _, k in ipairs(g:fieldKubbs(def)) do
		if k.thrown > 0 and g:liesNow(k.id) == "out" and not k.fouled and abs(k.pose.x) < 3
			and pitch.fromBaseline(def, k.pose.y) > -0.8 and pitch.fromBaseline(def, k.pose.y) < 4.8 then
			outNear[#outNear + 1] = k
		end
	end
	local rescue, chase = false, false
	if #outNear > 0 and r.chance(tune.chaseOut) then
		local k = r.pick(outNear)
		aim = { x = k.pose.x, y = k.pose.y }
		chase = true
	elseif #established > 0 and r.chance(tune.rescueTry) then
		local k = r.pick(established)
		aim = { x = k.pose.x, y = k.pose.y }
		rescue = true
	elseif r.chance(tune.shortTry) then
		aim = { x = r.uniform(-2, 2), y = 4 - dirY * r.uniform(0.1, 0.6) }
	else
		aim = { x = r.uniform(-2.1, 2.1), y = 4 + dirY * r.uniform(0.3, 3.2) }
	end
	local land = { x = aim.x + r.normal(tune.tossScatter[1]), y = aim.y + r.normal(tune.tossScatter[2]) }
	if rescue or chase then land.x, land.y = aim.x + r.normal(0.1), aim.y + r.normal(0.1) end
	local o = { moved = {} }
	-- The king.
	if dist(land, g.king.pose) < 0.15 and r.chance(tune.tossKing) then
		o.kingToppled = true
		self:count("tossKing")
	end
	-- Landing on or against kubbs.
	local nearest, nd
	for _, k in ipairs(g:onPitch()) do
		local d = dist(land, k.pose)
		if not nearest or d < nd then nearest, nd = k, d end
	end
	local rest = { x = land.x, y = land.y, standing = false, angle = r.uniform(0, 2 * pi) }
	if r.chance(tune.standOnEnd) then rest.standing = true; self:count("standOnEnd") end
	if nearest and nd < 0.12 and r.chance(tune.onTop) then
		rest.standing, rest.onTop = false, nearest.id
		self:count("onTop")
	elseif nearest and nd < 0.3 then
		-- Knock it.
		local k = nearest
		local dx, dy = k.pose.x - land.x, k.pose.y - land.y
		local len = sqrt(dx * dx + dy * dy)
		if len < 1e-6 then dx, dy, len = 1, 0, 1 end
		local push = rescue and r.uniform(0.6, 2.5) or r.uniform(0.05, 0.6)
		local mx, my = dx / len, dy / len
		if chase then
			-- toward the middle of the target half
			local cx, cy = 0, pitch.baseline[def] - dirY * 2
			local ex, ey = cx - k.pose.x, cy - k.pose.y
			local el = sqrt(ex * ex + ey * ey)
			if el > 1e-6 then mx, my = ex / el, ey / el end
			push = r.uniform(0.2, 1.5)
		elseif rescue then
			-- toward the nearest sideline or the baseline
			local toSide = 2.5 - abs(k.pose.x)
			local toBase = pitch.fromBaseline(def, k.pose.y)
			if toSide < toBase then mx, my = (k.pose.x < 0 and -1 or 1), 0 else mx, my = 0, dirY end
		end
		o.moved[k.id] = { x = k.pose.x + mx * push, y = k.pose.y + my * push,
			standing = not r.chance(0.6), angle = r.uniform(0, 2 * pi) }
		-- a kubb of this turn knocked across a line before the round is judged
		if k.thrown > 0 and k.half == def and not k.fouled then
			local was, now = raising.canRaise(k.pose, def), raising.canRaise(o.moved[k.id], def)
			if not was and now then self:count("knockedIn") elseif was and not now then self:count("knockedOut") end
		end
		self:count(k.half == att and "tossOwnHalf" or (k.kind == "base" and "tossBase" or "tossStruck"))
	end
	o.rest = rest
	return o
end

-- ---------- batons ----------

function Thrower:baton(g, need)
	local r, tune = self.r, thrower.tune
	local att, def = need.side, pitch.other(need.side)
	local skill = self.skill[att]
	local o = { toppled = {}, moved = {} }
	local own = g:fieldKubbs(att)
	if need.advantageY and #own > 0 and r.chance(tune.ownHalf) then
		o.ownHalfHit = { r.pick(own).id }
		self:count("ownHalf")
	end
	if r.chance(tune.illegal) then
		o.illegal = true
		self:count("illegal")
	end
	if need.kingShot then
		if r.chance(skill + tune.kingShot) then
			o.kingToppled = true
		end
		return o
	end
	local target = g.kubbs[r.pick(need.targets)]
	local d = sqrt((target.pose.y - need.throwY) ^ 2 + target.pose.x ^ 2 * 0.1)
	local p = skill + (8 - d) * tune.closeBonus
	if p > 0.92 then p = 0.92 elseif p < 0.05 then p = 0.05 end
	if r.chance(p) then
		o.toppled[#o.toppled + 1] = target.id
		o.moved[target.id] = { x = target.pose.x, y = target.pose.y + r.normal(0.1), standing = false, angle = r.uniform(0, 2 * pi) }
		for _, k in ipairs(g:onPitch(function(k) return k.half == def and k.id ~= target.id end)) do
			local dk = dist(k.pose, target.pose)
			if dk < tune.neighbour and r.chance(tune.neighbourTopple) then
				o.toppled[#o.toppled + 1] = k.id
				if k.kind == "base" then self:count("batonBase") end
			elseif dk < 2 * tune.neighbour and r.chance(tune.push) then
				local dx = k.pose.x - target.pose.x
				local push = r.uniform(0.05, 0.4)
				o.moved[k.id] = { x = k.pose.x + (dx >= 0 and push or -push), y = k.pose.y + r.normal(0.1), standing = true, angle = 0 }
				self:count("pushed")
			end
		end
		if dist(target.pose, g.king.pose) < tune.kingNear and r.chance(tune.kingTopple) then
			o.kingToppled = true
			self:count("batonKing")
		end
	end
	return o
end

-- ---------- defender choices ----------

function Thrower:raise(g, need)
	local dec = need.decision
	self:count("raise_" .. dec.mode)
	local u = self.r.next()
	if u < 0.5 then return nil, "apart" end
	if u < 0.7 then return nil, "together" end
	return self.r.int(1, #dec.choices)
end

function Thrower:punish(g, need)
	self:count("punish")
	local r = self.r
	if r.chance(0.5) then return nil end
	return function(cands) return r.pick(cands) end
end

-- ---------- a whole game ----------

-- Invented teams. Names exercise id derivation: punctuation, a clash
-- ("Dana" twice), and every team size from one to six (core/order).
local TEAMS = {
	{ "Jamie", { "Jamie" } }, { "Playdate", { "Club" } }, { "Field Day", { "Ann-Marie O'Neil", "Robin" } },
	{ "Snow Kubbs", { "Alex", "Kim", "Max" } }, { "Twin Pines", { "Dana", "Dana" } },
	{ "Wood Chucks", { "Lee" } }, { "Corner Stakes", { "Jo", "Pat" } }, { "Baton Rouge", { "Sam" } },
	{ "Backyard", { "Backyard" } }, { "Long Lob", { "Ray", "Kit" } },
	{ "Four Corners", { "Nell", "Otto", "Pia", "Quin" } },
	{ "High Five", { "Rae", "Sol", "Tam", "Uma", "Vic" } },
	{ "Six Pack", { "Wes", "Xan", "Yara", "Zed", "Abe", "Bea" } },
	{ "Full House", { "Cy", "Di", "Eli", "Fay", "Gus", "Hal" } },
}

-- Random game options from a seed.
function thrower.options(r)
	local a = r.int(1, #TEAMS)
	local b = r.int(1, #TEAMS - 1)
	if b >= a then b = b + 1 end
	local function team(i)
		local t = TEAMS[i]
		local players = {}
		for j, n in ipairs(t[2]) do players[j] = { name = n } end
		return { name = t[1], players = players }
	end
	return {
		teams = { A = team(a), B = team(b) },
		surface = r.chance(0.5) and "Grass" or "Sand",
		opening = r.chance(0.7) and "2-4-6" or "six",
		first = r.chance(0.5) and "A" or "B",
	}
end

local function standingCount(g, side)
	return #g:fieldKubbs(side) + #g:baseKubbs(side)
end

-- Plays one game to the end. Returns the game and the thrower (its stats).
-- `check(g)` is called after every action when given (for invariant tests).
-- check(g) runs after every action; swap(g, o), if given, may return a
-- game and an order (core/order) to carry on with instead (tests: a game
-- saved and restored mid-match).
-- Who throws is core/order's; now and then the team changes a baton's
-- thrower or its inkaster, drawn from its own generator so the throws
-- themselves are the same with or without it.
function thrower.playGame(seed, check, swap)
	local t = thrower.new(seed)
	local r = t.r
	local g = rules.new(thrower.options(r))
	local o = order.new(g.teams)
	local ro = thrower.rng(seed * 31 + 7)
	local function member(side)
		local ps = g.teams[side].players
		return ps[ro.int(1, #ps)].id
	end
	local inkastTried = nil
	local function tosser()
		order.thrower(o, g)
		if g.phase == "toss" and inkastTried ~= g.turn then
			inkastTried = g.turn
			if ro.chance(thrower.tune.changeInkaster) and order.setInkaster(o, member(g.attacker)) then
				t:count("changeInkaster")
			end
		end
		return order.thrower(o, g)
	end
	local function batonThrower(need)
		order.thrower(o, g)
		if ro.chance(thrower.tune.changeThrower) then
			if order.change(o, need.n, member(need.side), need.n - 1) then t:count("changeThrower")
			else t:count("changeRefused") end
		end
		return order.thrower(o, g)
	end
	local steps = 0
	while true do
		local need = g:need()
		steps = steps + 1
		if steps > 20000 then error("game did not end") end
		if need.kind == "over" then break end
		if g.turn > thrower.tune.maxTurns and (need.kind == "toss" or need.kind == "baton") then
			g:resign(g.attacker, order.thrower(o, g))
			t:count("resignLong")
		elseif need.kind == "toss" then
			if r.chance(thrower.tune.resignToss) then
				g:resign(need.side, order.thrower(o, g))
				t:count("resignToss")
			else
				g:toss(t:toss(g, need), tosser())
			end
		elseif need.kind == "raise" then
			local choice, policy = t:raise(g, need)
			g:raise(choice, policy)
		elseif need.kind == "punish" then
			g:autoPunishment(t:punish(g, need))
		elseif need.kind == "baton" then
			local behind = standingCount(g, need.side) - standingCount(g, pitch.other(need.side)) >= 4
			if behind and r.chance(thrower.tune.resignBaton * 10) or r.chance(thrower.tune.resignBaton) then
				g:resign(need.side, order.thrower(o, g))
				t:count("resign")
			else
				g:throwBaton(t:baton(g, need), batonThrower(need))
			end
		end
		if check then check(g) end
		if swap then
			local g2, o2 = swap(g, o)
			g, o = g2 or g, o2 or o
		end
	end
	t:count("winBy_" .. g.how)
	return g, t
end

return thrower
