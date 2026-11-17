-- Six clean batons at a lone field kubb 5.27 m out must hit it.
--
-- A replayed report from 2026-11-16, rebuilt from its geometry: a player
-- stood 0.63 m in front of the baseline, level with a field kubb 5.9 m up the
-- pitch, and threw the plan's clean baton (release 60, aimed at the kubb's
-- middle). AGENTS.md ("Aim") says a clean baton hits a kubb at 5.27 m every
-- time; each ground seed below is a different patch of turf under the
-- landing, which must not matter for a throw that strikes the kubb in the air.
local throws = {}
for seed = 1, 6 do
	throws[seed] = {
		groundSeed = seed,
		plan = { px = -0.6, py = 0.63, tx = -0.6, ty = 5.9, release = 60, aimZ = 0.075 },
	}
end

return {
	name = "clean baton at a field kubb from 5.27 m",
	surface = "grass",
	stakes = true,
	pieces = {
		{ id = "f1", kind = "kubb", x = -0.6, y = 5.9 },
		{ id = "b1", kind = "kubb", x = -2, y = 8 },
		{ id = "b2", kind = "kubb", x = -1, y = 8 },
		{ id = "b3", kind = "kubb", x = 0, y = 8 },
		{ id = "b4", kind = "kubb", x = 1, y = 8 },
		{ id = "b5", kind = "kubb", x = 2, y = 8 },
		{ id = "king", kind = "king", x = 0, y = 4 },
	},
	throws = throws,
	-- every throw topples f1 (more behind it would be fine), and no check
	-- finds anything (measured 2026-11-16: f1 alone, every throw)
	expect = { hits = "f1", clean = true },
}
