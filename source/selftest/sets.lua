-- Scenario "sets": every kubb set (render/world sets, the match options' SET
-- row) drawn up close: the king and four kubbs near the far baseline, three
-- standing (one raised the other way up, its paint at the foot) and one lying
-- with its head toward the camera, seen from about 2 m so the details show.
-- Frames 1 to 5: classic, USA, Sweden, Minnesota, Wisconsin; frame 6: USA
-- from the thrower's baseline, the 8 m view. The check: changing the set
-- changed the pixels, and classic again draws exactly what it did first.
import "core/tw"
import "core/camera"
import "core/quat"
import "render/world"

local gfx <const> = playdate.graphics
local camera, quat, render = tw.camera, tw.quat, tw.render.world

local items, n
local function layout()
	items, n = {}, 0
	local function add(id, kind, x, y, z, qw, qx, qy, qz)
		local it = render.item(id, kind)
		render.setPose(it, x, y, z or it.hz, qw or 1, qx or 0, qy or 0, qz or 0)
		n = n + 1
		items[n] = it
	end
	add("king", "king", 0.62, 7.75)
	add("k1", "kubb", -0.25, 7.6, nil, quat.fromAxisAngle(0, 0, 1, 0.3))
	add("k2", "kubb", 0.15, 7.9, nil, quat.fromAxisAngle(0, 0, 1, -0.2))
	-- raised the other way up: its head at the foot
	local fw, fx, fy, fz = quat.fromAxisAngle(1, 0, 0, math.pi)
	add("k3", "kubb", -0.6, 8.0, nil, fw, fx, fy, fz)
	-- lying, its head toward the camera and a little to the left
	local lw, lx, ly, lz = quat.fromAxisAngle(1, 0, 0, math.pi / 2)
	local tw_, tx, ty, tz = quat.fromAxisAngle(0, 0, 1, 0.5)
	lw, lx, ly, lz = quat.mul(tw_, tx, ty, tz, lw, lx, ly, lz)
	add("k4", "kubb", 0.05, 7.05, 0.035, lw, lx, ly, lz)
end

local function sum()
	-- a cheap fingerprint of the frame: black pixels on a few rows
	local img = gfx.getWorkingImage()
	local s = 0
	for y = 20, 230, 7 do
		for x = 0, 399, 3 do
			if img:sample(x, y) == gfx.kColorBlack then s = s + x * 3 + y end
		end
	end
	return s
end

local NAMES = { "classic", "usa", "sweden", "minnesota", "wisconsin" }

tw.selftest.scenarios.sets = {
	step = function(ctx)
		local f = ctx.frame
		if f == 1 then
			layout()
			ctx.cam = camera.new()
			ctx.sums = {}
			playdate.display.setRefreshRate(30)
		end
		local c = ctx.cam
		if f <= 5 then
			render.setSet(NAMES[f])
			camera.lookAt(c, 0.05, 5.75, 0.5, 0.05, 7.55, 0.14)
			c.f = 520
			gfx.clear(gfx.kColorWhite)
			render.draw(c, items, n, nil)
			ctx.sums[f] = sum()
			ctx:capture()
			return false
		elseif f == 6 then
			-- the thrower's view of the same pieces, USA
			render.setSet("usa")
			camera.lookAt(c, 0, -2.2, 1.6, 0, 7.4, 0.1)
			c.f = 880
			gfx.clear(gfx.kColorWhite)
			render.draw(c, items, n, nil)
			ctx:capture()
			return false
		end
		-- classic again: exactly the first frame
		render.setSet("classic")
		camera.lookAt(c, 0.05, 5.75, 0.5, 0.05, 7.55, 0.14)
		c.f = 520
		gfx.clear(gfx.kColorWhite)
		render.draw(c, items, n, nil)
		if sum() ~= ctx.sums[1] then error("classic drew differently the second time") end
		for i = 2, 5 do
			if ctx.sums[i] == ctx.sums[1] then error(NAMES[i] .. " looks the same as classic") end
		end
		return true
	end,
}
