-- Seeded random games through the engine (tools/thrower.lua, no physics),
-- checking the engine's invariants after every action, and a replay of the
-- score sheet that mirrors the counting kubb.js does (the Node gate checks
-- kubb.js itself; this runs on GitHub too).
import "core/rules"
import "core/notation"
local notation = tw.notation

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local thrower = dofile(here .. "/../../tools/thrower.lua")

local function count(list, id)
	local n = 0
	for _, v in ipairs(list) do if v == id then n = n + 1 end end
	return n
end

local function checkInvariants(g, seen)
	local c = g:census()
	if c.total ~= 10 then error("census total " .. c.total) end
	for _, id in ipairs(g.ids) do
		local k = g.kubbs[id]
		local inHand = count(g.hand.A, id) + count(g.hand.B, id) + count(g.firstQueue, id)
		local inRe, inPun = count(g.rethrowQueue, id), count(g.punishQueue, id)
		if k.where == "hand" and inHand ~= 1 then error(id .. " in hand " .. inHand .. " times") end
		if k.where ~= "hand" and inHand ~= 0 then error(id .. " queued but " .. k.where) end
		if (k.where == "out") ~= (inRe == 1) or inRe > 1 then error(id .. " rethrow queue mismatch") end
		if (k.where == "punish") ~= (inPun == 1) or inPun > 1 then error(id .. " punish queue mismatch") end
		-- judged at the final position: only kubbs on the pitch wait to be
		-- judged, and once the kubb throwing is over nothing does
		if k.fouled and k.where ~= "pitch" then error(id .. " fouled but " .. k.where) end
		if g.phase == "batons" and g.batonIndex == 0 and k.where == "pitch" then
			if k.fouled or k.pose.onTop then error(id .. " not judged after the inkast") end
			if k.kind == "field" and k.half == g.defender and not tw.raising.canRaise(k.pose, g.defender) then
				error(id .. " out but still on the pitch after the inkast")
			end
		end
	end
	if seen.winner and g.winner ~= seen.winner then error("winner changed") end
	if g.winner then seen.winner = g.winner end
	if (g.phase == "over") ~= (g.winner ~= nil) then error("phase/winner mismatch") end
end

-- Mirror of kubb.js analyze(): inkast count, advantage, F/B against what stands.
local function replay(g)
	local field = { A = 0, B = 0 }
	local prev = 0
	local ended = false
	for n, t in ipairs(g.sheet.turns) do
		if ended then error("turn " .. n .. " after the game ended") end
		local att = t.side
		local def = att == "A" and "B" or "A"
		local I, Q = 0, 0
		for _, pid in ipairs(t.inkastOrder) do
			I = I + t.inkast[pid].I; Q = Q + t.inkast[pid].Q
		end
		local thrown = #t.inkastOrder > 0 and I or prev
		if #t.inkastOrder > 0 and I ~= prev + Q then error(("turn %d: inkast %d, expected %d"):format(n, I, prev + Q)) end
		if #t.inkastOrder == 0 and prev ~= 0 then error("turn " .. n .. ": missing inkast") end
		field[def] = math.max(0, field[def] - Q) + thrown
		if (t.advantage ~= nil) ~= (field[att] > 0) then error("turn " .. n .. ": advantage marked wrongly") end
		local knocked, thrownBatons = 0, 0
		local over = false
		for _, pid in ipairs(t.inkastOrder) do if t.inkast[pid].E then over = true end end
		for _, b in ipairs(t.batons) do
			local tok = b.token
			if over then
				if tok ~= "X" then error("turn " .. n .. ": " .. tok .. " after the game ended") end
			elseif tok == "X" then
				error("turn " .. n .. ": X before the game ended")
			else
				if tok ~= "G" then thrownBatons = thrownBatons + 1 end
				local f, bb, e = tok:match("^(%d*F?)(%d*B?)(E?)$")
				if tok == "K" or tok == "G" or tok == "E" then over = true
				elseif tok ~= "-" and tok ~= "=" and tok ~= "Z" then
					local nf = f == "" and 0 or (f == "F" and 1 or tonumber(f:sub(1, -2)))
					local nb = bb == "" and 0 or (bb == "B" and 1 or tonumber(bb:sub(1, -2)))
					if nf > field[def] then error("turn " .. n .. ": " .. tok .. " with " .. field[def] .. " standing") end
					field[def] = field[def] - nf
					if nb > 0 and field[def] > 0 then error("turn " .. n .. ": B with field kubbs standing") end
					knocked = knocked + nf + nb
					if e == "E" then over = true end
				end
			end
		end
		if thrownBatons > g.batonsFor(n) then error("turn " .. n .. ": too many batons") end
		ended = over
		prev = knocked
	end
	if not ended then error("the sheet never ends the game") end
end

test("50 seeded random games: invariants hold after every action and the sheet replays cleanly", function()
	local endings = {}
	for seed = 1, 50 do
		local seen = {}
		local g = thrower.playGame(seed, function(game) checkInvariants(game, seen) end)
		expect.truthy(g.winner, "seed " .. seed .. " has a winner")
		endings[g.how] = (endings[g.how] or 0) + 1
		g.batonsFor = function(n) return tw.rules.batonsFor(g.opening, n) end
		local ok, err = pcall(replay, g)
		if not ok then error("seed " .. seed .. ": " .. tostring(err)) end
		expect.eq(pcall(g.throwBaton, g, {}), false, "no baton after game over")
		expect.eq(pcall(g.toss, g, {}), false, "no toss after game over")
		expect.eq(pcall(g.resign, g, "A"), false, "no resign after game over")
		local text = notation.render(g, {})
		expect.truthy(text:find('[Win "Team ' .. g.winner .. '"]', 1, true))
	end
	expect.truthy((endings.king or 0) > 10, "most games end with the king")
end)

test("the generator is reproducible: same seed, same game file", function()
	local a = notation.render((thrower.playGame(1234)), {})
	local b = notation.render((thrower.playGame(1234)), {})
	expect.eq(a, b)
	expect.truthy(a ~= notation.render((thrower.playGame(1235)), {}))
end)
