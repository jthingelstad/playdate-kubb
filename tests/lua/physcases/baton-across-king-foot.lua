-- A baton across the edge at the king's foot must not sink into it.
--
-- From lua5.4 tools/physfuzz.lua --repro 1:1227 (grass, a baton at the
-- king). The baton crossed the edge between one side of the king and its
-- foot, its end past the foot, spinning at 31 to 36 rad/s. With one contact
-- at the closest point it turned about it and went 22 mm into the king for
-- 0.05 s. With the stretch along the side clipped to the king and a contact
-- at each end, it does not go in. It must topple the king, cleanly.
return {
	name = "baton across the king's foot (1:1227)",
	surface = "grass",
	stakes = true,
	pieces = {
		{ id = "king", kind = "king", x = 0, y = 4, qw = 1, qx = 0, qy = 0, qz = 0 },
	},
	throws = {
		{ groundSeed = 769536265, state = { kind = "baton", id = "baton", exact = true, 0, 0, 0.59999999999999998, 0.9983043613435405, 0.00013681225170143152, -0.058162437196315329, 0.0023482555776982096, -0.027693620494967538, 5.886605660314542, 2.9652210085775361, -10.573016234848691, -0.049740906048628464, -1.2362035682722365 } },
	},
	expect = { toppled = { "king" }, clean = true },
}
