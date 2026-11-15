-- Scenario "drills-new": DOUBLES and THE WALL (core/drills) on screen. The
-- drills menu with DOUBLES chosen (frame 1: its six groups on the map), its
-- first baton's aim (frame 2: the circle on the nearest kubb of the pair),
-- that baton thrown on the plan's targets (frame 3: at rest); then THE WALL
-- chosen (frame 4: the stake and a wall on the map), its first kubb's aim
-- (frame 5: the circle by the stake), drilled on the plan's targets (frame
-- 6: at rest, lying by the stake).
import "core/tw"
import "scenes/drills"
import "input"
import "selftest/_throw"

local scene = tw.scenes.drills
local st = tw.selftest
local s, p, stage, restAt

local function feed(steps) p.steps, p.i, p.k = steps, 1, 0 end

tw.selftest.scenarios["drills-new"] = {
	step = function(ctx)
		if not s then
			p = tw.input.scripted({})
			s = scene.new(p, { scripted = true })
			scene.enter()
			-- down six times: DOUBLES
			local steps = {}
			for _ = 1, 6 do steps[#steps + 1] = { press = { "down" } }; steps[#steps + 1] = { n = 1 } end
			steps[#steps + 1] = { n = 3 }
			feed(steps)
			stage = 1
		end
		scene.update(s)
		scene.draw(s)
		local ts = s.ts
		if stage == 1 and p:finished() then
			if s.items[s.choice].id ~= "doubles" then error("chose " .. s.items[s.choice].id) end
			ctx:capture()
			feed { { press = { "a" } }, { n = 5 } }
			stage = 2
		elseif stage == 2 and p:finished() and s.phase == "run" and ts.mode == "aim" then
			if not ts.markerOn or not ts.markerOn.id:match("^g1k") then error("the circle is not on the first group") end
			ctx:capture()
			feed(st.planned(ts))
			stage, restAt = 3, nil
		elseif stage == 3 then
			if ts.mode == "rest" and not restAt then restAt = ctx.frame end
			if restAt and ctx.frame == restAt + 20 then
				ctx:capture()
				ctx.note = string.format("doubles first baton: down %d score %d", ts.last.down or -1, s.run.score)
				-- back to the menu, up once from DOUBLES: THE WALL
				scene.quit(s)
				feed { { press = { "down" } }, { n = 3 } }
				stage = 4
			end
		elseif stage == 4 and p:finished() then
			if s.items[s.choice].id ~= "wall" then error("chose " .. s.items[s.choice].id) end
			ctx:capture()
			feed { { press = { "a" } }, { n = 5 } }
			stage = 5
		elseif stage == 5 and p:finished() and s.phase == "run" and ts.mode == "aim" then
			if not ts.drill then error("THE WALL is not drilled") end
			-- the circle by the stake (2.5, 4), just inside the far half
			tw.scenes.throw.aimAt(ts, 2.2, 4.15)
			ctx:capture()
			feed(st.planned(ts))
			stage, restAt = 6, nil
		elseif stage == 6 then
			if ts.mode == "rest" and not restAt then restAt = ctx.frame end
			if restAt and ctx.frame == restAt + 20 then
				ctx:capture()
				ctx.note = ctx.note .. string.format("; wall first kubb rests %d cm from the circle", ts.last.restCm or -1)
				return true
			end
		end
		if ctx.frame > 1500 then error("stuck at stage " .. stage .. " (" .. s.phase .. ", " .. tostring(ts and ts.mode) .. ")") end
		return false
	end,
}
