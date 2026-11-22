-- The Names screen: a name for a player, a guest or a team, generated or typed.
--
-- Generated (kubb-engine docs/NAMES.md): two words from the engine's lists
-- (core/namegen through device/namepick), the crank stepping a word. Typed (the owner,
-- 2026-11-22: "On the Playdate we should allow players to both use the generated names
-- as well as enter their own. On the web we have to worry about people putting
-- profanity in that others see. In the playdate nobody else can see it so we can allow
-- profiles to have user entered names."): the Playdate's system keyboard, as the game
-- had before 0.12.0, under core/names' rules (letters, spaces, hyphens and apostrophes,
-- one letter at least), at most scene.tune.typedMax letters.
--
-- On the left a black panel: whose name this is, the name in the display face, the
-- game file id it will have, what comes next. On the right four rows: FIRST WORD,
-- SECOND WORD, SHUFFLE (a whole new name) and TYPE A NAME. Up/down choose a row; the
-- crank (a word every scene.tune.crankStep degrees, raw direction, as the score sheet
-- scrolls) or left/right step that row's word, or on SHUFFLE roll a new name. A takes
-- the name, except on TYPE A NAME, where A opens the keyboard (on the name typed so far,
-- or empty). The keyboard's OK takes the typed name (as before 0.12.0); a refused one
-- stays shown with the reason; its cancel goes back to what was shown. While a typed name is shown, stepping a word or SHUFFLE goes back
-- to the generated name. B goes back.
--
-- scene.new(provider, mode, opts): mode "player" (the one mode; the name is in
-- s.list.A once s.done, s.exit on B). opts.kind: "player" (default: a player or a
-- guest, "<adjective> <wood>") or "team" ("<adjective> <noun>", "The <noun>", "<wood>
-- <noun>"); opts.label and opts.nxt say what for; opts.initial is the name it starts
-- on: a generated name of that kind opens on the generator, any other name (one typed,
-- now or on an older build) opens typed, on TYPE A NAME; none rolls one.
-- opts.check(name) may refuse a name (nil and why: "taken", "full", "empty"), which
-- stays on screen with the reason. opts.seed: the draw's seed (self-tests; else the
-- clock).
--
-- Self-tests drive it with scene.set (take a generated name), scene.type (what the
-- keyboard's OK does with its text), scene.step, scene.shuffle, scene.ok and
-- scene.back, or through the input provider (opts.scripted: no keyboard is shown).
import "CoreLibs/graphics"
import "CoreLibs/keyboard"
import "core/tw"
import "core/names"
import "core/throwplan"
import "device/namepick"
import "render/ui"

local gfx <const> = playdate.graphics
local kb = playdate.keyboard
local cnames, np, ui = tw.names, tw.namepick, tw.render.ui
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

tw.scenes = tw.scenes or {}
local scene = {}

scene.tune = {
	x = 16,           -- the panel's left margin
	panelW = 212,     -- the black panel's width (the keyboard covers the rest)
	labelY = 18, nameY = 44, ruleY = 104, whyY = 116, idY = 134, nextY = 172, backY = 214,
	bigMax = 178,     -- px: a name wider than this at cap 32 is drawn at cap 16
	midMax = 192,     -- px: at cap 16 (the widest generated name is 189), else the label face
	rowY = 22, rowH = 40,   -- the right panel's rows
	crankStep = 24,   -- degrees of crank a word
	typedMax = 10,    -- letters a typed name may have: the game's limit before 0.12.0,
	                  -- which every screen fits in the widest letters (names-fit)
}

local ROWS <const> = { "FIRST WORD", "SECOND WORD", "SHUFFLE", "TYPE A NAME" }
local TYPE_ROW <const> = 4

-- What a refused name shows.
scene.WHY = { taken = "THAT NAME IS TAKEN", full = "NO ROOM FOR MORE PLAYERS", empty = "A NAME NEEDS A LETTER" }

local function draw_(s) s.img = nil end

-- A typed name as it may be: core/names' characters and tidying, then typedMax letters.
function scene.clean(text)
	local t = cnames.clean(text)
	if #t > scene.tune.typedMax then t = t:sub(1, scene.tune.typedMax) end
	return t
end

-- Take `text` if it is a generated name of the screen's kind (self-tests).
function scene.set(s, text)
	local ok = np.set(s.pick, text)
	if ok then s.typed, s.why = nil, nil; draw_(s) end
	return ok
end

-- What the keyboard's OK does: the typed name becomes the one shown. A name with no
-- letter is refused (the generated one, or the earlier typed one, stays). Returns
-- whether it was taken.
function scene.type(s, text)
	if s.keyboard == "scripted" then s.keyboard = nil end   -- (self-tests: the keyboard's OK)
	local name = cnames.finish(scene.clean(text or ""))
	if not name then
		s.why = "empty"
		draw_(s)
		return false
	end
	s.typed, s.why = name, nil
	draw_(s)
	return true
end

function scene.step(s, row, d)
	if s.typed then s.typed = nil else np.step(s.pick, row, d) end
	s.why = nil
	draw_(s)
end

function scene.shuffle(s)
	if s.typed then s.typed = nil else np.shuffle(s.pick, s.rand) end
	s.why = nil
	draw_(s)
end

-- The name shown now: the typed one, else the generated one.
function scene.text(s) return s.typed or np.text(s.pick) end

function scene.ok(s)
	local name = scene.text(s)
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

-- The system keyboard on the typed name so far (not in self-tests).
local function openKeyboard(s)
	if s.scripted then s.keyboard = "scripted"; return end
	s.keyboard = true
	kb.textChangedCallback = function()
		local t = scene.clean(kb.text)
		if t ~= kb.text then kb.text = t end
		s.typing = t
		draw_(s)
	end
	kb.keyboardWillHideCallback = function(ok) s.closing = ok and "ok" or "back" end
	kb.keyboardDidHideCallback = function()
		-- OK takes the typed name, as the keyboard did before 0.12.0 (a refused one stays,
		-- with the reason, and A opens the keyboard on it again)
		if s.closing == "ok" and scene.type(s, s.typing or "") then scene.ok(s) end
		s.closing, s.typing, s.keyboard = nil, nil, nil
		draw_(s)
	end
	kb.setCapitalizationBehavior(kb.kCapitalizationWords)
	s.typing = s.typed or ""
	kb.show(s.typing)
	draw_(s)
end
scene.openKeyboard = openKeyboard

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
	-- a name that is not generated (typed now or on an older build) opens typed
	local init = type(opts.initial) == "string" and cnames.finish(opts.initial) or nil
	if init and np.text(s.pick) ~= opts.initial then s.typed, s.row = init, TYPE_ROW end
	s.list = { A = scene.text(s) }
	return s
end

function scene.enter(s)
	s.img = nil
end

function scene.update(s)
	local p = s.input
	p:advance()
	-- the keyboard takes the input while it shows
	if s.keyboard then return end
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
	if d ~= 0 and s.row ~= TYPE_ROW then
		if s.row == 3 then scene.shuffle(s) else scene.step(s, s.row, d) end
	end
	if p:pressed("a") then
		if s.row == TYPE_ROW then openKeyboard(s) else scene.ok(s) end
	elseif p:pressed("b") then
		scene.back(s)
	end
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
	local shown = s.keyboard and (s.typing or "") or scene.text(s)
	local typedNow = s.keyboard or s.typed
	-- the black panel: whose name, the name, its id, what comes next
	gfx.setColor(BLACK)
	gfx.fillRect(0, 0, t.panelW, 240)
	pennant(x, t.labelY, true)
	ui.text(label, s.label, x + 15, t.labelY, true)
	local text = string.upper(shown)
	local f = (d32:getTextWidth(text) <= t.bigMax) and d32 or d16
	if f == d16 and d16:getTextWidth(text) > t.midMax then f = label end
	local w = ui.text(f, text, x, t.nameY + ((f == d32) and 0 or 18), true)
	if s.keyboard then
		-- a cursor bar after the text being typed
		gfx.setColor(WHITE)
		gfx.fillRect(x + w + 4, t.nameY + ((f == d32) and 0 or 16), 3, (f == d32) and 34 or 18)
	end
	gfx.setColor(WHITE)
	gfx.fillRect(x, t.ruleY, t.panelW - 2 * x, 3)
	local line = typedNow and ("TYPED: UP TO " .. t.typedMax .. " LETTERS") or "WORDS FROM THE WOODSHED"
	ui.text(label, s.why and (scene.WHY[s.why] or "TRY ANOTHER NAME") or line, x, t.whyY, true)
	-- the id in lower case, as the file has it (ui.text would capitalise it), on a line
	-- of its own: a 16-letter name's id does not fit beside the words
	ui.text(label, "ON THE SCORE SHEET", x, t.idY, true)
	gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
	label:drawText(cnames.id(shown ~= "" and shown or "p"), x, t.idY + 14)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	pennant(x, t.nextY, true)
	ui.text(label, s.nxt, x + 15, t.nextY, true)
	if s.keyboard then
		ui.text(label, "KEYBOARD: OK TAKES IT", x, t.backY + 2, true)
	else
		ui.button("A", (s.row == TYPE_ROW) and "TYPE" or "TAKE IT", x, t.backY, true)
		ui.button("B", "BACK", x + 90, t.backY, true)
	end
	-- the rows, the chosen one in a black box with arrows (the keyboard covers them
	-- while it shows)
	local rx, rw = t.panelW + 10, 400 - t.panelW - 20
	local words = np.slots(s.pick)
	for i, row in ipairs(ROWS) do
		local y = t.rowY + (i - 1) * t.rowH
		local on = i == s.row
		if on then
			gfx.setColor(BLACK)
			gfx.fillRect(rx - 4, y - 4, rw + 8, 38)
		end
		ui.text(label, row, rx + 4, y, on)
		local value
		if i == TYPE_ROW then value = s.typed and string.upper(s.typed) or "YOUR OWN"
		elseif i == 3 then value = s.typed and "BACK TO WORDS" or "ANY NAME"
		else value = string.upper(words[i] or "") end
		local vf = (d16:getTextWidth(value) <= rw - 34) and d16 or label
		local vx = rx + 16
		local vy = y + 14 + ((vf == d16) and 0 or 3)
		-- a generated word set aside while a typed name is shown
		if s.typed and i <= 2 then vf = label; vy = y + 17 end
		local vw = ui.text(vf, value, vx, vy, on)
		if on and i ~= TYPE_ROW then
			-- arrows either side of the word (the display face has no < >)
			gfx.setColor(WHITE)
			gfx.fillTriangle(vx - 6, y + 15, vx - 6, y + 29, vx - 13, y + 22)
			gfx.fillTriangle(vx + vw + 6, y + 15, vx + vw + 6, y + 29, vx + vw + 13, y + 22)
		end
	end
	local hy = t.rowY + 4 * t.rowH + 2
	local hint = (s.row == TYPE_ROW) and "KEYBOARD OK TAKES IT"
		or (s.typed and "CRANK: BACK TO WORDS")
		or ((s.row == 3) and "CRANK: A NEW NAME" or "CRANK: THE NEXT WORD")
	ui.text(label, hint, rx + 4, hy)
	ui.text(label, "UP/DOWN: PICK A ROW", rx + 4, hy + 15)
	gfx.popContext()
	return img
end

function scene.draw(s)
	if not s.img then s.img = render(s) end
	s.img:draw(0, 0)
end

tw.scenes.names = scene
