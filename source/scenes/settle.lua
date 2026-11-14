-- Raising kubbs and placing punishment kubbs by hand (Rules V4.0 II.D; the
-- boards Raising.png and Punish.png, which are sketches: the calls here are
-- this module's). The defending team does both, between the attacker's kubb
-- tosses and its batons; the rail names that team, so it is clear who holds
-- the Playdate.
--
-- Raise: a top-down close-up of the lying kubb in the defender's view frame
-- (their own baseline at the bottom). Each end the engine allows is drawn as
-- the 7 x 7 footprint the kubb would stand on; the chosen one is dotted with
-- STANDS HERE under it. Left and right choose an end (when there are two), A
-- raises. A footprint moved clear of an obstruction (II.D.5) says MOVED CLEAR.
-- The highlight starts on the engine's own choice (its raise policy).
--
-- Punish: the defender's half seen from above (5 x 4 m at 40 px a metre), the
-- grey keep-out circles (a baton length from each stake and from the king),
-- the kubbs standing in it, and a cursor kubb. The d-pad moves it (faster the
-- longer it is held), A places it. The engine checks the spot
-- (raising.punishmentCheck): a refused spot shows why in a flag and the
-- cursor stays. It starts at the engine's own suggestion.
--
-- Everything that does not move is drawn once into an image when it changes
-- (no text call in a normal frame); per frame the punish view adds only the
-- cursor.
import "CoreLibs/graphics"
import "core/tw"
import "core/pitch"
import "core/frame"
import "core/raising"
import "render/ui"

local gfx <const> = playdate.graphics
local pitch, frame, raising, ui = tw.pitch, tw.frame, tw.raising, tw.render.ui
local floor, cos, sin, min, max = math.floor, math.cos, math.sin, math.min, math.max
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

tw.scenes = tw.scenes or {}
local settle = {}

settle.tune = {
	raiseScale = 360,     -- px per metre in the raising close-up
	raiseCY = 108,        -- screen y of the lying kubb's centre
	punishScale = 40,     -- px per metre in the placement view
	punishLeft = 100,     -- screen x of the half's left sideline
	punishTop = 30,       -- screen y of the middle line (the half's far edge)
	cursorSpeed = 0.6,    -- m/s when a d-pad direction is first held
	cursorAccel = 2.0,    -- m/s faster per second held
	cursorMax = 2.5,      -- m/s at most
	cursorPx = 9,         -- the cursor kubb's square on screen (true size is 3 px)
	kubbPx = 6,           -- other kubbs in the placement view
	keepOut = { 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA },  -- 50% checker
	rough = { 0xFF, 0x9F, 0xFF, 0xFF, 0xFF, 0xF9, 0xFF, 0xFF },     -- as the pitch's rough
}

-- the engine's refusals, as labels (12 characters or so)
local WHY = {
	["not in the half"] = "NOT IN THE HALF",
	["closer than a baton length to the king"] = "TOO NEAR THE KING",
	["closer than a baton length to a stake"] = "TOO NEAR A STAKE",
}
local function whyLabel(why)
	if not why then return nil end
	if WHY[why] then return WHY[why] end
	if why:find("^overlaps") then return "ON A KUBB" end
	return string.upper(why)
end

-- ---------- drawing helpers ----------

local function plaque(x, y, w, h)
	gfx.setColor(BLACK)
	gfx.fillRect(x + 2, y + 2, w, h)
	gfx.setColor(WHITE)
	gfx.fillRect(x, y, w, h)
	gfx.setColor(BLACK)
	gfx.setLineWidth(2)
	gfx.drawRect(x, y, w, h)
	gfx.setLineWidth(1)
end

-- the rail: the team on the left, a title in the middle, a count on the right
local function rail(name, title, right)
	local f = ui.label()
	gfx.setColor(BLACK)
	gfx.fillRect(0, 0, 400, 14)
	gfx.setColor(WHITE)
	gfx.fillPolygon(4, 2, 12, 2, 9, 5, 12, 8, 6, 8, 6, 12, 4, 12)   -- the pennant
	local ty = 2
	ui.text(f, name, 17, ty, true)
	if title then ui.text(f, title, 200, ty, true, "center") end
	if right then ui.text(f, right, 395, ty, true, "right") end
end

-- a d-pad glyph (a plus) or left/right arrows, then a word, in a plaque
local function hint(kind, word, x, y)
	local f = ui.label()
	local w = 24 + f:getTextWidth(word) + 10
	plaque(x, y, w, 20)
	gfx.setColor(BLACK)
	local cx, cy = x + 12, y + 10
	if kind == "plus" then
		gfx.fillRect(cx - 6, cy - 2, 13, 5)
		gfx.fillRect(cx - 2, cy - 6, 5, 13)
	elseif kind == "lr" then
		gfx.fillTriangle(cx - 8, cy, cx - 2, cy - 5, cx - 2, cy + 5)
		gfx.fillTriangle(cx + 8, cy, cx + 2, cy - 5, cx + 2, cy + 5)
	elseif kind == "grey" then
		gfx.setPattern(settle.tune.keepOut)
		gfx.fillRect(cx - 6, cy - 6, 12, 12)
		gfx.setColor(BLACK)
		gfx.drawRect(cx - 6, cy - 6, 12, 12)
	end
	ui.text(f, word, x + 24, y + 4)
	return w
end

local function buttonPlaque(letter, word, x, y)
	local w = ui.buttonWidth(word) + 12
	plaque(x, y, w, 20)
	ui.button(letter, word, x + 6, y + 3)
	return w
end

-- a 4-point polygon from a centre, an angle and half sizes, through a
-- world-to-screen function
local function box(toScreen, x, y, a, hl, hs)
	local cx, cy, sx, sy = cos(a) * hl, sin(a) * hl, -sin(a) * hs, cos(a) * hs
	local x1, y1 = toScreen(x + cx + sx, y + cy + sy)
	local x2, y2 = toScreen(x - cx + sx, y - cy + sy)
	local x3, y3 = toScreen(x - cx - sx, y - cy - sy)
	local x4, y4 = toScreen(x + cx - sx, y + cy - sy)
	return x1, y1, x2, y2, x3, y3, x4, y4
end

-- a dashed or dotted outline of a polygon (on, off in px)
local function dashedPoly(on, off, ...)
	local p = { ... }
	local n = #p // 2
	for i = 1, n do
		local x1, y1 = p[2 * i - 1], p[2 * i]
		local j = i % n + 1
		local x2, y2 = p[2 * j - 1], p[2 * j]
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		local t = 0
		while t < len do
			local t2 = min(len, t + on)
			gfx.drawLine(x1 + dx * t / len, y1 + dy * t / len, x1 + dx * t2 / len, y1 + dy * t2 / len)
			t = t2 + off
		end
	end
end

-- ---------- state ----------

-- The next thing to do, from the engine: a raise, a punishment kubb, or done.
local function begin(s)
	local g = s.g
	local n = g:need()
	s.img = nil
	if n.kind == "raise" then
		s.mode, s.side, s.kubb = "raise", n.side, n.kubb
		s.pose, s.dec = n.pose, n.decision
		s.ctx = g:context(n.side, n.kubb)
		s.choice = raising.choose(s.dec, s.ctx, g.raisePolicy) or 1
		if not s.raiseTotal then
			s.raiseTotal = 0
			for _, k in ipairs(g:fieldKubbs(n.side)) do
				if not k.pose.standing then s.raiseTotal = s.raiseTotal + 1 end
			end
		end
	elseif n.kind == "punish" then
		s.mode, s.side, s.kubb = "punish", n.side, n.kubb
		s.ctx = g:context(n.side, n.kubb)
		if not s.punishTotal then s.punishTotal = #g.punishQueue end
		local p = raising.autoPunishment(s.ctx)
		local vx, vy = 0, 2
		if p then vx, vy = frame.point(n.side, p.x, p.y) end
		s.cx, s.cy, s.held = vx, vy, 0
		s.why = nil
		s.check = true
	else
		s.mode, s.done = nil, true
	end
end

-- game: the core/rules game; name(side) the team's name for the rail;
-- provider an input provider.
function settle.new(game, name, provider)
	local s = { g = game, name = name, input = provider, done = false, raised = 0, placed = 0 }
	begin(s)
	return s
end

-- ---------- raising ----------

local function raiseView(s)
	local t = settle.tune
	local S = t.raiseScale
	local side = s.side
	local ox, oy = frame.point(side, s.pose.x, s.pose.y)
	local function toScreen(x, y)       -- view frame metres to screen
		return 200 + (x - ox) * S, t.raiseCY - (y - oy) * S
	end
	gfx.clear(WHITE)
	gfx.setColor(BLACK)
	-- the lines in view: the middle line (dashed), the sidelines, the baseline
	local _, my = toScreen(0, 4)
	if my > 14 and my < 240 then
		gfx.setLineWidth(3)
		local x = 0
		while x < 400 do gfx.drawLine(x, my, x + 12, my); x = x + 20 end
	end
	gfx.setLineWidth(2)
	for _, sx in ipairs { -2.5, 2.5 } do
		local lx = toScreen(sx, 0)
		if lx > 0 and lx < 400 then gfx.drawLine(lx, 14, lx, 240) end
	end
	local _, by = toScreen(0, 0)
	if by > 14 and by < 240 then gfx.drawLine(0, by, 400, by) end
	-- the other kubbs and the king nearby
	local hk = pitch.kubbSide / 2
	for _, o in ipairs(s.ctx.others) do
		local p = o.pose
		local a = frame.angle(side, p.angle)
		local hl = p.standing and hk or pitch.kubbLong / 2
		local vx, vy = frame.point(side, p.x, p.y)
		local x1, y1, x2, y2, x3, y3, x4, y4 = box(toScreen, vx, vy, a, hl, hk)
		if x1 > -60 and x1 < 460 and y1 > -60 and y1 < 300 then
			gfx.fillPolygon(x1 + 3, y1 + 3, x2 + 3, y2 + 3, x3 + 3, y3 + 3, x4 + 3, y4 + 3)
			gfx.setColor(WHITE)
			gfx.fillPolygon(x1, y1, x2, y2, x3, y3, x4, y4)
			gfx.setColor(BLACK)
			gfx.setLineWidth(2)
			gfx.drawPolygon(x1, y1, x2, y2, x3, y3, x4, y4)
		end
	end
	local kp = s.ctx.king
	if kp then
		local vx, vy = frame.point(side, kp.x, kp.y)
		local h = pitch.kingSide / 2
		local x1, y1, x2, y2, x3, y3, x4, y4 = box(toScreen, vx, vy, frame.angle(side, kp.angle), h, h)
		if x1 > -60 and x1 < 460 and y1 > -60 and y1 < 300 then
			gfx.fillPolygon(x1 + 3, y1 + 3, x2 + 3, y2 + 3, x3 + 3, y3 + 3, x4 + 3, y4 + 3)
			gfx.setColor(WHITE)
			gfx.fillPolygon(x1, y1, x2, y2, x3, y3, x4, y4)
			gfx.setColor(BLACK)
			gfx.drawPolygon(x1, y1, x2, y2, x3, y3, x4, y4)
			local cx, cy = toScreen(vx, vy)
			gfx.fillCircleAtPoint(cx, cy, 4)
		end
	end
	-- the lying kubb: a hard shadow right and down, white, a 2 px outline
	local a = frame.angle(side, s.pose.angle)
	local x1, y1, x2, y2, x3, y3, x4, y4 = box(toScreen, ox, oy, a, pitch.kubbLong / 2, hk)
	gfx.fillPolygon(x1 + 6, y1 + 5, x2 + 6, y2 + 5, x3 + 6, y3 + 5, x4 + 6, y4 + 5)
	gfx.setColor(WHITE)
	gfx.fillPolygon(x1, y1, x2, y2, x3, y3, x4, y4)
	gfx.setColor(BLACK)
	gfx.setLineWidth(2)
	gfx.drawPolygon(x1, y1, x2, y2, x3, y3, x4, y4)
	-- grain along it
	gfx.setLineWidth(1)
	local gx, gy = cos(a) * pitch.kubbLong * 0.3, sin(a) * pitch.kubbLong * 0.3
	local ax1, ay1 = toScreen(ox - gx, oy - gy)
	local ax2, ay2 = toScreen(ox + gx, oy + gy)
	gfx.drawLine(ax1, ay1, ax2, ay2)
	-- the ends: every choice as its footprint, the chosen one dotted; the
	-- label goes under the whole group, pointing up at the chosen end
	local f = ui.label()
	local dec = s.dec
	local bottom = max(y1, y2, y3, y4) + 5
	local labelX, label
	for i, c in ipairs(dec.choices) do
		local p = c.pose
		local vx, vy = frame.point(side, p.x, p.y)
		local q1, r1, q2, r2, q3, r3, q4, r4 = box(toScreen, vx, vy, frame.angle(side, p.angle), hk, hk)
		bottom = max(bottom, r1, r2, r3, r4)
		gfx.setColor(BLACK)
		if i == s.choice then
			gfx.setLineWidth(3)
			dashedPoly(3, 3, q1, r1, q2, r2, q3, r3, q4, r4)
			labelX = toScreen(vx, vy)
			label = c.displaced and "MOVED CLEAR" or "STANDS HERE"
		else
			gfx.setLineWidth(1)
			dashedPoly(6, 4, q1, r1, q2, r2, q3, r3, q4, r4)
		end
	end
	gfx.setLineWidth(1)
	if label then
		local ly = floor(bottom) + 12
		local w = f:getTextWidth(label)
		local lx = max(6 + w // 2, min(394 - w // 2, floor(labelX)))
		gfx.setColor(BLACK)
		gfx.fillTriangle(labelX, ly - 8, labelX - 5, ly - 1, labelX + 5, ly - 1)
		gfx.setColor(WHITE)
		gfx.fillRect(lx - w // 2 - 3, ly, w + 6, 15)
		ui.text(f, label, lx, ly + 2, false, "center")
	end
	-- the rail and the buttons
	local done = s.raised
	rail(s.name(side), "RAISE " .. (done + 1) .. " OF " .. max(s.raiseTotal, done + 1), nil)
	local x = 6
	if #dec.choices > 1 then x = x + hint("lr", "CHOOSE END", x, 212) + 8 end
	buttonPlaque("A", "RAISE", x, 212)
	if #dec.choices == 1 and dec.mode ~= "standing" then
		local note = (dec.mode == "displaced") and "THE OTHER END IS OUT" or "ONE END IS CLEAR"
		ui.text(f, note, 394, 216, false, "right")
	end
end

-- ---------- punishment ----------

local function toHalf(x, y)
	local t = settle.tune
	return t.punishLeft + (x + 2.5) * t.punishScale, t.punishTop + (4 - y) * t.punishScale
end

local function punishView(s)
	local t = settle.tune
	local S = t.punishScale
	local side = s.side
	gfx.setPattern(t.rough)
	gfx.fillRect(0, 14, 400, 226)
	local x0, y0 = toHalf(-2.5, 4)
	local x1, y1 = toHalf(2.5, 0)
	gfx.setColor(WHITE)
	gfx.fillRect(x0, y0, x1 - x0, y1 - y0)
	gfx.setColor(BLACK)
	gfx.setLineWidth(2)
	gfx.drawLine(x0, y0, x0, y1)
	gfx.drawLine(x1, y0, x1, y1)
	gfx.drawLine(x0, y1, x1, y1)
	gfx.setLineWidth(3)
	local x = x0
	while x < x1 do gfx.drawLine(x, y0, min(x + 10, x1), y0); x = x + 16 end
	gfx.setLineWidth(1)
	-- keep-out circles: a baton length from each stake (to the kubb's
	-- edge) and from the king
	local hk = pitch.kubbSide / 2
	local rs = floor((pitch.batonLength + hk) * S + 0.5)
	for _, st in ipairs(pitch.stakes) do
		local vx, vy = frame.point(side, st.x, st.y)
		if vy >= -0.01 and vy <= 4.01 then
			local cx, cy = toHalf(vx, vy)
			gfx.setPattern(t.keepOut)
			gfx.fillCircleAtPoint(cx, cy, rs)
			gfx.setColor(BLACK)
			gfx.drawCircleAtPoint(cx, cy, rs)
			gfx.fillRect(cx - 2, cy - 2, 4, 4)
		end
	end
	local kp = s.ctx.king
	if kp then
		local vx, vy = frame.point(side, kp.x, kp.y)
		local cx, cy = toHalf(vx, vy)
		local rk = floor((pitch.batonLength + pitch.kingSide / 2 + hk) * S + 0.5)
		gfx.setPattern(t.keepOut)
		gfx.fillCircleAtPoint(cx, cy, rk)
		gfx.setColor(BLACK)
		gfx.drawCircleAtPoint(cx, cy, rk)
		gfx.setColor(WHITE)
		gfx.fillRect(cx - 4, cy - 4, 9, 9)
		gfx.setColor(BLACK)
		gfx.drawRect(cx - 4, cy - 4, 9, 9)
		gfx.fillPolygon(cx - 4, cy - 4, cx - 4, cy - 7, cx - 2, cy - 5, cx, cy - 8, cx + 2, cy - 5,
			cx + 4, cy - 7, cx + 4, cy - 4)
	end
	-- the kubbs on the pitch, as small squares
	local k = t.kubbPx
	for _, o in ipairs(s.ctx.others) do
		local vx, vy = frame.point(side, o.pose.x, o.pose.y)
		if vy >= -0.2 and vy <= 4.2 then
			local cx, cy = toHalf(vx, vy)
			gfx.setColor(WHITE)
			gfx.fillRect(cx - k // 2, cy - k // 2, k, k)
			gfx.setColor(BLACK)
			gfx.drawRect(cx - k // 2, cy - k // 2, k, k)
		end
	end
	rail(s.name(side), "PLACE THE PUNISHMENT KUBB", (s.placed + 1) .. " OF " .. max(s.punishTotal, s.placed + 1))
	local bx = 6
	bx = bx + hint("plus", "MOVE", bx, 212) + 8
	buttonPlaque("A", "PLACE", bx, 212)
	local f = ui.label()
	local w = 24 + f:getTextWidth("KEEP OUT") + 10
	hint("grey", "KEEP OUT", 394 - w, 212)
end

-- the refusal flag, one small image per reason
local whyImg, whyKey = nil, nil
local function whyFlag(label)
	if whyKey ~= label then
		whyKey = label
		local f = ui.label()
		local w = f:getTextWidth(label) + 14
		whyImg = gfx.image.new(w + 2, 17, gfx.kColorClear)
		gfx.pushContext(whyImg)
		gfx.setColor(BLACK)
		gfx.fillRect(0, 0, w, 15)
		ui.text(f, label, w // 2, 2, true, "center")
		gfx.popContext()
	end
	local w = whyImg:getSize()
	whyImg:draw(200 - w // 2, 192)
end

-- ---------- update and draw ----------

function settle.update(s)
	local p = s.input
	p:advance()
	if s.done then return end
	if s.mode == "raise" then
		local n = #s.dec.choices
		if n > 1 and (p:pressed("left") or p:pressed("right")) then
			s.choice = s.choice % n + 1
			s.img = nil
		end
		if p:pressed("a") then
			s.g:raise(s.choice)
			s.raised = s.raised + 1
			begin(s)
		end
	elseif s.mode == "punish" then
		local t = settle.tune
		local dt = p:dt()
		local dx = (p:held("right") and 1 or 0) - (p:held("left") and 1 or 0)
		local dy = (p:held("up") and 1 or 0) - (p:held("down") and 1 or 0)
		if dx ~= 0 or dy ~= 0 then
			s.held = s.held + dt
			local v = min(t.cursorMax, t.cursorSpeed + t.cursorAccel * s.held) * dt
			local hk = pitch.kubbSide / 2
			s.cx = max(-2.5 + hk, min(2.5 - hk, s.cx + dx * v))
			s.cy = max(hk, min(4 - hk, s.cy + dy * v))
			s.check = true
		else
			s.held = 0
		end
		if s.check then
			-- the engine's own test, live, so the cursor says before A is pressed
			s.check = false
			local wx, wy = frame.point(s.side, s.cx, s.cy)
			local ok, why = raising.punishmentCheck({ x = wx, y = wy, standing = true, angle = 0 }, s.ctx)
			s.why = (not ok) and whyLabel(why) or nil
		end
		if p:pressed("a") then
			local wx, wy = frame.point(s.side, s.cx, s.cy)
			local ok, why = s.g:placePunishment({ x = wx, y = wy, standing = true, angle = 0 })
			if ok then
				s.placed = s.placed + 1
				begin(s)
			else
				s.why = whyLabel(why)
			end
		end
	end
end

function settle.draw(s)
	if s.done then return end
	if not s.img then
		s.img = gfx.image.new(400, 240, WHITE)
		gfx.pushContext(s.img)
		if s.mode == "raise" then raiseView(s) else punishView(s) end
		gfx.popContext()
	end
	s.img:draw(0, 0)
	if s.mode == "punish" then
		local t = settle.tune
		local cx, cy = toHalf(s.cx, s.cy)
		cx, cy = floor(cx + 0.5), floor(cy + 0.5)
		local k = t.cursorPx
		gfx.setColor(BLACK)
		local x = cx - 30
		while x < cx + 30 do gfx.drawPixel(x, cy); x = x + 3 end
		local y = cy - 30
		while y < cy + 30 do gfx.drawPixel(cx, y); y = y + 3 end
		gfx.fillRect(cx - k // 2 + 3, cy - k // 2 + 2, k, k)        -- its shadow
		gfx.setColor(s.why and BLACK or WHITE)
		gfx.fillRect(cx - k // 2, cy - k // 2, k, k)
		gfx.setColor(BLACK)
		gfx.setLineWidth(2)
		gfx.drawRect(cx - k // 2, cy - k // 2, k, k)
		gfx.setLineWidth(1)
		if s.why then whyFlag(s.why) end
	end
end

tw.scenes.settle = settle
