-- Scenario "options-kid": the match options against the Playdate (scenes/options),
-- COMPUTER stepped to KID (engine 0.15: Kid first, before BEGINNER, from
-- core/matchopts' order), then A. Frames: 1 COMPUTER on KID with its line ("KID
-- RULES: ..."). The check: from CLUB, left reaches BEGINNER then KID, and A gives a
-- Kid match (opts.computer and opts.rules "kid").
import "core/tw"
import "scenes/options"
import "input"

local scene = tw.scenes.options
local s

tw.selftest.scenarios["options-kid"] = {
	step = function(ctx)
		if not s then
			s = scene.new(tw.input.scripted {
				{ n = 1 }, { press = { "up" } }, { n = 1 }, { press = { "left" } }, { n = 1 },
				{ press = { "left" } }, { n = 2 }, { press = { "a" } }, { n = 2 },
			}, "vs", { scripted = true })
			scene.enter()
		end
		scene.update(s)
		scene.draw(s)
		local f = ctx.frame
		local v = tw.matchopts.value(s.choice, "computer")
		if f == 1 and v ~= "club" then error("COMPUTER starts on " .. v) end
		if f == 4 and v ~= "beginner" then error("left from CLUB gave " .. v) end
		if f == 6 then
			if v ~= "kid" then error("left from BEGINNER gave " .. v) end
			if s.rows[s.row].key ~= "computer" then error("not on COMPUTER") end
			ctx:capture()
		end
		if s.done then
			local o = scene.apply(s, { vs = "B" })
			if o.computer ~= "kid" or o.rules ~= "kid" or o.scene ~= "bw" then
				error(string.format("options %s %s %s", tostring(o.computer), tostring(o.rules), tostring(o.scene)))
			end
			return true
		end
		if f > 30 then error("A did not start") end
		return false
	end,
}
