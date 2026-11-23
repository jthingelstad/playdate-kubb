-- Scenario "games": the games list and a score sheet (scenes/games) over
-- three game files (one with two ten-letter names) written for the test into the Data folder's
-- selftest-games/. Frames: 1 the list (newest first), 2 the second game
-- chosen, 3 its score sheet, 4 scrolled down with the crank. Then B twice
-- must go back to the list and on to the title.
import "core/tw"
import "scenes/games"
import "input"

local games = tw.scenes.games
local s

local function file(start, a, b, win, turns)
	local lines = {
		'[Event "Throwing Wood"]', '[Location "Playdate"]', '[Start "' .. start .. '"]',
		'[Duration "' .. (turns * 3) .. 'm"]', '[Surface "Grass"]',
		'[Team A "' .. a .. '"]', '[Team A Players "' .. a .. ' (a)"]',
		'[Team B "' .. b .. '"]', '[Team B Players "' .. b .. ' (b)"]',
		'[First "Team A"]', '[Win "Team ' .. win .. '"]', '[Rules "U.S. Championship 4.0, 2-4-6"]', '',
		'1. a:B a:-', '2. b:I b:- b:- b:F b:-',
	}
	for t = 3, turns - 1 do lines[#lines + 1] = t .. ". " .. ((t % 2 == 1) and "a:I a:F a:- a:B a:- a:- a:-" or "b:I b:F b:- b:- b:- b:- b:-") end
	lines[#lines + 1] = turns .. ". " .. ((win == "A") and "a:5I a:3F a:2F a:B a:B a:K X" or "b:5I b:3F b:2F b:B b:B b:K X")
	return table.concat(lines, "\n") .. "\n"
end

tw.selftest.scenarios.games = {
	step = function(ctx)
		local f = ctx.frame
		if f == 1 then
			local dir = "selftest-games"
			playdate.file.mkdir(dir)
			for _, g in ipairs {
				{ "2026-11-18-1900-woodchucks-v-lumberjack.txt", "2026-11-18 19:00", "Woodchucks", "Lumberjack", "B", 19 },
				{ "2026-11-19-2010-ash-v-playdate.txt", "2026-11-19 20:10", "Ash", "Playdate", "A", 7 },
				{ "2026-11-20-2130-oak-v-birch-grove.txt", "2026-11-20 21:30", "Oak", "Birch Grov", "A", 15 },
			} do
				local fh = playdate.file.open(dir .. "/" .. g[1], playdate.file.kFileWrite)
				fh:write(file(g[2], g[3], g[4], g[5], g[6]))
				fh:close()
			end
			s = games.new(tw.input.scripted {
				{ n = 1 }, { press = { "down" } }, { n = 1 }, { press = { "a" } }, { n = 1 },
				{ crank = 20, n = 10 }, { n = 1 }, { press = { "b" } }, { n = 1 }, { press = { "b" } }, { n = 2 },
			}, { dir = dir })
			games.enter()
		end
		games.update(s)
		games.draw(s)
		if f == 1 then
			if #s.files ~= 3 or not s.files[1]:find("2026%-11%-20") then error("files " .. #s.files) end
			ctx:capture()
		elseif f == 3 then
			if s.sel ~= 2 then error("down chose " .. s.sel) end
			local g = games.summary(s, 2)
			if not g or g.a ~= "Ash" or g.b ~= "Playdate" or g.winner ~= "A" then error("second game") end
			ctx:capture()
		elseif f == 5 then
			if s.view ~= "sheet" then error("A did not open the score sheet") end
			ctx:capture()
		elseif f == 15 then
			if not s.sheet or s.sheet.y <= 0 then error("the crank did not scroll") end
			ctx:capture()
		elseif f == 17 then
			if s.view ~= "list" then error("B did not go back to the list") end
		elseif f >= 19 then
			if s.exit ~= "title" then error("B did not leave for the title") end
			for _, name in ipairs(playdate.file.listFiles("selftest-games") or {}) do
				playdate.file.delete("selftest-games/" .. name)
			end
			playdate.file.delete("selftest-games")
			return true
		end
		return false
	end,
}
