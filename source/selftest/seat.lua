-- Scenario "seat" (core 1.0, docs/notes/match.md "The seat"): kubbs standing plumb are
-- drawn in their seat, the pose the throw's world builds them at, so nothing steps at a
-- throw's first frame.
--   1, 2  grass: a new match's first throw, the aim view as the game shows it, then a
--         close look from the side at Team A's most leaning base kubb, square to its
--         lean (a dotted plumb line from each kubb's foot, drawn by this test only, so
--         the lean can be seen; the note gives the lean in px at its top)
--   3, 4  sand: the same
--   5     a raise by the crank (as "settle-crank"), the last frame before it stands
--   6, 7  the next throw's first frame, then a close look at the raised kubb in it
-- The check, at each throw: every standing kubb item is off plumb (seated: grass 2,
-- sand 3 degrees at most), and a world built from the scene's items (as throw.launch
-- builds it) has every body at its item's orientation, to 1e-4 (the device's floats).
import "core/tw"
import "core/match"
import "core/world"
import "core/camera"
import "scenes/throw"
import "scenes/settle"
import "render/world"
import "input"

local gfx <const> = playdate.graphics
local cmatch, phys, camera = tw.match, tw.world, tw.camera
local throw, settle, render = tw.scenes.throw, tw.scenes.settle, tw.render.world

local MISS = {}
local function topple(id) return { toppled = { id } } end
local function land(x, y, a) return { rest = { x = x, y = y, standing = false, angle = a }, moved = {} } end
local function newMatch(surface)
	return cmatch.new { start = { year = 2026, month = 11, day = 22, hour = 9, min = 0 }, surface = surface,
		teams = { A = { name = "Ash", players = { { name = "Ash" } } }, B = { name = "Birch", players = { { name = "Birch" } } } } }
end

-- The throw scene set up for m's next throw.
local function sceneFor(m)
	local setup = cmatch.setup(m)
	local s = throw.new(tw.input.scripted({}))
	throw.enter()
	throw.prepare(s, setup)
	return s, setup
end

-- Every standing kubb seated and a world built from the items where they are drawn.
-- Returns the number of seated kubbs and the largest lean (degrees), or errors.
local function check(s, maxDeg)
	local pieces = {}
	for i = 1, s.nitems do
		local it = s.items[i]
		pieces[i] = { id = it.id, kind = it.kind, x = it.x, y = it.y, z = it.z,
			qw = it.qw, qx = it.qx, qy = it.qy, qz = it.qz, toppled = it.toppled }
	end
	local w = phys.new { surface = s.surface, pieces = pieces }
	local n, worst = 0, 0
	for i = 1, s.nitems do
		local it = s.items[i]
		if it.kind == "kubb" and not it.toppled then
			local lean = math.deg(math.acos(math.min(1, 1 - 2 * (it.qx * it.qx + it.qy * it.qy))))
			if lean > maxDeg + 1e-3 then error(string.format("%s leans %.3f degrees, the seat is %g", it.id, lean, maxDeg)) end
			if lean < 1e-6 then error(it.id .. " is drawn plumb") end
			n = n + 1
			if lean > worst then worst = lean end
			local b = w.byId[it.id]
			local d = math.abs(b.qw - it.qw) + math.abs(b.qx - it.qx) + math.abs(b.qy - it.qy) + math.abs(b.qz - it.qz)
			if d > 1e-4 then error(string.format("%s drawn at %.5f %.5f %.5f %.5f, built at %.5f %.5f %.5f %.5f", it.id,
				it.qw, it.qx, it.qy, it.qz, b.qw, b.qx, b.qy, b.qz)) end
		end
	end
	return n, worst
end

-- A low look at kubb `it` from dist metres away, square to its lean (so the lean lies in
-- the picture), with a dotted plumb line up from each standing kubb's foot. Returns the
-- lean in px at the kubb's top in this view.
local function closeLook(s, it, dist, lens)
	-- the lean's direction on the ground (the long axis's horizontal part)
	local lx, ly = it.r13, it.r23
	local ln = math.sqrt(lx * lx + ly * ly)
	if ln < 1e-9 then lx, ly, ln = 1, 0, 1 end
	lx, ly = lx / ln, ly / ln
	-- the camera to the side of it: along the perpendicular, facing the kubb
	local c = camera.new()
	camera.lookAt(c, it.x - ly * dist, it.y + lx * dist, 0.15, it.x, it.y, 0.15)
	c.f, c.cy = lens, 130
	gfx.clear(gfx.kColorWhite)
	render.advantageY, render.kidY = nil, nil
	render.draw(c, s.items, s.nitems, nil)
	gfx.setColor(gfx.kColorBlack)
	local px = 0
	for i = 1, s.nitems do
		local o = s.items[i]
		if o.kind == "kubb" and not o.toppled then
			-- the foot's centre: the item's centre less its axis times the half height
			local fx, fy = o.x - o.r13 * o.hz, o.y - o.r23 * o.hz
			for k = 0, 34, 2 do
				local sx, sy = camera.project(c, fx, fy, k * 0.01)
				if sx then gfx.fillRect(math.floor(sx) - 1, math.floor(sy), 2, 2) end
			end
			if o == it then
				local tx, ty = camera.project(c, o.x + o.r13 * o.hz, o.y + o.r23 * o.hz, o.z + o.r33 * o.hz)
				local ux = camera.project(c, fx, fy, 2 * o.hz)
				if tx and ux then px = math.abs(tx - ux) end
			end
		end
	end
	return px
end

local function item(s, id)
	for i = 1, s.nitems do if s.items[i].id == id then return s.items[i] end end
end

local stage, s, m, g, st, rshot, notes = 1, nil, nil, nil, nil, false, {}

tw.selftest.scenarios.seat = {
	step = function(ctx)
		if stage == 1 or stage == 3 then
			local surface = stage == 1 and "Grass" or "Sand"
			m = newMatch(surface)
			s = sceneFor(m)
			throw.update(s)
			throw.draw(s)
			ctx:capture()
			local n, worst = check(s, stage == 1 and 2 or 3)
			notes[#notes + 1] = string.format("%s=%d<=%.2f", string.lower(surface), n, worst)
			-- the most leaning of Team A's base kubbs, from the side
			local best, bl = nil, -1
			for i = 1, s.nitems do
				local o = s.items[i]
				if o.kind == "kubb" and o.id:sub(1, 1) == "a" and not o.toppled then
					local l = o.r13 * o.r13 + o.r23 * o.r23
					if l > bl then best, bl = o, l end
				end
			end
			local px = closeLook(s, best, 0.9, 600)
			notes[#notes + 1] = string.format("%s=%.1fpx", best.id, px)
			ctx:capture()
			stage = stage + 2
			return false
		end
		if stage == 5 then
			-- B's raise of a1 as in "settle-crank", in a core/match on grass
			if not st then
				m = newMatch("Grass")
				g = m.game
				g:throwBaton(MISS); g:throwBaton(MISS)
				g:throwBaton(topple("a1")); g:throwBaton(topple("a2")); g:throwBaton(MISS); g:throwBaton(MISS)
				g:toss(land(0.6, 6.0, 0.4)); g:toss(land(2.7, 6.0, math.pi / 2)); g:toss(land(2.8, 5.5, 0))
				local sign = tw.swing.tune.forwardSign
				st = settle.new(g, function(side) return side == "A" and "ASH" or "BIRCH" end,
					tw.input.scripted { { n = 2 }, { crank = 10 * sign, n = 80 } })
			end
			settle.update(st)
			settle.draw(st)
			-- the last frame before the crank stands it (the next 10 degrees raise it)
			if not rshot and st.mode == "raise" and st.kubb == "a1" and st.tip >= 1 - 10 / settle.tune.crankPerRaise - 1e-9 then
				ctx:capture()
				rshot = true
			end
			if st.done or st.mode ~= "raise" or st.kubb ~= "a1" then
				-- a1 is up: match.setup settles the rest by the engine (match.settle)
				if not g.kubbs.a1.pose.standing then error("a1 not raised") end
				if not rshot then error("no frame before a1 stood") end
				stage = 6
			end
			if ctx.frame > 200 then error("not raised by frame 200") end
			return false
		end
		if stage == 6 then
			s = sceneFor(m)
			throw.update(s)
			throw.draw(s)
			ctx:capture()
			local n, worst = check(s, 2)
			notes[#notes + 1] = string.format("raised=%d<=%.2f", n, worst)
			local a1 = item(s, "a1")
			if not a1 or a1.toppled then error("a1 not standing in the next throw") end
			local px = closeLook(s, a1, 0.9, 600)
			notes[#notes + 1] = string.format("a1=%.1fpx", px)
			ctx:capture()
			ctx.note = table.concat(notes, " ")
			return true
		end
		return false
	end,
}
