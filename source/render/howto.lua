-- HOW TO THROW on screen (core/howto runs it): a title bar, a big dial that
-- is the crank (both notches, the wind-up, the last stop), a power bar, a
-- side view of the throw (the last one solid, the full-power aim at the notch
-- dashed, a kubb 8 m out), and the step's words with a line on the last throw.
-- Drawn whole each frame; the walkthrough waits on the player, not the
-- physics.
import "CoreLibs/graphics"
import "core/tw"
import "core/swing"
import "core/flight"
import "core/howto"
import "render/ui"

tw.render = tw.render or {}

local gfx <const> = playdate.graphics
local swing, flight, howto, ui = tw.swing, tw.flight, tw.howto, tw.render.ui
local floor, sin, cos, rad, max, min = math.floor, math.sin, math.cos, math.rad, math.max, math.min
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

local rhowto = {}

rhowto.tune = {
	dialX = 76, dialY = 96, dialR = 52,
	barX = 4, barY = 46, barW = 10, barH = 100,   -- the power bar, left of the dial, under POWER
	viewX = 176, groundY = 142, pxPerM = 23,   -- the side view: the hand's x, the ground, the scale
	textY = 158,
}

-- the point at radius r for a backswing of `deg` degrees (0 = straight down,
-- winding back turns it to the left and up; forward is negative), as hud's
local function onDial(cx, cy, r, deg)
	local a = rad(deg)
	return cx - r * sin(a), cy + r * cos(a)
end

local function notch(cx, cy, r, deg, inset, w)
	local x0, y0 = onDial(cx, cy, r - inset, deg)
	local x1, y1 = onDial(cx, cy, r - 2, deg)
	gfx.setLineWidth(w)
	gfx.drawLine(x0, y0, x1, y1)
end

local function dial(h)
	local t = rhowto.tune
	local cx, cy, r = t.dialX, t.dialY, t.dialR
	local full = swing.tune.fullBackswingDeg
	gfx.setColor(BLACK)
	gfx.fillCircleAtPoint(cx, cy, r)
	gfx.setColor(WHITE)
	-- the track, dotted
	local tr = r - 9
	for i = 0, 59 do
		local a = i * 6
		local x, y = onDial(cx, cy, tr, a)
		gfx.fillRect(floor(x), floor(y), 1, 1)
	end
	local sw = h.sw
	-- the wind-up so far: a thick white arc on the track
	if sw.phase ~= "idle" and sw.backswing > 1 then
		gfx.setLineWidth(6)
		gfx.drawArc(cx, cy, tr, 180, 180 + min(sw.backswing, 180))
	end
	-- the back notch (full power) and the front notch (the loft: stop here)
	notch(cx, cy, r, full, 11, 3)
	notch(cx, cy, r, -h.loft, 15, 3)
	-- the last throw's stop
	if h.last then
		local x, y = onDial(cx, cy, r - 7, -h.last.angle)
		gfx.fillCircleAtPoint(x, y, 4)
	end
	-- the arm: the crank as it is
	local a = h.arm or 0
	local kx, ky = onDial(cx, cy, r - 12, -a)
	gfx.setLineWidth(4)
	gfx.drawLine(cx, cy, kx, ky)
	gfx.fillCircleAtPoint(kx, ky, 6)
	gfx.fillCircleAtPoint(cx, cy, 4)
	gfx.setLineWidth(1)
	gfx.setColor(BLACK)
	gfx.drawCircleAtPoint(kx, ky, 6)
	-- the labels by the notches, outside the dial
	local f = ui.label()
	ui.text(f, "POWER", 2, t.barY - 16, false)
	local fx, fy = onDial(cx, cy, r + 6, -h.loft)
	ui.text(f, "STOP", floor(fx) + 3, min(t.textY - 16, floor(fy) - 6), false)
end

local function bar(h)
	local t = rhowto.tune
	local sw = h.sw
	local p = 0
	if sw.phase ~= "idle" then p = swing.powerCap(sw) elseif h.last then p = h.last.power end
	gfx.setColor(BLACK)
	gfx.setLineWidth(2)
	gfx.drawRect(t.barX, t.barY, t.barW, t.barH)
	local fill = floor((t.barH - 4) * max(0, min(1, p)) + 0.5)
	gfx.fillRect(t.barX + 2, t.barY + t.barH - 2 - fill, t.barW - 4, fill)
	gfx.setLineWidth(1)
end

-- one arc in the side view: from the hand, `loftDeg` and `speed`, to the
-- ground; solid or dashed
local function arc(loftDeg, speed, dashed)
	local t = rhowto.tune
	local ft = flight.tune
	local carry, T = howto.flight(loftDeg, speed)
	local e = rad(loftDeg)
	local vx, vz = speed * cos(e), speed * sin(e)
	local k = t.pxPerM
	local n = 24
	local px, py = t.viewX, t.groundY - ft.handHeight * k
	for i = 1, n do
		local tt = T * i / n
		local x = t.viewX + vx * tt * k
		local y = t.groundY - (ft.handHeight + vz * tt - 0.5 * ft.g * tt * tt) * k
		if x > 398 then break end
		if not dashed or i % 2 == 0 then gfx.drawLine(px, py, x, y) end
		px, py = x, y
	end
	return carry
end

local function side(h, docked)
	local t = rhowto.tune
	local k, gx, gy = t.pxPerM, t.viewX, t.groundY
	gfx.setColor(BLACK)
	gfx.setLineWidth(2)
	gfx.drawLine(gx - 12, gy, 398, gy)
	-- the thrower: a post with the hand at hand height
	local hy = gy - flight.tune.handHeight * k
	gfx.fillRect(gx - 7, hy - 6, 4, gy - hy + 6)
	gfx.fillCircleAtPoint(gx - 5, hy - 10, 4)
	-- the kubb 8 m out
	local kxp = gx + howto.tune.kubbAt * k
	gfx.fillRect(floor(kxp) - 2, gy - 7, 5, 7)
	local f = ui.label()
	ui.text(f, "8 M", floor(kxp), gy + 3, false, "center")
	-- the aim: a full-power throw at the notch, dashed
	gfx.setLineWidth(1)
	arc(h.loft, howto.aimSpeed(h.loft), true)
	-- the last throw, solid, with where it landed
	local l = h.last
	if l then
		gfx.setLineWidth(2)
		local carry = arc(l.launch, l.speed, false)
		local lx = gx + max(0, carry) * k
		if lx <= 396 then
			gfx.drawLine(lx - 3, gy - 3, lx + 3, gy + 3)
			gfx.drawLine(lx - 3, gy + 3, lx + 3, gy - 3)
		end
		gfx.setLineWidth(1)
	end
	if docked then
		local w = 150
		gfx.fillRect(gx + 30, 60, w, 20)
		ui.text(f, "UNDOCK THE CRANK", gx + 30 + w // 2, 64, true, "center")
	end
end

function rhowto.draw(h, docked)
	local t = rhowto.tune
	gfx.clear(WHITE)
	-- the bar on top
	gfx.setColor(BLACK)
	gfx.fillRect(0, 0, 400, 18)
	local f = ui.label()
	ui.text(f, "HOW TO THROW", 6, 3, true)
	ui.text(f, "B: LEAVE", 394, 3, true, "right")
	dial(h)
	bar(h)
	side(h, docked)
	-- the step's words
	local title, l1, l2, say = howto.lines(h)
	gfx.setColor(BLACK)
	ui.text(ui.display(16), title, 8, t.textY, false)
	ui.text(f, l1, 8, t.textY + 22, false)
	ui.text(f, l2, 8, t.textY + 36, false)
	if say then
		local w = f:getTextWidth(say) + 12
		gfx.fillRect(400 - w - 4, 218, w, 18)
		ui.text(f, say, 400 - 10, 221, true, "right")
	end
end

tw.render.howto = rhowto
