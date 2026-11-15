-- Team names before a match (the Names board): the Playdate's system keyboard
-- on the right (not ours to draw), on the left a black panel with whose name
-- this is, the name as typed in the display font, UP TO 10 LETTERS, the game
-- file id it will have, and what comes next. OK takes the name (it needs a
-- letter); the keyboard's cancel (B) goes back a step, from the first name to
-- the title. PASS + PLAY asks for both teams, VS PLAYDATE for the player's.
-- The last names used are saved (playdate.datastore "names") and offered
-- again.
--
-- Mode "player" asks for one saved player's name (scenes/players: a new
-- player or a rename): opts.label and opts.nxt say what for, opts.initial is
-- the text it starts with, and opts.check(name) may refuse a name (it
-- returns nil and why: "taken", "full"); a refused name stays typed with the
-- reason under it. Nothing is saved to "names" in that mode; the caller
-- reads s.list.A once s.done.
--
-- Self-tests drive it without the keyboard (opts.scripted): names.type,
-- names.ok and names.back do what the keyboard's callbacks do.
import "CoreLibs/graphics"
import "CoreLibs/keyboard"
import "core/tw"
import "core/names"
import "render/ui"

local gfx <const> = playdate.graphics
local kb = playdate.keyboard
local cnames, ui = tw.names, tw.render.ui

tw.scenes = tw.scenes or {}
local scene = {}

scene.tune = {
	x = 16,           -- the panel's left margin
	panelW = 212,     -- the panel's width (the keyboard covers the rest)
	labelY = 18, nameY = 44, ruleY = 104, upToY = 118, idY = 134, nextY = 166, backY = 214,
	bigMax = 178,     -- px: a name wider than this at cap 32 is drawn at cap 16
}

local STEPS = {
	match = { { side = "A", label = "FIRST TEAM", nxt = "SECOND TEAM NEXT" },
		{ side = "B", label = "SECOND TEAM", nxt = "THEN THE MATCH" } },
	vs = { { side = "A", label = "YOUR NAME", nxt = "THEN THE MATCH" } },
}

-- the saved names, or the defaults
local function saved(mode)
	local d = playdate.datastore.read("names") or {}
	local m = d[mode] or {}
	return { A = m.A or (mode == "vs" and cnames.defaults.you or cnames.defaults.A), B = m.B or cnames.defaults.B }
end

local function save(mode, list)
	local d = playdate.datastore.read("names") or {}
	d[mode] = { A = list.A, B = list.B }
	playdate.datastore.write(d, "names")
end

local showStep

-- What a refused name shows instead of UP TO 10 LETTERS.
scene.WHY = { taken = "THAT NAME IS TAKEN", full = "NO ROOM FOR MORE PLAYERS" }

-- What the keyboard's callbacks do (and the self-tests).
function scene.type(s, text)
	local t = cnames.clean(text)
	if t ~= s.text then s.why = nil end
	s.text = t
	s.img = nil
	return s.text
end

function scene.ok(s)
	local name = cnames.finish(s.text)
	if not name then return false end      -- no letter: the same step again
	local step = s.steps[s.i]
	if s.check then
		local ok, why = s.check(name)
		if not ok then
			s.why, s.img = why, nil
			s.list[step.side] = s.text       -- keep what was typed for the next try
			return false
		end
	end
	s.why = nil
	s.list[step.side] = name
	if s.i < #s.steps then
		s.i = s.i + 1
	else
		s.done = true
		if not s.scripted and s.mode ~= "player" then save(s.mode, s.list) end
	end
	return true
end

function scene.back(s)
	if s.i == 1 then s.exit = "title" else s.i = s.i - 1 end
end

-- mode: "match" (both teams) or "vs" (the player). opts.scripted: no keyboard.
function scene.new(provider, mode, opts)
	opts = opts or {}
	local s = { input = provider, mode = mode, steps = STEPS[mode], i = 1, done = false, exit = nil,
		scripted = opts.scripted, img = nil, text = "", check = opts.check }
	if mode == "player" then
		s.steps = { { side = "A", label = opts.label or "NEW PLAYER", nxt = opts.nxt or "THEN THE LEVEL" } }
		s.list = { A = opts.initial or "" }
	else
		s.list = opts.scripted and { A = cnames.defaults.A, B = cnames.defaults.B } or saved(mode)
	end
	if mode == "vs" then s.list.B = "Playdate" end
	return s
end

showStep = function(s)
	local step = s.steps[s.i]
	s.text = s.list[step.side] or ""
	s.img = nil
	if s.scripted then return end
	kb.textChangedCallback = function()
		local t = cnames.clean(kb.text)
		if t ~= kb.text then kb.text = t end
		scene.type(s, t)
	end
	kb.keyboardWillHideCallback = function(ok) s.closing = ok and "ok" or "back" end
	kb.keyboardDidHideCallback = function()
		local how = s.closing
		s.closing = nil
		if how == "ok" then scene.ok(s) else scene.back(s) end
		if not s.done and not s.exit then showStep(s) end
	end
	kb.setCapitalizationBehavior(kb.kCapitalizationWords)
	kb.show(s.text)
end

function scene.enter(s)
	s.shownI = s.i
	showStep(s)
end

-- The keyboard takes the input while it shows; nothing to do per frame but
-- keep a scripted step's text current.
function scene.update(s)
	s.input:advance()
	if s.scripted and s.shownI ~= s.i then
		s.shownI = s.i
		showStep(s)
	end
end

local function render(s)
	local t = scene.tune
	local step = s.steps[s.i]
	local img = gfx.image.new(400, 240, gfx.kColorBlack)
	gfx.pushContext(img)
	local label = ui.label()
	local x = t.x
	local function pennant(y)
		gfx.setColor(gfx.kColorWhite)
		gfx.fillPolygon(x, y, x + 9, y, x + 6, y + 3, x + 9, y + 6, x + 2, y + 6, x + 2, y + 11, x, y + 11)
	end
	pennant(t.labelY)
	ui.text(label, step.label, x + 15, t.labelY, true)
	-- the name as typed, with a cursor bar after it
	local text = string.upper(s.text)
	local big = ui.display(32)
	local f = (big:getTextWidth(text) <= t.bigMax) and big or ui.display(16)
	local w = ui.text(f, text, x, t.nameY + ((f == big) and 0 or 18), true)
	gfx.setColor(gfx.kColorWhite)
	local ch = (f == big) and 34 or 18
	gfx.fillRect(x + w + 4, t.nameY + ((f == big) and 0 or 16), 3, ch)
	gfx.fillRect(x, t.ruleY, t.panelW - 2 * x, 3)
	ui.text(label, s.why and (scene.WHY[s.why] or "TRY ANOTHER NAME") or ("UP TO " .. cnames.max .. " LETTERS"),
		x, t.upToY, true)
	-- the id in lower case, as the file has it (ui.text would capitalise it)
	local pre = "ON THE SCORE SHEET: "
	local pw = ui.text(label, pre, x, t.idY, true)
	gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
	label:drawText(cnames.id(s.text ~= "" and s.text or "p"), x + pw, t.idY)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	pennant(t.nextY)
	ui.text(label, step.nxt, x + 15, t.nextY, true)
	ui.button("B", "BACK", x, t.backY, true)
	if s.scripted then
		-- (self-tests: where the system keyboard will be)
		gfx.setColor(gfx.kColorWhite)
		gfx.fillRect(t.panelW, 0, 400 - t.panelW, 240)
		gfx.setColor(gfx.kColorBlack)
		gfx.drawRect(t.panelW + 8, 8, 400 - t.panelW - 16, 224)
		ui.text(label, "SYSTEM KEYBOARD", (t.panelW + 400) // 2, 114, false, "center")
	end
	gfx.popContext()
	return img
end

function scene.draw(s)
	if not s.img then s.img = render(s) end
	s.img:draw(0, 0)
end

tw.scenes.names = scene
