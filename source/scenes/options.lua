-- The match options (Jamie, 2026-11-14): after the names, before every match
-- (PASS + PLAY and VS PLAYDATE): the surface, the opening, who stands the
-- thrown-in kubbs up and the wind; against the Playdate also COMPUTER, its
-- throw level (a match option since core 0.9; KID first since engine 0.15, which
-- makes the match a Kid match: docs/DESIGN.md "Kid matches"). Rows from core/matchopts, which has no kubb set since 0.9
-- (sets are a look for the web and the iPhone only). A kept choice from an
-- older build that still holds a set loads all the same (matchopts.valid).
-- Up/down choose a row, left/right change its value, A starts the match, B
-- goes back to the names. The choice is kept (playdate.datastore
-- "matchopts") and offered next time.
-- One image, redrawn only on a change.
import "CoreLibs/graphics"
import "core/tw"
import "core/matchopts"
import "render/ui"

local gfx <const> = playdate.graphics
local matchopts, ui = tw.matchopts, tw.render.ui
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

tw.scenes = tw.scenes or {}
local scene = {}

scene.tune = {
	key = "matchopts",   -- the datastore file
	top = 20,            -- y of the first row
	rowH = 30,           -- px a row
	labelX = 16,         -- the row's label
	valueX = 150,        -- the value (display 16), between arrows
	arrowGap = 10,
	noteY = 178,         -- the chosen row's line of explanation
	buttonY = 214,
}

-- what each row is for, under the rows
scene.notes = {
	surface = "THE GROUND: GRASS HOLDS, SAND STOPS, SNOW SLIDES",
	opening = "2-4-6: TEAM A OPENS WITH 2, B WITH 4, THEN 6",
	raising = "WHO STANDS UP THE KUBBS THROWN IN",
	wind = "WIND PUSHES BATONS AND KUBBS IN THE AIR",
	computer = "HOW WELL THE PLAYDATE THROWS",
}
scene.openingSix = "SIX: SIX BATONS A TURN FROM THE START"
-- KID: the Kid rules for both teams and the wide meter (kubb-engine docs/notes/kid-mode.md)
scene.computerKid = "KID RULES: A CLOSER LINE, 3 BASE KUBBS"

-- the rows shown in each mode: core/matchopts' rows, COMPUTER only against
-- the Playdate
function scene.rowsFor(mode)
	local rows = {}
	for _, row in ipairs(matchopts.list) do
		if row.key ~= "computer" or mode == "vs" then rows[#rows + 1] = row end
	end
	return rows
end

-- mode: "match" (PASS + PLAY) or "vs" (VS PLAYDATE). opts.scripted: nothing
-- read or saved (self-tests).
function scene.new(provider, mode, opts)
	opts = opts or {}
	local s = { input = provider, mode = mode, row = 1, img = nil, done = false, back = false,
		scripted = opts.scripted, rows = scene.rowsFor(mode) }
	local kept = (not s.scripted) and playdate.datastore.read(scene.tune.key) or nil
	s.choice = matchopts.valid(kept)
	return s
end

local function render(s)
	local t = scene.tune
	local label, d16 = ui.label(), ui.display(16)
	gfx.clear(WHITE)
	gfx.setColor(BLACK)
	gfx.fillRect(0, 0, 400, 14)
	ui.text(label, "MATCH OPTIONS", 6, 2, true)
	ui.text(label, (s.mode == "vs") and "VS PLAYDATE" or "PASS + PLAY", 394, 2, true, "right")
	for i, row in ipairs(s.rows) do
		local y = t.top + (i - 1) * t.rowH
		local chosen = (i == s.row)
		if chosen then
			gfx.setColor(BLACK)
			gfx.fillRect(0, y, 400, t.rowH - 6)
		end
		local boxH = t.rowH - 6
		ui.text(label, row.label, t.labelX, y + (boxH - 10) // 2, chosen)
		local value = matchopts.shown(s.choice, row.key)
		local f = (d16:getTextWidth(value) <= 400 - t.valueX - 40) and d16 or label
		local vy = y + ((f == d16) and (boxH - 16) // 2 or (boxH - 10) // 2)
		local w = ui.text(f, value, t.valueX + t.arrowGap + 8, vy, chosen)
		if chosen then
			-- the arrows that say left/right change it
			gfx.setColor(WHITE)
			local cy = y + (t.rowH - 6) // 2
			local lx = t.valueX
			gfx.fillTriangle(lx, cy, lx + 8, cy - 6, lx + 8, cy + 6)
			local rx = t.valueX + t.arrowGap + 8 + w + t.arrowGap
			gfx.fillTriangle(rx + 8, cy, rx, cy - 6, rx, cy + 6)
		end
	end
	local key = s.rows[s.row].key
	local note = scene.notes[key]
	if key == "opening" and matchopts.value(s.choice, "opening") == "six" then note = scene.openingSix end
	if key == "computer" and matchopts.value(s.choice, "computer") == "kid" then note = scene.computerKid end
	ui.text(label, note, t.labelX, t.noteY)
	ui.button("A", "START", t.labelX, t.buttonY)
	ui.button("B", "TEAMS", t.labelX + 96, t.buttonY)
end

-- The scenes/match options this screen makes, on top of `opts` (names, vs);
-- the computer's level only against the Playdate, and with it the rules: KID
-- (engine 0.15) makes a Kid match (opts.rules = "kid", core/matchopts), so PASS +
-- PLAY, which has no COMPUTER row, keeps the standard rules whatever was kept.
function scene.apply(s, opts)
	matchopts.apply(opts, s.choice)
	if s.mode ~= "vs" then opts.computer, opts.rules = nil, nil end
	return opts
end

function scene.update(s)
	local p = s.input
	p:advance()
	local n = #s.rows
	if p:pressed("down") then s.row = s.row % n + 1; s.img = nil
	elseif p:pressed("up") then s.row = (s.row - 2) % n + 1; s.img = nil end
	local d = (p:pressed("right") and 1 or 0) - (p:pressed("left") and 1 or 0)
	if d ~= 0 then
		matchopts.step(s.choice, s.rows[s.row].key, d)
		s.img = nil
	end
	if p:pressed("a") then
		if not s.scripted then playdate.datastore.write(s.choice, scene.tune.key) end
		s.done = true
	elseif p:pressed("b") then
		s.back = true
	end
end

function scene.draw(s)
	if not s.img then
		s.img = gfx.image.new(400, 240, WHITE)
		gfx.pushContext(s.img)
		render(s)
		gfx.popContext()
	end
	s.img:draw(0, 0)
end

function scene.enter()
	playdate.display.setRefreshRate(30)
end

tw.scenes.options = scene
