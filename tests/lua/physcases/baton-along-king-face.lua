-- A baton lying along the king's face must not sink into it.
--
-- From lua5.4 tools/physfuzz.lua --repro 1:5977 (grass): the fuzzer's
-- deepest overlap, 66 mm into the king, for the same reason as
-- baton-along-kubb-edge.lua. With the clipped stretch the deepest is 6.7 mm
-- for one step. It must topple the king, cleanly.
return {
	name = "baton along a box sinks in (1:5977)",
	surface = "grass",
	stakes = true,
	pieces = {
		{ id = "king", kind = "king", x = 0, y = 4, qw = 1, qx = 0, qy = 0, qz = 0 },
	},
	throws = {
		{ groundSeed = 1080298474, state = { kind = "baton", id = "baton", exact = true, 0, 0, 0.59999999999999998, 0.99900583986996438, 7.7573075557735264e-06, 0.044579161337374378, -0.00017383897133542594, 0.0020094326676475898, 5.7738345251323828, 3.0268360784320842, -9.0825955833246326, 0.0031609607432845116, 0.81221222274429605 } },
	},
	expect = { toppled = { "king" }, clean = true },
}
