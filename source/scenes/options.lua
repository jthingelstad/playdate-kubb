-- The match options (Jamie, 2026-11-14): after the names, before every match
-- (PASS + PLAY and VS PLAYDATE): the surface, the opening and who stands the
-- thrown-in kubbs up. Rows from core/matchopts; up/down choose a row,
-- left/right change its value, A starts the match, B goes back to the names.
-- The choice is kept (playdate.datastore "matchopts") and offered next time.
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
	top = 30,            -- y of the first row
	rowH = 44,           -- px a row
	labelX = 16,         -- the row's label
	valueX = 150,        -- the value (display 16), between arrows
	arrowGap = 10,
	noteY = 168,         -- the chosen row's line of explanation
	buttonY = 214,
}

-- what each row is for, under the rows
scene.notes = {
	surface = "THE GROUND: GRASS HOLDS, SAND STOPS, SNOW SLIDES",
	opening = "2-4-6: TEAM A OPENS WITH 2, B WITH 4, THEN 6",
	raising = "WHO STANDS UP THE KUBBS THROWN IN",
}
scene.openingSix = "SIX: SIX BATONS A TURN FROM THE START"

-- mode: "match" (PASS + PLAY) or "vs" (VS PLAYDATE). opts.scripted: nothing
-- read or saved (self-tests).
function scene.new(provider, mode, opts)
	opts = opts or {}
	local s = { input = provider, mode = mode, row = 1, img = nil, done = false, back = false,
		scripted = opts.scripted }
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
	for i, row in ipairs(matchopts.list) do
		local y = t.top + (i - 1) * t.rowH
		local chosen = (i == s.row)
		if chosen then
			gfx.setColor(BLACK)
			gfx.fillRect(0, y, 400, t.rowH - 6)
		end
		ui.text(label, row.label, t.labelX, y + 14, chosen)
		local value = matchopts.shown(s.choice, row.key)
		local f = (d16:getTextWidth(value) <= 400 - t.valueX - 40) and d16 or label
		local vy = y + ((f == d16) and 10 or 14)
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
	local key = matchopts.list[s.row].key
	local note = scene.notes[key]
	if key == "opening" and matchopts.value(s.choice, "opening") == "six" then note = scene.openingSix end
	ui.text(label, note, t.labelX, t.noteY)
	ui.button("A", "START", t.labelX, t.buttonY)
	ui.button("B", "NAMES", t.labelX + 96, t.buttonY)
end

-- The scenes/match options this screen makes, on top of `opts` (names, vs).
function scene.apply(s, opts)
	return matchopts.apply(opts, s.choice)
end

function scene.update(s)
	local p = s.input
	p:advance()
	local n = #matchopts.list
	if p:pressed("down") then s.row = s.row % n + 1; s.img = nil
	elseif p:pressed("up") then s.row = (s.row - 2) % n + 1; s.img = nil end
	local d = (p:pressed("right") and 1 or 0) - (p:pressed("left") and 1 or 0)
	if d ~= 0 then
		matchopts.step(s.choice, matchopts.list[s.row].key, d)
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
