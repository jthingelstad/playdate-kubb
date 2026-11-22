-- The game files the games list and the score sheets read (core/gamefile):
-- files the released game wrote before Planet Kubb Notation 2 (engine 0.13.1),
-- with their "(@ ...)" positions comments, still read
-- (tests/fixtures/legacy: the game's own files as of 0.10.0), and today's,
-- whose position lines (@a, *b ...) a screen never shows: gamefile.parse's
-- lines leave them out and gamefile.shown draws none of a comment
-- (scenes/sheet.split leaves them out the same way; self-test match-sheet).
import "core/gamefile"
local gamefile = tw.gamefile

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local function files(dir)
	local out = {}
	local p = io.popen('ls "' .. here .. "/../fixtures/" .. dir .. '"')
	for f in p:lines() do if f:match("%.txt$") then out[#out + 1] = here .. "/../fixtures/" .. dir .. "/" .. f end end
	p:close()
	return out
end
local function read(path)
	local f = assert(io.open(path)); local t = f:read("a"); f:close(); return t
end

local function checkAll(dir, wantPositions)
	local n, withPos = 0, 0
	for _, path in ipairs(files(dir)) do
		local text = read(path)
		local g, why = gamefile.parse(text)
		expect.truthy(g, path .. ": " .. tostring(why))
		local win = text:match('%[Win "Team ([AB])"%]')
		expect.eq(g.winner, win, path .. " winner")
		expect.truthy(g.turns > 0, path .. " turns")
		for _, line in ipairs(g.lines) do
			expect.truthy(not gamefile.isPosition(line), path .. ": a position line in lines")
			local shown = gamefile.shown(line)
			expect.truthy(not shown:find("%(@"), path .. ": a positions comment shown")
		end
		if text:find("%(@") or text:find("\n[@*][ab] ") then withPos = withPos + 1 end
		n = n + 1
	end
	expect.truthy(n > 0, "no files in " .. dir)
	if wantPositions then expect.truthy(withPos > 0, "no file in " .. dir .. " has positions") end
end

test("game files: the released game's (older notation, positions comments) still read", function()
	checkAll("legacy", true)
end)

test("game files: Notation 2's position lines never reach the screen", function()
	checkAll("games", true)
	expect.truthy(gamefile.isPosition("@a 2.50,1.20"), "a pitch line")
	expect.truthy(gamefile.isPosition("*b 2.50,1.20 -"), "a felled line")
	expect.eq(gamefile.shown("@a 2.50,1.20"), "", "a pitch line shown")
	expect.eq(gamefile.shown("3. 2 (@ 4.39,4.61 4.34,5.21) / 1"), "3. 2 / 1", "an old comment shown")
end)
