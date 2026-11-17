-- A kubb lying on another must not keep waking.
--
-- From lua5.4 tools/physfuzz.lua --repro 1:1658 (grass, the leaning layout).
-- f2 falls onto f1, and the baton comes to rest against them. When one of
-- the pieces pressing on each other slept first, the push from the ground
-- that was warm started for their shared weight kicked the other, which
-- woke the sleeper: f1 woke 6 times and the baton 5, until 11.8 s. Pieces
-- pressing on each other now wait for each other and sleep in the same
-- step, and the throw ends at 1.31 s.
-- It must topple f2, cleanly (the rest check included).
return {
	name = "kubbs pressing on each other stay asleep (1:1658)",
	surface = "grass",
	stakes = true,
	pieces = {
		{ id = "b1", kind = "kubb", x = -2.0000092263886309, y = 8.0000153523560122, z = 0.074995480883875837, qw = 0.99999999628646941, qx = -7.4080589344988903e-05, qy = -3.3236685860926627e-06, qz = 4.390992067044549e-05 },
		{ id = "b2", kind = "kubb", x = -1.0000092263886284, y = 8.0000153523560122, z = 0.074995480883875837, qw = 0.99999999628646941, qx = -7.4080589344988876e-05, qy = -3.3236685860929058e-06, qz = 4.3909920670445523e-05 },
		{ id = "b3", kind = "kubb", x = -9.2263886284559351e-06, y = 8.0000153523560122, z = 0.074995480883875837, qw = 0.99999999628646941, qx = -7.4080589344988808e-05, qy = -3.3236685860930447e-06, qz = 4.3909920670445598e-05 },
		{ id = "b4", kind = "kubb", x = 0.99999077361137179, y = 8.0000153523560122, z = 0.074995480883875837, qw = 0.99999999628646941, qx = -7.4080589344988876e-05, qy = -3.3236685860930341e-06, qz = 4.3909920670445429e-05 },
		{ id = "b5", kind = "kubb", x = 1.9999907736113716, y = 8.0000153523560122, z = 0.074995480883875837, qw = 0.99999999628646941, qx = -7.4080589344988767e-05, qy = -3.3236685860929011e-06, qz = 4.3909920670445679e-05 },
		{ id = "king", kind = "king", x = -8.6137143651953687e-06, y = 4.0000154452420738, z = 0.149996263281302, qw = 0.99999999804065554, qx = -3.3384359220814028e-05, qy = -3.852656604747184e-06, qz = 5.281411110271153e-05 },
		{ id = "f1", kind = "kubb", x = 1.1860000174012242, y = 5.1595243958263142, z = 0.034995778826169423, qw = 0.49990900716306952, qx = -0.49998167222770901, qy = 0.50001944830031453, qz = -0.50008985524110294, toppled = true },
		{ id = "f2", kind = "kubb", x = 1.1859904375060482, y = 5.063406431989665, z = 0.07499452514043782, qw = 0.99999989946031209, qx = -8.7732730822815655e-05, qy = -3.2848523941079073e-06, qz = -0.00043974031384615662 },
	},
	throws = {
		{ groundSeed = 655841695, state = { kind = "baton", id = "baton", exact = true, 1.1859904375060482, 1.5025777468710078, 0.59999999999999998, 0.99986321859473193, -1.8426083311957393e-05, 0.01650143109426801, 0.0011164827378389057, -0.012430257000831321, 5.5659352602324805, 2.3037032417353562, -10.926634109706221, -0.024402164917028703, 0.36075869109055392 } },
	},
	expect = { toppled = { "f2" }, clean = true },
}
