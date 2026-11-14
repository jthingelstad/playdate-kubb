-- Scenario "soak": the device soak (soak.lua) for one short match (turns 1
-- and 2, the inkast and its raising among them, then the team on turn 3
-- resigns), the save read back after every throw.
-- The check: soak.txt ends with "soak done", the match finished without an
-- error and every save check passed. Frame: the title it returns to.
import "core/tw"
import "soak"

local soak = tw.soak
local st, done = nil, false

tw.selftest.scenarios.soak = {
	step = function(ctx)
		if not st then
			soak.tune.matches, soak.tune.maxTurns, soak.tune.saveCheck = 1, 2, 1
			playdate.file.delete("soak.txt")
			st = soak.start()
			return false
		end
		if not done then
			done = soak.update(st)
			return false
		end
		local f = playdate.file.open("soak.txt", playdate.file.kFileRead)
		local text = f and f:read(100000) or ""
		if f then f:close() end
		if not text:find("soak done") then error("no soak done") end
		if not text:find("0 ended by an error") then error("soak error: " .. text:sub(1, 300)) end
		if not text:find("save checks [1-9]%d*, failed 0") then error("save checks: " .. text:sub(1, 300)) end
		ctx.note = text:match("(match 1[^\n]*)")
		playdate.file.delete("soak.txt")
		playdate.graphics.clear(playdate.graphics.kColorWhite)
		ctx:capture()
		return true
	end,
}
