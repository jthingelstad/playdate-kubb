-- Raising kubbs and placing punishment kubbs by hand (Rules V4.0 II.D; the
-- boards Raising.png and Punish.png, which are sketches: the calls here are
-- this module's). The defending team does both, between the attacker's kubb
-- tosses and its batons; the rail names that team, so it is clear who holds
-- the Playdate. (While REST OF GAME raises for it in PASS + PLAY the
-- attacker still holds it, with no pass card; the rail goes on naming the
-- team whose kubbs are raised: scenes/match, scene.holder.)
--
-- Raise (in any order since 1.1.0, engine 1.4 "Raising in any order"): the whole
-- group the other team threw in, on one view held for the whole raise
-- (core/camera.fromEnd, kind "raise": over the group from the viewer's side, every
-- lying kubb and each of its ends in it), and on the ground the 7 x 7
-- footprint of each end the engine allows for the chosen kubb; the chosen end is
-- dotted with STANDS HERE under it (MOVED CLEAR when II.D.5 slid it), and a
-- pointer stands over the chosen kubb. B steps to the next lying kubb
-- (need().lying, in id order). Left and right choose the end on that side of the
-- screen, A raises (g:raise(choice, nil, id)). Or the crank (Jamie's idea): forward
-- tips the chosen kubb up onto its right-hand end on screen, backward onto its
-- left, slowly (crankPerRaise degrees from lying to standing, raising.tipPose),
-- and all the way up raises it; an end the engine does not allow will not tip,
-- and says why. The highlight starts on the engine's own choice (its raise
-- policy). After a raise the next lying kubb after it is chosen.
--
-- REST OF GAME (the web's and the iPhone's, Jamie's Settings sheet 2026-11-20:
-- auto raise is a game setting on every platform) is the System Menu's "Auto
-- raise" since 1.1.0 (main.lua; B is NEXT now): every raise from then on, this
-- turn and every later one, for both teams, until the match ends or it is turned
-- off, is the game's. Each of those shows its kubb for autoWait seconds, tipping
-- up over the last autoTip of them, then raises it with the call A makes on the
-- engine's end (g:raise(choice)); B there, BY HAND, gives the raising back,
-- starting with the kubb on screen. The choice lives in the table `auto` the
-- match scene hands in ({ on, changed }), which saves it with the match
-- (scenes/match, "Auto raise" in docs/notes/match.md).
--
-- Watch (opts.watch, 1.1.0: the Playdate's own raises against the Playdate): the
-- same automatic raise on the computer's policy, seen from the player's end
-- (opts.view: the player's side; camera.fromEnd kind "raise" in the player's frame,
-- engine 1.4.1), at the match's SPEED
-- (watch.speed: B steps it), A to skip (watch.skipping: every raise left is made at
-- once). Its punishment kubbs are placed at once (g:autoPunishment, as
-- core/match.settle does). The same calls core/match.settle makes, in the same
-- order, so a watched raise and a skipped one leave the same game.
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
import "core/world"
import "core/match"
import "render/ui"
import "render/world"
import "render/watchbar"

local gfx <const> = playdate.graphics
local pitch, frame, raising, ui = tw.pitch, tw.frame, tw.raising, tw.render.ui
local camera, quat, render, swing = tw.camera, tw.quat, tw.render.world, tw.swing
local floor, cos, sin, min, max = math.floor, math.cos, math.sin, math.min, math.max
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

tw.scenes = tw.scenes or {}
local settle = {}

settle.tune = {
	crankPerRaise = 270,  -- degrees of crank from lying to standing
	autoWait = 0.7,       -- s an automatic raise shows its kubb (the web's wait)
	autoTip = 0.4,        -- s of it, at the end, it tips up onto the engine's end
	-- the raise view's box (camera.fromEnd): under the rail, over the plaques
	raiseBox = { left = 6, top = 20, right = 394, bottom = 204 },
	groupMinWidth = 3.6,  -- m: the raise view is at least this wide across the lying kubbs
	pointerZ = 0.42,      -- m above the chosen kubb its pointer's tip stands
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

local set3D, holdCamera   -- (the raising section below)

-- the frame the raise is drawn in: the viewer's (watch) or the defender's
local function viewOf(s) return s.view or s.side end

-- Choose lying kubb `id` (one of need().lying): its decision, context and pose, the
-- end offered first, and the view of it.
local function choose(s, id)
	local g = s.g
	local dec, ctx, k = g:raiseOptions(id)
	s.kubb, s.dec, s.ctx, s.pose = id, dec, ctx, k.pose
	-- the end offered first, and what an automatic raise stands it on: the
	-- defender's policy (engine 0.12: core/match.raisePolicy, a person's the
	-- engine's advice), else the game's own
	local policy = s.policyFor and s.policyFor(s.side)
	s.choice = raising.choose(dec, ctx, policy or g.raisePolicy) or 1
	s.engineChoice = s.choice
	s.wait = settle.tune.autoWait
	s.blocked = nil
	set3D(s)
end

-- The kubb chosen after `last` was raised (or B from it): the next in the raise's
-- order (need().lying when it began) still lying, round to the first.
local function nextLying(s, last, lying)
	local still = {}
	for _, id in ipairs(lying) do still[id] = true end
	local order = s.order
	local at = 0
	for i, id in ipairs(order) do if id == last then at = i end end
	for k = 1, #order do
		local id = order[(at + k - 1) % #order + 1]
		if still[id] then return id end
	end
	return lying[1]
end

-- The next thing to do, from the engine: a raise, a punishment kubb, or done.
local function begin(s)
	local g = s.g
	local n = g:need()
	s.img = nil
	s.autoWas = s.auto.on
	if n.kind == "raise" then
		s.mode, s.side = "raise", n.side
		if s.watch and s.watch.skipping then
			-- skipped: every raise left at once, as core/match.settle makes them
			while g:need().kind == "raise" do
				g:raise(nil, s.policyFor and s.policyFor(n.side))
				s.raised = s.raised + 1
			end
			return begin(s)
		end
		-- one view for the whole raise, made at its start (and again should the
		-- other team raise in the same settle)
		if s.raiseSide ~= n.side then
			s.raiseSide, s.raiseFrom = n.side, s.raised
			s.raiseTotal = #n.lying
			s.order = {}
			for i, id in ipairs(n.lying) do s.order[i] = id end
			holdCamera(s, n.lying)
		end
		-- the game's raises go in the engine's order (need().kubb); a person's
		-- go on from the kubb raised last, or stay on the one chosen
		local id = n.kubb
		if not (s.auto.on or s.watch) then
			local here = false
			for _, l in ipairs(n.lying) do if l == s.kubb then here = true end end
			if here and not s.justRaised then id = s.kubb
			elseif s.justRaised then id = nextLying(s, s.justRaised, n.lying) end
		end
		s.justRaised = nil
		s.lying = n.lying
		choose(s, id)
	elseif n.kind == "punish" and s.watch then
		-- the computer's punishment kubb: where the engine puts it, at once
		g:autoPunishment()
		s.placed = s.placed + 1
		return begin(s)
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
-- provider an input provider; auto the match's automatic raising
-- ({ on = true } raises for the rest of the game; settle sets changed when B
-- turns it on or off), or nil for a table of this view's own; policyFor(side)
-- (optional) the raising policy for that side's kubbs (scenes/match: the
-- match's, core/match.raisePolicy), nil for the game's own (game.raisePolicy).
-- opts (1.1.0, optional): watch, the match's { speed, skipping } for the Playdate's
-- own raises (see "Watch" above); view, the side whose end the raise is seen from.
function settle.new(game, name, provider, auto, policyFor, opts)
	opts = opts or {}
	local s = { g = game, name = name, input = provider, done = false, raised = 0, placed = 0,
		auto = auto or { on = false }, policyFor = policyFor, watch = opts.watch, view = opts.view,
		-- the pitch's surface (core/match.surfaceName: the seat's depth)
		surface = tw.match.surfaceName(game) }
	begin(s)
	return s
end

-- ---------- raising ----------

local LONG <const>, SIDE <const> = pitch.kubbLong, pitch.kubbSide

-- How high a box's center sits on the ground at this orientation.
local function restZ(it, qw, qx, qy, qz)
	local _, _, _, _, _, _, r31, r32, r33 = quat.toMatrix(qw, qx, qy, qz)
	return math.abs(r31) * it.hx + math.abs(r32) * it.hy + math.abs(r33) * it.hz
end

-- An engine pose (world frame) on a render item, in the defender's view frame.
-- A standing kubb is drawn in its seat (core 1.0: world.seat, the lean the next
-- throw's world gives it; the same in either side's view), so the close-up shows
-- the neighbours as the pitch will.
local function placeItem(it, side, p, surface)
	local x, y = frame.point(side, p.x, p.y)
	local a = frame.angle(side, p.angle)
	if p.standing then
		local qw, qx, qy, qz = quat.fromAxisAngle(0, 0, 1, a)
		local seated
		qw, qx, qy, qz, seated = tw.world.seat(surface, it.kind, x, y, qw, qx, qy, qz)
		render.setPose(it, x, y, seated and restZ(it, qw, qx, qy, qz) or it.hz, qw, qx, qy, qz)
	else
		-- turned to its angle about the vertical, then laid along it (a face flat)
		local zw, zx, zy, zz = quat.fromAxisAngle(0, 0, 1, a)
		local lw, lx, ly, lz = quat.fromAxisAngle(-sin(a), cos(a), 0, math.pi / 2)
		render.setPose(it, x, y, SIDE / 2, quat.mul(lw, lx, ly, lz, zw, zx, zy, zz))
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
local readEnds   -- (below, with the raise camera)

local function tipTo(s, tip)
	s.tip = tip
	-- back to flat: which end is on the right is read again (the view may
	-- have turned while it was tipped)
	if tip == 0 and s.cam and s.vpose then readEnds(s) end
	local which = (tip >= 0) and s.rightEnd or (3 - s.rightEnd)
	local t = tip >= 0 and tip or -tip
	render.setPose(s.it, raising.tipPose(s.vpose, which, t))
	s.img = nil
end

-- The pitch as it stands, the chosen kubb lying, and which of its ends shows on the
-- right of the held view.
set3D = function(s)
	local vf = viewOf(s)
	s.vpose = frame.pose(vf, s.pose)
	local items, n = {}, 0
	local function add(id, kind, p)
		local it = render.item(id, kind)
		placeItem(it, vf, p, s.surface)
		n = n + 1
		items[n] = it
	end
	for _, o in ipairs(s.ctx.others) do add(o.id, "kubb", o.pose) end
	if s.ctx.king then add("king", "king", s.ctx.king) end
	s.it = render.item(s.kubb, "kubb")
	n = n + 1
	items[n] = s.it
	s.items, s.nitems = items, n
	-- a new kubb lies flat: its ends are read afresh (the last one may have
	-- been raised mid-tip)
	s.tip = 0
	readEnds(s)
	tipTo(s, 0)
end

-- The one view for the whole raise (engine 1.4, camera.fromEnd; the session's raise
-- camera): every lying kubb and each end it may stand on. From engine 1.4.1 the raise
-- camera stands over the group from the viewer's side. Before 1.4.1 the session also
-- kept the baseline and the king in it; on the
-- Playdate's 400 x 240 that left a lying kubb about 8 px long, too small to read its
-- ends or see the crank tip it, so the view keeps the group only, at least
-- groupMinWidth across (a lone kubb is not blown up to fill the screen). The
-- defender's own raise is the "raise" framing; the Playdate's, seen from the
-- player's end, is the "raise" framing too, in the player's frame (engine 1.4.1): the
-- "end" kind is now a person's eyes on the player's baseline, which left the group
-- small at the top of the screen and the player's own base kubbs, just in front of the
-- eyes, large and cut off behind the plaque; the raise camera stands at the group from
-- the player's side, those kubbs behind it.
holdCamera = function(s, lying)
	local g, vf = s.g, viewOf(s)
	local pts = {}
	local x0, x1, ysum, n = math.huge, -math.huge, 0, 0
	local function add(x, y)
		pts[#pts + 1] = { x, y, 0 }
		if x < x0 then x0 = x end
		if x > x1 then x1 = x end
		ysum, n = ysum + y, n + 1
	end
	for _, id in ipairs(lying) do
		local dec, _, k = g:raiseOptions(id)
		if dec then
			add(frame.point(vf, k.pose.x, k.pose.y))
			for _, ch in ipairs(dec.choices) do add(frame.point(vf, ch.pose.x, ch.pose.y)) end
		end
	end
	if n == 0 then add(0, 2) end
	local w, cx, cy = settle.tune.groupMinWidth, (x0 + x1) / 2, ysum / n
	if x1 - x0 < w then
		pts[#pts + 1] = { cx - w / 2, cy, 0 }
		pts[#pts + 1] = { cx + w / 2, cy, 0 }
	end
	s.cam = camera.fromEnd(nil, pts, settle.tune.raiseBox, "raise")
end

-- Which end of the lying kubb shows on the right of the raise camera.
readEnds = function(s)
	local c, vx, vy, a = s.cam, s.vpose.x, s.vpose.y, s.vpose.angle
	local e1 = camera.project(c, vx + cos(a) * LONG / 2, vy + sin(a) * LONG / 2, SIDE / 2) or 0
	local e2 = camera.project(c, vx - cos(a) * LONG / 2, vy - sin(a) * LONG / 2, SIDE / 2) or 0
	s.rightEnd = (e1 >= e2) and 1 or 2
end

local function raiseView(s)
	local side = viewOf(s)
	local c = s.cam
	render.advantageY, render.kidY = nil, nil
	render.setTurned(false)
	render.draw(c, s.items, s.nitems, nil)
	-- the footprints on the ground: every choice, the chosen one dotted
	local f = ui.label()
	local hk = SIDE / 2
	-- the pointer over the chosen kubb (when there is more than one to choose from)
	if #(s.lying or {}) > 1 and not s.watch and not s.auto.on then
		local px, py = camera.project(c, s.vpose.x, s.vpose.y, settle.tune.pointerZ)
		if px then
			gfx.setColor(WHITE)
			gfx.fillTriangle(px, py + 2, px - 8, py - 11, px + 8, py - 11)
			gfx.setColor(BLACK)
			gfx.fillTriangle(px, py, px - 6, py - 9, px + 6, py - 9)
		end
	end
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
				local ly = max(pts[2], pts[4], pts[6], pts[8], cy) + 18
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
	local done = s.raised - (s.raiseFrom or 0)
	rail(s.name(s.side), "RAISE " .. (done + 1) .. " OF " .. max(s.raiseTotal, done + 1), nil)
	-- watching the Playdate: its SPEED and SKIP plaque, drawn over this each frame
	if s.watch then return end
	local x = 6
	if s.auto.on then
		x = x + buttonPlaque("B", "BY HAND", x, 212) + 8
		ui.text(f, settle.fit(f, settle.autoText, 394 - x), 394, 216, false, "right")
		return
	end
	if #s.dec.choices > 1 then x = x + hint("lr", "END", x, 212) + 8 end
	x = x + buttonPlaque("A", "RAISE", x, 212) + 8
	if #(s.lying or {}) > 1 then x = x + buttonPlaque("B", "NEXT", x, 212) + 8 end
	ui.text(f, settle.fit(f, (#s.dec.choices > 1) and settle.crankText or settle.crankText1, 394 - x), 394, 216,
		false, "right")
end

-- the line beside the plaques, longest first: the first that fits in w px
settle.crankText = { "OR CRANK EITHER END UP", "OR CRANK AN END UP", "OR CRANK" }
settle.crankText1 = { "OR CRANK IT UP", "OR CRANK" }
settle.autoText = { "RAISING AUTOMATICALLY FOR THE REST OF THE GAME", "RAISING FOR THE REST OF THE GAME",
	"AUTOMATIC FOR THE REST OF THE GAME", "AUTOMATIC" }
function settle.fit(f, texts, w)
	for _, t in ipairs(texts) do
		if f:getTextWidth(t) <= w then return t end
	end
	return texts[#texts]
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

-- An automatic raise (REST OF GAME, or the Playdate's watched): the kubb shows,
-- tips up onto the engine's end over the last autoTip seconds, then is raised.
-- dt: the time to count (the watch's at its speed).
local function autoStep(s, dt)
	s.wait = s.wait - dt
	local t = settle.tune
	local c = s.dec.choices[s.engineChoice]
	if c and s.wait < t.autoTip then
		local u = 1 - max(0, s.wait) / t.autoTip
		tipTo(s, (c.which == s.rightEnd) and u or -u)
	end
	if s.wait <= 0 then
		s.g:raise(s.engineChoice)
		s.raised = s.raised + 1
		begin(s)
	end
end

function settle.update(s)
	local p = s.input
	p:advance()
	if s.done then return end
	-- the System Menu's Auto raise turned on or off under the raise: start again
	-- from the kubb the game raises next (or the one it was on)
	if s.mode == "raise" and s.auto.on ~= s.autoWas then begin(s) end
	if s.mode == "raise" and s.watch then
		-- the Playdate's: B its speed, A skips the rest (scenes/match keeps both)
		local w = s.watch
		if p:pressed("b") then w.speed, w.changed = tw.render.watchbar.nextSpeed(w.speed), true end
		if p:pressed("a") then
			w.skipping, w.changed = true, true
			begin(s)
			return
		end
		autoStep(s, p:dt() * (w.speed or 1))
		return
	end
	if s.mode == "raise" and s.auto.on then
		-- raising for the rest of the game: B gives it back, else the kubb is
		-- raised on the engine's end once it has been seen
		if p:pressed("b") then
			s.auto.on, s.auto.changed = false, true
			begin(s)
			return
		end
		autoStep(s, p:dt())
		return
	end
	if s.mode == "raise" and p:pressed("b") and #s.lying > 1 then
		-- NEXT: the next lying kubb (any order, engine 1.4)
		choose(s, nextLying(s, s.kubb, s.lying))
		return
	end
	if s.mode == "raise" then
		-- left/right: the end on that side of the screen (the crank's choice too)
		local lr = (p:pressed("right") and 1 or 0) - (p:pressed("left") and 1 or 0)
		if lr ~= 0 and s.tip == 0 then
			readEnds(s)
			local which = (lr > 0) and s.rightEnd or (3 - s.rightEnd)
			local ci = choiceFor(s, which)
			if ci then s.choice, s.blocked = ci, nil else s.blocked = endWhy(s, which) end
			s.img = nil
		end
		-- the crank tips it: forward toward the right-hand end, back the left
		local d = p:crank() * swing.tune.forwardSign
		local up = false
		if d ~= 0 then
			local tip = s.tip + d / settle.tune.crankPerRaise
			-- through flat (or from it): read the ends for this view first
			if s.tip == 0 or (s.tip > 0) ~= (tip > 0) then readEnds(s) end
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
			s.g:raise(s.choice, nil, s.kubb)
			s.raised = s.raised + 1
			s.justRaised = s.kubb
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
	if s.mode == "raise" and s.watch then tw.render.watchbar.draw(s.watch.speed or 1) end
end

-- (1.1.0) The System Menu's Auto raise (main.lua): REST OF GAME on or off. The
-- raise on screen starts again from the game's kubb (settle.update sees it).
function settle.setAuto(s, on)
	if s.auto.on == on then return end
	s.auto.on, s.auto.changed = on, true
end

tw.scenes.settle = settle
