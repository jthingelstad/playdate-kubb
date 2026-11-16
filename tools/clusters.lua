-- How tight are the groups the kubbs are drilled into, and what do batons
-- take from them? (AGENTS.md "Real games": Jamie, "Multiple fields kubbs is
-- all about drilling tight clusters.") Plays physics matches like
-- tools/physmatch.lua, with the computer's mistakes scaled separately for
-- its kubbs and its batons, and measures, at the first baton of every turn
-- that has two or more field kubbs standing to clear:
--   the gap from each field kubb to its nearest neighbour (edge to edge),
--   the group's spread (rms distance from its middle),
--   the largest group chained by gaps of 15 cm or less,
-- and, over the turn's batons thrown while a field kubb stood: how many
-- field kubbs each took. A measuring tool; it changes nothing in the game.
--
--   lua5.4 tools/clusters.lua [--n 60] [--seed 2] [--drill 1] [--baton 1]
--     [--raise apart|together] [--maxturns 40]
--
-- --drill and --baton multiply every mistake of the computer's swing for
-- kubbs and for batons (1: the game's Playdate; 0: the plan's clean throw).

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end

import "core/match"
import "core/world"
import "core/autothrow"
import "core/raising"
import "core/rect"
local match, world, autothrow, raising, rect = tw.match, tw.world, tw.autothrow, tw.raising, tw.rect
local fmt = string.format

local n, seed, drill, baton, raise, maxTurns = 60, 2, 1, 1, "apart", 40
local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--n" then n = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--seed" then seed = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--drill" then drill = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--baton" then baton = tonumber(arg[i + 1]); i = i + 1
	elseif a == "--raise" then raise = arg[i + 1]; i = i + 1
	elseif a == "--maxturns" then maxTurns = tonumber(arg[i + 1]); i = i + 1
	else error("unknown argument " .. a) end
	i = i + 1
end

local LINK = 0.15
local BUCKETS = { 0.005, 0.03, 0.07, 0.15, 0.30 }
local LABELS = { "touching", "to 3 cm", "3-7 cm", "7-15 cm", "15-30 cm", "over 30 cm" }
local hist, samples, gapSum = {}, 0, 0
for b = 1, #BUCKETS + 1 do hist[b] = 0 end
local turnsSeen, spreadSum, groupSum, kubbSum, groupShare = 0, 0, 0, 0, 0
local took = { [0] = 0, 0, 0, 0 }
local fieldBatons, tosses, rethrown, turns, kings = 0, 0, 0, 0, 0

-- The field kubbs standing in `half` and what the turn's first baton faces.
local function measure(g, half)
	local ks = {}
	for _, k in ipairs(g:onPitch()) do
		if k.half == half and k.kind == "field" and k.pose.standing and not k.pose.onTop then ks[#ks + 1] = k end
	end
	if #ks < 2 then return end
	local rs, cx, cy = {}, 0, 0
	for j, k in ipairs(ks) do
		rs[j] = raising.kubbRect(k.pose)
		cx, cy = cx + k.pose.x, cy + k.pose.y
	end
	cx, cy = cx / #ks, cy / #ks
	local link, sq = {}, 0
	for j, k in ipairs(ks) do
		local best = math.huge
		link[j] = {}
		for o = 1, #ks do
			if o ~= j then
				local d = rect.distance(rs[j], rs[o])
				if d < best then best = d end
				if d <= LINK then link[j][#link[j] + 1] = o end
			end
		end
		local b = 1
		while b <= #BUCKETS and best >= BUCKETS[b] do b = b + 1 end
		hist[b] = hist[b] + 1
		samples, gapSum = samples + 1, gapSum + best
		sq = sq + (k.pose.x - cx) ^ 2 + (k.pose.y - cy) ^ 2
	end
	-- the largest group chained by gaps of LINK or less
	local seen, biggest = {}, 1
	for j = 1, #ks do
		if not seen[j] then
			local stack, size = { j }, 0
			seen[j] = true
			while #stack > 0 do
				local c = table.remove(stack)
				size = size + 1
				for _, o in ipairs(link[c]) do
					if not seen[o] then seen[o] = true; stack[#stack + 1] = o end
				end
			end
			if size > biggest then biggest = size end
		end
	end
	turnsSeen = turnsSeen + 1
	spreadSum = spreadSum + math.sqrt(sq / #ks)
	groupSum, kubbSum = groupSum + biggest, kubbSum + #ks
	groupShare = groupShare + biggest / #ks
end

local t0 = os.clock()
for gi = 1, n do
	local m = match.new { start = { year = 2026, month = 11, day = 20, hour = 9, min = 0 },
		first = (gi % 2 == 0) and "B" or "A", raisePolicy = raise }
	m.game.raisePolicy = raise
	local r = autothrow.rng(seed * 7919 + gi)
	local last = -1
	while not match.over(m) and m.game.turn <= maxTurns do
		local s = match.setup(m)
		if not s then break end
		local g = m.game
		local half = (s.side == "A") and "B" or "A"
		local fieldUp = 0
		if s.kind == "baton" then
			if g.turn ~= last and not s.kingShot then
				last = g.turn
				measure(g, half)
			end
			for _, k in ipairs(g:onPitch()) do
				if k.half == half and k.kind == "field" and k.pose.standing then fieldUp = fieldUp + 1 end
			end
		end
		local a = autothrow.choose(s, r, s.kind == "toss" and drill or baton)
		local w = world.new { surface = "grass", pieces = match.worldPieces(s) }
		autothrow.launch(w, s, a)
		world.run(w)
		local res = world.result(w)
		if s.kind == "baton" and fieldUp > 0 and not s.kingShot then
			local down = 0
			if a.legal then
				for _, id in ipairs(res.toppled) do
					local k = g.kubbs[id]
					if k and k.kind == "field" and k.half == half then down = down + 1 end
				end
			end
			fieldBatons = fieldBatons + 1
			took[down > 3 and 3 or down] = took[down > 3 and 3 or down] + 1
		end
		match.resolve(m, res, not a.legal)
		if s.kind == "toss" then
			tosses = tosses + 1
			local j = m.game.judgment
			if j then rethrown = rethrown + j.rethrow end
		end
	end
	turns = turns + m.game.turn
	if m.game.how == "king" then kings = kings + 1 end
end

local function pct(a, b) return b > 0 and fmt("%.1f%%", 100 * a / b) or "-" end
print(fmt("clusters: %d matches, seed %d, drill mistakes x%g, baton mistakes x%g, raised %s (%.0f s)",
	n, seed, drill, baton, raise, os.clock() - t0))
print(fmt("  turns a game %.1f, ended on the king %s, kubbs rethrown %s of %d",
	turns / n, pct(kings, n), pct(rethrown, tosses), tosses))
print(fmt("  turns measured (two or more field kubbs standing): %d, %.1f kubbs each", turnsSeen,
	turnsSeen > 0 and kubbSum / turnsSeen or 0))
print(fmt("  a field kubb's gap to its nearest neighbour: mean %.1f cm", samples > 0 and 100 * gapSum / samples or 0))
for b = 1, #BUCKETS + 1 do print(fmt("    %-11s %s", LABELS[b], pct(hist[b], samples))) end
print(fmt("  spread (rms from the group's middle) %.0f cm; largest group chained by gaps of %d cm or less: %.1f kubbs, %s of the field",
	turnsSeen > 0 and 100 * spreadSum / turnsSeen or 0, LINK * 100, turnsSeen > 0 and groupSum / turnsSeen or 0,
	turnsSeen > 0 and fmt("%.0f%%", 100 * groupShare / turnsSeen) or "-"))
print(fmt("  batons at field kubbs %d: missed %s, one %s, two %s, three or more %s", fieldBatons,
	pct(took[0], fieldBatons), pct(took[1], fieldBatons), pct(took[2], fieldBatons), pct(took[3], fieldBatons)))
