-- A baton across a kubb's upright edge must not sink into it.
--
-- From lua5.4 tools/physfuzz.lua --repro 1:352 (grass, a baton at the base
-- line). The baton struck b2 across one of its upright edges, spinning at
-- 34 rad/s. collide.capsuleBox made one contact, at the edge; the baton
-- turned about it and went 10.9 mm into the kubb. With the stretch along
-- the edge clipped to the kubb and a contact at each end, the deepest is
-- 0.7 mm. It must topple b2, cleanly.
return {
	name = "baton across a kubb edge (1:352)",
	surface = "grass",
	stakes = true,
	pieces = {
		{ id = "b2", kind = "kubb", x = -1, y = 8, qw = 1, qx = 0, qy = 0, qz = 0 },
		{ id = "b3", kind = "kubb", x = 0, y = 8, qw = 1, qx = 0, qy = 0, qz = 0 },
		{ id = "b4", kind = "kubb", x = 1, y = 8, qw = 1, qx = 0, qy = 0, qz = 0 },
		{ id = "king", kind = "king", x = 0, y = 4, qw = 1, qx = 0, qy = 0, qz = 0 },
	},
	throws = {
		{ groundSeed = 1059733148, state = { kind = "baton", id = "baton", exact = true, -1, 1.03812620280136, 0.59999999999999998, 0.99751961206372886, -0.0001119186850707405, -0.070371117382589887, -0.0015864617113791658, 0.023188518321865772, 7.2901044908479919, 4.4919679510157051, -5.9282999492237032, 0.018856861676354284, -0.84062468315525174 } },
	},
	expect = { toppled = { "b2" }, clean = true },
}
