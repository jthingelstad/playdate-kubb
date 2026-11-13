import "core/vec"
local vec = tw.vec

local function same(a, x, y, z, what)
	expect.near(a.x, x, 1e-12, (what or "") .. " x")
	expect.near(a.y, y, 1e-12, (what or "") .. " y")
	expect.near(a.z, z, 1e-12, (what or "") .. " z")
end

test("new defaults to zero", function()
	same(vec.new(), 0, 0, 0)
	same(vec.new(1, 2), 1, 2, 0)
end)

test("add and sub", function()
	local a, b = vec.new(1, 2, 3), vec.new(0.5, -4, 10)
	same(vec.add(a, b), 1.5, -2, 13)
	same(vec.sub(a, b), 0.5, 6, -7)
	same(a, 1, 2, 3, "arguments unchanged")
end)

test("scale", function()
	same(vec.scale(vec.new(1, -2, 0.25), 4), 4, -8, 1)
end)

test("dot", function()
	expect.eq(vec.dot(vec.new(1, 2, 3), vec.new(4, -5, 6)), 12)
	expect.eq(vec.dot(vec.new(1, 0, 0), vec.new(0, 1, 0)), 0)
end)

test("cross follows the right-hand rule (x across, y downfield, z up)", function()
	same(vec.cross(vec.new(1, 0, 0), vec.new(0, 1, 0)), 0, 0, 1)
	same(vec.cross(vec.new(0, 1, 0), vec.new(1, 0, 0)), 0, 0, -1)
	local a, b = vec.new(2, 3, 4), vec.new(5, 6, 7)
	local c = vec.cross(a, b)
	same(c, -3, 6, -3)
	expect.near(vec.dot(c, a), 0, 1e-12, "perpendicular to a")
	expect.near(vec.dot(c, b), 0, 1e-12, "perpendicular to b")
end)

test("length", function()
	expect.near(vec.length(vec.new(3, 4, 12)), 13)
	expect.eq(vec.length(vec.new()), 0)
end)
