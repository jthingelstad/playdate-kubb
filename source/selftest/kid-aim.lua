-- Scenario "kid-aim": the player's first baton in a Kid match against the Kid computer
-- (engine 0.15), aimed by hand: the pitch with the Kid line 2 m in front of the
-- player's baseline (thin and solid), three base kubbs on the far baseline, the KID LINE
-- flag and the Kid meter's wide bars on the clock. Frames: 1 first person, 2 the plan
-- view (B held) with the whole half and the line under the thrower.
-- The check: the thrower stands on the Kid line, the plan is solved on the Kid meter
-- and its bars are wider than the standard meter's at the same throw.
import "core/tw"
import "input"
import "scenes/match"
import "core/throwplan"

local scene, throw, plan = tw.scenes.match, tw.scenes.throw, tw.plan
local ms, notes

tw.selftest.scenarios["kid-aim"] = {
	step = function(ctx)
		if not ms then
			ms = scene.new(tw.input.scripted { { n = 25 }, { hold = { "b" }, n = 40 } },
				{ vs = "B", computer = "kid", rules = "kid", skipHandoff = true, cpuSeed = 7, noSave = true,
					surface = "Grass" })
			scene.enter()
		end
		scene.update(ms)
		scene.draw(ms)
		local ts, s = ms.ts, ms.setup
		if ctx.frame == 24 then
			if not s.kid or s.side ~= "A" or s.kind ~= "baton" then error("not the player's Kid baton") end
			if math.abs(ts.playerY - s.kidY) > 1e-6 then error(string.format("stands at %.2f, the Kid line %.2f", ts.playerY, s.kidY)) end
			if ts.advText ~= "KID LINE  2.0 M" then error("flag " .. tostring(ts.advText)) end
			local m = throw.planBy(ts)
			if m ~= plan.meter("kid") then error("not on the Kid meter") end
			local sol = ts.sol
			local q = { projectile = "baton", px = ts.playerX, py = ts.playerY, tx = ts.markerX, ty = ts.markerY,
				release = ts.release, meter = plan.meter() }
			local std = plan.solve(q, {})
			local kw, sw = sol.powerHi - sol.powerLo, std.powerHi - std.powerLo
			local kr, sr = sol.releaseHi - sol.releaseLo, std.releaseHi - std.releaseLo
			if kw <= sw or kr <= sr then error("the Kid bars are not wider") end
			notes = string.format(" dist=%.2f power=%.0f/%.0f release=%.0f/%.0f", sol.dist, kw, sw, kr, sr)
			local bases = 0
			for i = 1, ts.nitems do if ts.items[i].id:match("^[ab]%d$") then bases = bases + 1 end end
			if bases ~= 6 then error(bases .. " base kubbs on the pitch, not 3 a side") end
			ctx:capture()
		elseif ctx.frame == 64 then
			ctx:capture()
			ctx.note = (ctx.note or "") .. notes
			return true
		end
		return false
	end,
}
