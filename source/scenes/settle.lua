-- Raising kubbs and placing punishment kubbs by hand (Rules V4.0 II.D; the
-- boards Raising.png and Punish.png, which are sketches: the calls here are
-- this module's). The defending team does both, between the attacker's kubb
-- tosses and its batons; the rail names that team, so it is clear who holds
-- the Playdate.
--
-- Raise: a 3D close-up of the lying kubb (render/world, in the defender's
-- view frame, from behind and above), the kubbs and king nearby, and on the
-- ground the 7 x 7 footprint of each end the engine allows; the chosen one
-- is dotted with STANDS HERE under it (MOVED CLEAR when II.D.5 slid it).
-- Left and right choose an end, A raises. Or the crank (Jamie's idea):
-- forward tips the kubb up onto its right-hand end on screen, backward onto
-- its left, slowly (crankPerRaise degrees from lying to standing,
-- raising.tipPose), and all the way up raises it; an end the engine does not
-- allow will not tip, and says why. The highlight starts on the engine's own
-- choice (its raise policy).
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
import "core/camera"
import "core/quat"
import "core/swing"
import "render/ui"
import "render/world"

local gfx <const> = playdate.graphics
local pitch, frame, raising, ui = tw.pitch, tw.frame, tw.raising, tw.render.ui
local camera, quat, render, swing = tw.camera, tw.quat, tw.render.world, tw.swing
local floor, cos, sin, min, max = math.floor, math.cos, math.sin, math.min, math.max
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

tw.scenes = tw.scenes or {}
local settle = {}

settle.tune = {
	raiseBack = 0.95,     -- m the raise camera stands behind the kubb (toward the baseline),
	raiseUp = 0.62,       -- above the ground,
	raiseSide = 0.25,     -- and to the right
	raiseLens = 760,      -- px focal length
	raiseCY = 104,        -- screen y the kubb's centre is put at
	raiseNear = 1.6,      -- m: other pieces this near are drawn
	crankPerRaise = 270,  -- degrees of crank from lying to standing
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

local set3D   -- (the raising section below)

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
		s.blocked = nil
		set3D(s)
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

local LONG <const>, SIDE <const> = pitch.kubbLong, pitch.kubbSide

-- An engine pose (world frame) on a render item, in the defender's view frame.
local function placeItem(it, side, p)
	local x, y = frame.point(side, p.x, p.y)
	local a = frame.angle(side, p.angle)
	if p.standing then
		render.setPose(it, x, y, it.hz, quat.fromAxisAngle(0, 0, 1, a))
	else
		render.setPose(it, x, y, SIDE / 2, quat.fromAxisAngle(-sin(a), cos(a), 0, math.pi / 2))
	end
end

-- The index of the engine's choice for end `which`, or nil.
local function choiceFor(s, which)
	for i, c in ipairs(s.dec.choices) do
		if c.which == which then return i end
	end
	return nil
end

-- Why end `which` cannot be raised on.
local function endWhy(s, which)
	local e = s.dec.ends and s.dec.ends[which]
	if e and not e.inBounds then return "THAT END IS OUT" end
	return "THAT END IS BLOCKED"
end

-- The crank's tip: > 0 toward the right-hand end, < 0 the left, 1 standing.
local function tipTo(s, tip)
	s.tip = tip
	local which = (tip >= 0) and s.rightEnd or (3 - s.rightEnd)
	local t = tip >= 0 and tip or -tip
	render.setPose(s.it, raising.tipPose(s.vpose, which, t))
	s.img = nil
end

-- The 3D close-up: the pieces near the kubb, the camera behind and above it,
-- which end shows on the right.
set3D = function(s)
	local t = settle.tune
	local side = s.side
	s.vpose = frame.pose(side, s.pose)
	local vx, vy = s.vpose.x, s.vpose.y
	local items, n = {}, 0
	local near2 = t.raiseNear * t.raiseNear
	local function add(id, kind, p)
		local px, py = frame.point(side, p.x, p.y)
		if (px - vx) * (px - vx) + (py - vy) * (py - vy) > near2 then return end
		local it = render.item(id, kind)
		placeItem(it, side, p)
		n = n + 1
		items[n] = it
	end
	for _, o in ipairs(s.ctx.others) do add(o.id, "kubb", o.pose) end
	if s.ctx.king then add("king", "king", s.ctx.king) end
	s.it = render.item(s.kubb, "kubb")
	n = n + 1
	items[n] = s.it
	s.items, s.nitems = items, n
	local c = s.cam or camera.new()
	s.cam = c
	camera.lookAt(c, vx + t.raiseSide, vy - t.raiseBack, t.raiseUp, vx, vy, SIDE / 2)
	c.f, c.cy = t.raiseLens, t.raiseCY
	local a = s.vpose.angle
	local e1 = camera.project(c, vx + cos(a) * LONG / 2, vy + sin(a) * LONG / 2, SIDE / 2) or 0
	local e2 = camera.project(c, vx - cos(a) * LONG / 2, vy - sin(a) * LONG / 2, SIDE / 2) or 0
	s.rightEnd = (e1 >= e2) and 1 or 2
	tipTo(s, 0)
end

local function raiseView(s)
	local side = s.side
	local c = s.cam
	render.advantageY = nil
	render.draw(c, s.items, s.nitems, nil)
	-- the footprints on the ground: every choice, the chosen one dotted
	local f = ui.label()
	local hk = SIDE / 2
	for i, ch in ipairs(s.dec.choices) do
		local p = frame.pose(side, ch.pose)
		local ca, sa = cos(p.angle), sin(p.angle)
		local pts, ok = {}, true
		for k, sgn in ipairs { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } } do
			local x = p.x + (ca * sgn[1] - sa * sgn[2]) * hk
			local y = p.y + (sa * sgn[1] + ca * sgn[2]) * hk
			local sx, sy = camera.project(c, x, y, 0)
			if not sx then ok = false break end
			pts[2 * k - 1], pts[2 * k] = sx, sy
		end
		if ok then
			gfx.setColor(BLACK)
			if i == s.choice then
				gfx.setLineWidth(2)
				dashedPoly(3, 3, table.unpack(pts))
				gfx.setLineWidth(1)
				-- the label under the kubb's group, pointing up at this end
				local cx, cy = camera.project(c, p.x, p.y, 0)
				local ly = max(pts[2], pts[4], pts[6], pts[8], cy) + 34
				local label = ch.displaced and "MOVED CLEAR" or "STANDS HERE"
				local w = f:getTextWidth(label)
				local lx = max(6 + w // 2, min(394 - w // 2, floor(cx)))
				gfx.fillTriangle(cx, ly - 8, cx - 5, ly - 1, cx + 5, ly - 1)
				gfx.setColor(WHITE)
				gfx.fillRect(lx - w // 2 - 3, ly, w + 6, 15)
				ui.text(f, label, lx, ly + 2, false, "center")
			else
				dashedPoly(5, 4, table.unpack(pts))
			end
		end
	end
	local done = s.raised
	rail(s.name(side), "RAISE " .. (done + 1) .. " OF " .. max(s.raiseTotal, done + 1), nil)
	local x = 6
	if #s.dec.choices > 1 then x = x + hint("lr", "CHOOSE END", x, 212) + 8 end
	x = x + buttonPlaque("A", "RAISE", x, 212) + 8
	ui.text(f, "OR CRANK IT UP", 394, 216, false, "right")
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
			s.blocked = nil
			tipTo(s, 0)
		end
		-- the crank tips it: forward toward the right-hand end, back the left
		local d = p:crank() * swing.tune.forwardSign
		local up = false
		if d ~= 0 then
			local tip = s.tip + d / settle.tune.crankPerRaise
			local which = (tip > 0) and s.rightEnd or ((tip < 0) and (3 - s.rightEnd) or nil)
			local ci = which and choiceFor(s, which)
			if which and not ci then
				tip = 0
				s.blocked = endWhy(s, which)
			else
				s.blocked = nil
				if ci then s.choice = ci end
			end
			if tip >= 1 then tip, up = 1, true elseif tip <= -1 then tip, up = -1, true end
			if tip ~= s.tip then tipTo(s, tip) else s.img = nil end
		end
		if up or p:pressed("a") then
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
	elseif s.mode == "raise" and s.blocked then
		whyFlag(s.blocked)
	end
end

tw.scenes.settle = settle
