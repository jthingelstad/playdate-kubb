-- core/gamefile: what the games list shows of a game file.
import "core/gamefile"
local gamefile = tw.gamefile

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local dir = here .. "/../fixtures/games/"

local function read(name)
	local f = assert(io.open(dir .. name, "r"))
	local s = f:read("a")
	f:close()
	return s
end

test("gamefile: the hand-written game's summary", function()
	local s = assert(gamefile.parse(read("2026-11-20-1942-jamie-v-playdate.txt")))
	expect.eq(s.a, "Jamie"); expect.eq(s.b, "Playdate")
	expect.eq(s.winner, "A"); expect.eq(s.first, "A")
	expect.eq(s.turns, 5); expect.eq(s.minutes, 16)
	expect.eq(s.date, "NOV 20")
	-- Jamie's batons: B - | B - B - - - | 3F 2F B B K X  -> 6 thrown in turn 5, X not
	expect.eq(s.hits.A[2], 2 + 6 + 5)
	expect.eq(s.hits.A[1], 1 + 2 + 5)
	expect.eq(s.kingBaton, 5)
	expect.eq(gamefile.rate(s, "A"), math.floor(100 * 8 / 13 + 0.5))
end)

test("gamefile: every fixture game parses, with turns and a winner", function()
	local n = 0
	for name in io.popen('ls "' .. dir .. '"'):lines() do
		if name:match("%.txt$") then
			local s, why = gamefile.parse(read(name))
			expect.truthy(s, name .. ": " .. tostring(why))
			if s then
				expect.truthy(s.turns > 0, name .. " turns")
				expect.truthy(s.winner == "A" or s.winner == "B", name .. " winner")
				expect.truthy(s.hits.A[1] <= s.hits.A[2] and s.hits.B[1] <= s.hits.B[2], name .. " hits")
			end
			n = n + 1
		end
	end
	expect.truthy(n >= 10, "fixtures found: " .. n)
end)

test("gamefile: a note after # is not counted as throws", function()
	local text = '[Team A "Ash"]\n[Team B "Birch"]\n[First "Team A"]\n[Win "Team B"]\n\n'
		.. "1. a:B a:- # b1 toppled the king early\n2. b:- b:F\n"
	local s = assert(gamefile.parse(text))
	expect.eq(s.hits.A[2], 2)
	expect.eq(s.hits.A[1], 1)
	expect.eq(s.hits.B[2], 2)
end)

test("gamefile: not a game file", function()
	expect.eq((gamefile.parse("hello")), nil)
	expect.eq((gamefile.parse(nil)), nil)
end)
