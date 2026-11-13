import "core/quat"
import "core/body"
local quat, body = tw.quat, tw.body

local function close3(ax, ay, az, bx, by, bz, tol, what)
	expect.near(ax, bx, tol, what .. " x")
	expect.near(ay, by, tol, what .. " y")
	expect.near(az, bz, tol, what .. " z")
end

test("a quarter turn about z takes x to y", function()
	local w, x, y, z = quat.fromAxisAngle(0, 0, 1, math.pi / 2)
	local rx, ry, rz = quat.rotate(w, x, y, z, 1, 0, 0)
	close3(rx, ry, rz, 0, 1, 0, 1e-12, "rotated")
end)

test("matrix and quaternion round trip", function()
	local w, x, y, z = quat.normalize(0.3, -0.5, 0.7, 0.2)
	local r11, r12, r13, r21, r22, r23, r31, r32, r33 = quat.toMatrix(w, x, y, z)
	-- column 3 is the local z axis in the world
	local zx, zy, zz = quat.rotate(w, x, y, z, 0, 0, 1)
	close3(r13, r23, r33, zx, zy, zz, 1e-12, "column 3")
	local w2, x2, y2, z2 = quat.fromMatrix(r11, r12, r13, r21, r22, r23, r31, r32, r33)
	expect.near(quat.angleBetween(w, x, y, z, w2, x2, y2, z2), 0, 1e-9, "angle")
end)

test("integrating a constant spin turns by rate times time", function()
	local w, x, y, z = quat.identity()
	for _ = 1, 240 do w, x, y, z = quat.integrate(w, x, y, z, 0, 0, 2, 1 / 240) end
	local ew, ex, ey, ez = quat.fromAxisAngle(0, 0, 1, 2)
	expect.near(quat.angleBetween(w, x, y, z, ew, ex, ey, ez), 0, 1e-3, "angle after 1 s at 2 rad/s")
end)

test("box and capsule inertia", function()
	local k = body.new("kubb", "k")
	-- box: Ixx = m (b^2 + c^2) / 12 with b = 0.07, c = 0.15
	expect.near(k.Ix, 0.40 * (0.07 ^ 2 + 0.15 ^ 2) / 12, 1e-12, "kubb Ix")
	expect.near(k.Iz, 0.40 * (0.07 ^ 2 + 0.07 ^ 2) / 12, 1e-12, "kubb Iz")
	local b = body.new("baton", "b")
	expect.near(b.m, 0.25, 1e-12, "baton mass")
	-- a 0.30 m by 4.4 cm round stick: across about m (3 r^2 + L^2) / 12
	expect.near(b.Ix, 0.25 * (3 * 0.022 ^ 2 + 0.30 ^ 2) / 12, 1e-9, "baton Ix")
	expect.near(b.Iz, 0.25 * 0.022 ^ 2 / 2, 1e-9, "baton Iz")
end)
