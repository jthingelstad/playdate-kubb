-- A kubb that comes to rest on another kubb must fall asleep.
--
-- From lua5.4 tools/physfuzz.lua --repro 1:64 (grass, the leaning layout).
-- The baton knocks f2 flat onto f1, which lies beside it. On f1 it never
-- touched the ground, and the sleep test wanted a push from the ground, so it
-- stayed awake at 0.00 m/s for the full 12 s. Held up by a piece that is
-- asleep or on the ground, it sleeps and the throw ends at 1.35 s.
-- It must topple f2, cleanly (the rest check included).
-- The launch is 2 percent slower than the fuzz found it (2026-11-17): since
-- the bounce reaches the row, the captured throw tipped f2 into f1's edge,
-- threw it up and it landed standing; at 0.98 of the speed f2 comes to rest
-- on f1 again (at 1.32 s), which is what this case is for.
return {
	name = "kubb resting on a kubb sleeps (1:64)",
	surface = "grass",
	stakes = true,
	pieces = {
		{ id = "b1", kind = "kubb", x = -2.0000092263886309, y = 8.0000153523560122, z = 0.074995480883875837, qw = 0.99999999628646941, qx = -7.4080589344988903e-05, qy = -3.3236685860926627e-06, qz = 4.390992067044549e-05 },
		{ id = "b2", kind = "kubb", x = -1.0000092263886284, y = 8.0000153523560122, z = 0.074995480883875837, qw = 0.99999999628646941, qx = -7.4080589344988876e-05, qy = -3.3236685860929058e-06, qz = 4.3909920670445523e-05 },
		{ id = "b3", kind = "kubb", x = -9.2263886284559351e-06, y = 8.0000153523560122, z = 0.074995480883875837, qw = 0.99999999628646941, qx = -7.4080589344988808e-05, qy = -3.3236685860930447e-06, qz = 4.3909920670445598e-05 },
		{ id = "b4", kind = "kubb", x = 0.99999077361137179, y = 8.0000153523560122, z = 0.074995480883875837, qw = 0.99999999628646941, qx = -7.4080589344988876e-05, qy = -3.3236685860930341e-06, qz = 4.3909920670445429e-05 },
		{ id = "king", kind = "king", x = -8.6137143651953687e-06, y = 4.0000154452420738, z = 0.149996263281302, qw = 0.99999999804065554, qx = -3.3384359220814028e-05, qy = -3.852656604747184e-06, qz = 5.281411110271153e-05 },
		{ id = "f1", kind = "kubb", x = 1.3994253368692917, y = 6.7811634911863914, z = 0.034995778826169423, qw = 0.49990900716306952, qx = -0.49998167222770901, qy = 0.50001944830031453, qz = -0.50008985524110294, toppled = true },
		{ id = "f2", kind = "kubb", x = 1.3994142054210308, y = 6.6855687579217626, z = 0.074994906386693636, qw = 0.99999990080638701, qx = -8.2288134054581274e-05, qy = -3.2870120841231046e-06, qz = -0.00043772716915287785 },
		{ id = "x1", kind = "baton", x = -1.0039852265843792, y = 4.5463470290842523, z = 0.021998996533863877, qw = 0.46091295158720502, qx = -0.4609115184880046, qy = -0.53624397439594962, qz = 0.53624828494671084 },
	},
	throws = {
		{ groundSeed = 131450214, state = { kind = "baton", id = "baton", exact = true, 1.3994142054210308, 2.3203989001858591, 0.59999999999999998, 0.99652819806726622, 0.00025478995023785862, 0.083199593067495012, -0.00305176216174763, 0.038807465965749958, 6.3360723080357708, 2.6034247274123437, -10.459182624973961, 0.06406088093935762, 1.7587549889608847 } },
	},
	expect = { toppled = { "f2" }, clean = true },
}
