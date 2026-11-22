-- The Names screen: a generated name for a player, a guest or a team (kubb-engine
-- docs/NAMES.md; the owner, 2026-11-21: the Playdate switches to generated names too,
-- "the crank steps a word"). Nothing is typed: every name is two words from the
-- engine's lists (core/namegen through device/namepick).
--
-- On the left a black panel: whose name this is, the name in the display face, the
-- game file id it will have, what comes next. On the right three rows: the first word,
-- the second word, and SHUFFLE (a whole new name). Up/down choose a row; the crank (a
-- word every scene.tune.crankStep degrees, raw direction, as the score sheet scrolls)
-- or left/right step that row's word, or on SHUFFLE roll a new name. A takes the name,
-- B goes back.
--
-- scene.new(provider, mode, opts): mode "player" (the one mode; the name is in
-- s.list.A once s.done, s.exit on B). opts.kind: "player" (default: a player or a
-- guest, "<adjective> <wood>") or "team" ("<adjective> <noun>", "The <noun>", "<wood>
-- <noun>"); opts.label and opts.nxt say what for; opts.initial is the name it starts on
-- when it is a name of that kind (else one is rolled); opts.check(name) may refuse a
-- name (nil and why: "taken", "full"), which stays on screen with the reason.
-- opts.seed: the draw's seed (self-tests; else the clock).
--
-- Self-tests drive it with scene.set (take a generated name), scene.step, scene.shuffle,
-- scene.ok and scene.back, or through the input provider.
import "CoreLibs/graphics"
import "core/tw"
import "core/names"
import "core/throwplan"
import "device/namepick"
import "render/ui"

local gfx <const> = playdate.graphics
local cnames, np, ui = tw.names, tw.namepick, tw.render.ui
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

tw.scenes = tw.scenes or {}
local scene = {}

scene.tune = {
	x = 16,           -- the panel's left margin
	panelW = 212,     -- the black panel's width
	labelY = 18, nameY = 44, ruleY = 104, whyY = 116, idY = 134, nextY = 172, backY = 214,
	bigMax = 178,     -- px: a name wider than this at cap 32 is drawn at cap 16
	midMax = 192,     -- px: at cap 16 (the widest generated name is 189), else the label face
	rowY = 30, rowH = 50,   -- the right panel's rows
	crankStep = 24,   -- degrees of crank a word
}

local ROWS <const> = { "FIRST WORD", "SECOND WORD", "SHUFFLE" }

-- What a refused name shows.
scene.WHY = { taken = "THAT NAME IS TAKEN", full = "NO ROOM FOR MORE PLAYERS" }

local function draw_(s) s.img = nil end

-- Take `text` if it is a generated name of the screen's kind (self-tests).
function scene.set(s, text)
	local ok = np.set(s.pick, text)
	if ok then s.why = nil; draw_(s) end
	return ok
end

function scene.step(s, row, d)
	np.step(s.pick, row, d)
	s.why = nil
	draw_(s)
end

function scene.shuffle(s)
	np.shuffle(s.pick, s.rand)
	s.why = nil
	draw_(s)
end

function scene.text(s) return np.text(s.pick) end

function scene.ok(s)
	local name = np.text(s.pick)
	if s.check then
		local ok, why = s.check(name)
		if not ok then
			s.why = why
			draw_(s)
			return false
		end
	end
	s.why = nil
	s.list.A = name
	s.done = true
	return true
end

function scene.back(s)
	s.exit = "back"
end

function scene.new(provider, mode, opts)
	opts = opts or {}
	local seed = opts.seed or (opts.scripted and 1) or playdate.getSecondsSinceEpoch()
	local r = tw.plan.rng(seed)
	local function rand(n)
		local k = math.floor(r.next() * n) + 1
		return (k > n) and n or k
	end
	local kind = opts.kind or "player"
	local s = { input = provider, mode = mode, kind = kind, done = false, exit = nil, scripted = opts.scripted,
		img = nil, check = opts.check, row = 1, crankAcc = 0, rand = rand,
		label = opts.label or "NEW PLAYER", nxt = opts.nxt or "THEN BACK" }
	s.pick = np.new(kind, opts.initial, rand)
	s.list = { A = np.text(s.pick) }
	return s
end

function scene.enter(s)
	s.img = nil
end

function scene.update(s)
	local p = s.input
	p:advance()
	if p:pressed("up") then s.row = (s.row - 2) % #ROWS + 1; draw_(s) end
	if p:pressed("down") then s.row = s.row % #ROWS + 1; draw_(s) end
	local d = (p:pressed("right") and 1 or 0) - (p:pressed("left") and 1 or 0)
	-- the crank: a word every crankStep degrees, either way
	local c = p:crank() or 0
	if c ~= 0 then
		s.crankAcc = s.crankAcc + c
		local st = scene.tune.crankStep
		if s.crankAcc >= st then d = d + 1; s.crankAcc = s.crankAcc - st
		elseif s.crankAcc <= -st then d = d - 1; s.crankAcc = s.crankAcc + st end
	end
	if d ~= 0 then
		if s.row == 3 then scene.shuffle(s) else scene.step(s, s.row, d) end
	end
	if p:pressed("a") then scene.ok(s)
	elseif p:pressed("b") then scene.back(s) end
end

local function pennant(x, y, white)
	gfx.setColor(white and WHITE or BLACK)
	gfx.fillPolygon(x, y, x + 9, y, x + 6, y + 3, x + 9, y + 6, x + 2, y + 6, x + 2, y + 11, x, y + 11)
end

local function render(s)
	local t = scene.tune
	local img = gfx.image.new(400, 240, WHITE)
	gfx.pushContext(img)
	local label, d16, d32 = ui.label(), ui.display(16), ui.display(32)
	local x = t.x
	-- the black panel: whose name, the name, its id, what comes next
	gfx.setColor(BLACK)
	gfx.fillRect(0, 0, t.panelW, 240)
	pennant(x, t.labelY, true)
	ui.text(label, s.label, x + 15, t.labelY, true)
	local text = string.upper(np.text(s.pick))
	local f = (d32:getTextWidth(text) <= t.bigMax) and d32 or d16
	if f == d16 and d16:getTextWidth(text) > t.midMax then f = label end
	ui.text(f, text, x, t.nameY + ((f == d32) and 0 or 18), true)
	gfx.setColor(WHITE)
	gfx.fillRect(x, t.ruleY, t.panelW - 2 * x, 3)
	ui.text(label, s.why and (scene.WHY[s.why] or "TRY ANOTHER NAME") or "WORDS FROM THE WOODSHED", x, t.whyY, true)
	-- the id in lower case, as the file has it (ui.text would capitalise it), on a line
	-- of its own: a 16-letter name's id does not fit beside the words
	ui.text(label, "ON THE SCORE SHEET", x, t.idY, true)
	gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
	label:drawText(cnames.id(np.text(s.pick)), x, t.idY + 14)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	pennant(x, t.nextY, true)
	ui.text(label, s.nxt, x + 15, t.nextY, true)
	ui.button("A", "TAKE IT", x, t.backY, true)
	ui.button("B", "BACK", x + 90, t.backY, true)
	-- the rows: the two words and SHUFFLE, the chosen one in a black box with arrows
	local rx, rw = t.panelW + 10, 400 - t.panelW - 20
	local words = np.slots(s.pick)
	for i, row in ipairs(ROWS) do
		local y = t.rowY + (i - 1) * t.rowH
		local on = i == s.row
		if on then
			gfx.setColor(BLACK)
			gfx.fillRect(rx - 4, y - 4, rw + 8, 42)
		end
		ui.text(label, row, rx + 4, y, on)
		local value = (i == 3) and "ANY NAME" or string.upper(words[i] or "")
		local vf = (d16:getTextWidth(value) <= rw - 34) and d16 or label
		local vx = rx + 16
		local w = ui.text(vf, value, vx, y + 16 + ((vf == d16) and 0 or 3), on)
		if on then
			-- arrows either side of the word (the display face has no < >)
			gfx.setColor(WHITE)
			gfx.fillTriangle(vx - 6, y + 17, vx - 6, y + 31, vx - 13, y + 24)
			gfx.fillTriangle(vx + w + 6, y + 17, vx + w + 6, y + 31, vx + w + 13, y + 24)
		end
	end
	ui.text(label, (s.row == 3) and "CRANK: A NEW NAME" or "CRANK: THE NEXT WORD", rx + 4, t.rowY + 3 * t.rowH + 4)
	ui.text(label, "UP/DOWN: PICK A ROW", rx + 4, t.rowY + 3 * t.rowH + 20)
	gfx.popContext()
	return img
end

function scene.draw(s)
	if not s.img then s.img = render(s) end
	s.img:draw(0, 0)
end

tw.scenes.names = scene
