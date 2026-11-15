-- PLAYERS (docs/PLAYERS.md section 7): the saved players (core/roster,
-- source/players.lua) in the Woodcut look of the Drills board. No board of
-- its own (Jamie, 2026-11-15: build in the existing boards' style).
--
-- Modes:
--   list     the roster on the left (+ NEW PLAYER first, then the players most
--            recently played first, each with their level); the chosen
--            player's figures on the right: games and wins, hit rate, kings,
--            the last ten games as bars. Up/down choose (the list scrolls),
--            A opens (or makes a new player), B the title.
--   player   one player: rows NAME (A: the keyboard), LEVEL (left/right
--            change it, saved at once and logged in the history), GAMES (A:
--            their recent games) and REMOVE (A: the confirm card); on the
--            right the figures and the drill bests. B back to the list.
--   games    their recent games, newest first (date, the other team, won or
--            lost, hits over batons); A opens the game file's score sheet
--            (scenes/sheet, from games/ in the Data folder), B back.
--   confirm  REMOVE <NAME>?: A removes the player and their history file
--            (game files stay), B keeps them.
--   name     scenes/names in mode "player" (a new player, then the LEVEL row
--            of their page; or a rename), refusing a name another player has.
--
-- Each screen is one image redrawn only on a change (s.img = nil).
--
-- opts.scripted (self-tests): the keyboard is scripted (scenes/names).
-- Saves go through tw.players, whose self-test runs use their own files.
import "CoreLibs/graphics"
import "core/tw"
import "core/roster"
import "core/history"
import "core/drills"
import "core/throwplan"
import "render/ui"
import "scenes/names"
import "players"
import "scenes/sheet"
import "scenes/games"

local gfx <const> = playdate.graphics
local roster, history, drills, plan, ui = tw.roster, tw.history, tw.drills, tw.plan, tw.render.ui
local names, players = tw.scenes.names, tw.players
local floor, max = math.floor, math.max
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

tw.scenes = tw.scenes or {}
local scene = {}

scene.tune = {
	panelW = 194,       -- the black list panel
	itemY = 24, rowH = 22, listBottom = 206,
	rightX = 206,       -- the figures
	barsY = 196,        -- the last ten games' bars sit on this line
}

local ROWS <const> = { "NAME", "LEVEL", "GAMES", "REMOVE" }

-- A level's word on screen.
function scene.levelText(l) return string.upper(l or "") end

local function refresh(s)
	s.list = roster.sorted(s.r)
	s.img = nil
end

local function save(s) players.save(s.r) end

local function historyOf(s, key)
	local h = s.hs[key]
	if not h then
		h = players.history(key)
		s.hs[key] = h
	end
	return h
end

-- opts.scripted: the keyboard is scripted; opts.roster: start from this one
-- (self-tests) instead of players.load()
function scene.new(provider, opts)
	opts = opts or {}
	local s = { input = provider, mode = "list", choice = 1, top = 1, row = 1, scripted = opts.scripted,
		img = nil, exit = nil, hs = {} }
	s.r = opts.roster or players.load()
	refresh(s)
	return s
end

-- The player on list row i (row 1 is + NEW PLAYER).
local function chosen(s)
	return s.list[s.choice - 1]
end

local function openPlayer(s, p, row)
	s.mode, s.player, s.row, s.img = "player", p, row or 1, nil
end

local function askName(s, rename)
	local p = s.player
	s.renaming = rename and p or nil
	s.sub = names.new(s.input, "player", { scripted = s.scripted,
		label = rename and "NEW NAME" or "NEW PLAYER", nxt = rename and "THEN BACK" or "THEN THE LEVEL",
		initial = rename and p.name or "",
		check = function(name) return roster.canName(s.r, name, rename and p.key or nil) end })
	s.mode = "name"
	names.enter(s.sub)
end

local function nameDone(s)
	local name = s.sub.list.A
	s.sub = nil
	if s.renaming then
		roster.rename(s.r, s.renaming.key, name)
		save(s)
		refresh(s)
		openPlayer(s, s.renaming, 1)
	else
		local p = roster.add(s.r, name, nil, players.today())
		save(s)
		refresh(s)
		if p then
			for i, q in ipairs(s.list) do if q == p then s.choice = i + 1 end end
			openPlayer(s, p, 2)   -- straight to the level
		else
			s.mode = "list"
		end
	end
	s.renaming = nil
end

local function setLevel(s, dir)
	local p = s.player
	local at = 1
	for i, l in ipairs(plan.LEVELS) do if l == p.level then at = i end end
	local to = plan.LEVELS[at + dir]
	if not to then return end
	local h = historyOf(s, p.key)
	if history.setLevel(s.r, h, p.key, to, players.today()) then
		save(s)
		players.saveHistory(p.key, h)
		s.img = nil
	end
end

function scene.update(s)
	local p = s.input
	if s.mode == "sheet" then
		tw.scenes.sheet.update(s.sheet, false)
		if s.sheet.done then s.mode, s.sheet, s.img = "games", nil, nil end
		return
	end
	if s.mode == "name" then
		names.update(s.sub)
		if s.sub.done then nameDone(s)
		elseif s.sub.exit then
			s.sub = nil
			if s.renaming then openPlayer(s, s.renaming, 1) else s.mode, s.img = "list", nil end
			s.renaming = nil
		end
		return
	end
	p:advance()
	if s.mode == "list" then
		local n = #s.list + 1
		if p:pressed("up") then s.choice = (s.choice - 2) % n + 1; s.img = nil end
		if p:pressed("down") then s.choice = s.choice % n + 1; s.img = nil end
		if p:pressed("a") then
			if s.choice == 1 then askName(s, false) else openPlayer(s, chosen(s), 1) end
		elseif p:pressed("b") then
			s.exit = "title"
		end
	elseif s.mode == "player" then
		if p:pressed("up") then s.row = (s.row - 2) % #ROWS + 1; s.img = nil end
		if p:pressed("down") then s.row = s.row % #ROWS + 1; s.img = nil end
		if ROWS[s.row] == "LEVEL" then
			if p:pressed("left") then setLevel(s, -1) end
			if p:pressed("right") then setLevel(s, 1) end
		end
		if p:pressed("a") then
			if ROWS[s.row] == "NAME" then askName(s, true)
			elseif ROWS[s.row] == "GAMES" then s.mode, s.gi, s.img = "games", 1, nil
			elseif ROWS[s.row] == "REMOVE" then s.mode, s.img = "confirm", nil end
		elseif p:pressed("b") then
			s.mode, s.img = "list", nil
		end
	elseif s.mode == "games" then
		local list = historyOf(s, s.player.key).games
		local n = #list
		if n > 0 and p:pressed("up") then s.gi = (s.gi - 2) % n + 1; s.img = nil end
		if n > 0 and p:pressed("down") then s.gi = s.gi % n + 1; s.img = nil end
		if p:pressed("a") and n > 0 then
			local e = list[n - s.gi + 1]
			local text = e.f and tw.scenes.games.readFile("games/" .. e.f)
			s.sheet = tw.scenes.sheet.new(p, text and tw.scenes.sheet.split(text) or { "(this game file is not on the Playdate)" },
				string.upper(e.team .. " V " .. e.vs), { e.d or "", string.upper(e.res or "") })
			s.mode = "sheet"
		elseif p:pressed("b") then
			s.mode, s.img = "player", nil
		end
	elseif s.mode == "confirm" then
		if p:pressed("a") then
			players.remove(s.r, s.player.key)
			s.hs[s.player.key] = nil
			s.player = nil
			refresh(s)
			s.choice = math.min(s.choice, #s.list + 1)
			s.mode = "list"
		elseif p:pressed("b") then
			s.mode, s.img = "player", nil
		end
	end
end

-- ---------- drawing ----------

local function rail(label, left, right)
	gfx.setColor(BLACK)
	gfx.fillRect(0, 0, 400, 14)
	ui.text(label, left, 6, 2, true)
	if right then ui.text(label, right, 394, 2, true, "right") end
end

-- The figures of player p on the right: name, level, games, hit rate, the
-- last ten games as bars (hits over batons).
local function figures(s, p, withDrills)
	local t = scene.tune
	local big, label = ui.display(16), ui.label()
	local x = t.rightX
	local f32 = ui.display(32)
	local nameFont = (f32:getTextWidth(string.upper(p.name)) <= 394 - x) and f32 or big
	ui.text(nameFont, p.name, x, 24 + ((nameFont == f32) and 0 or 10))
	ui.textDots(label, { "LEVEL " .. scene.levelText(p.level), p.last and ("PLAYED " .. p.last) or "NOT PLAYED YET" }, x, 64)
	local tt = p.totals
	local rate = roster.hitRate(p)
	ui.textDots(label, { tt.games .. (tt.games == 1 and " GAME" or " GAMES"), "WON " .. tt.wins }, x, 82)
	ui.textDots(label, { "HIT RATE " .. (rate and (rate .. "%") or "-"), tt.batons .. " BATONS" }, x, 96)
	ui.textDots(label, { "KINGS " .. tt.kings, "KUBBS IN " .. tt.I }, x, 110)
	gfx.setColor(BLACK)
	local h = historyOf(s, p.key)
	if withDrills then
		local y = 128
		ui.text(label, "DRILL BESTS", x, y)
		local shown = 0
		for _, d in ipairs(drills.list) do
			local rec = h.drills[d.id]
			if rec and shown < 4 then
				shown = shown + 1
				ui.text(label, d.name .. " " .. rec.best .. "/" .. d.of, x, y + shown * 13)
			end
		end
		if shown == 0 then ui.text(label, "NONE YET", x, y + 13) end
		return
	end
	gfx.fillRect(x, 130, 394 - x, 2)
	ui.text(label, "LAST TEN", x, 140)
	local by = t.barsY
	for i, g in ipairs(history.lastGames(h, 10)) do
		local hgt = g.b > 0 and max(2, floor(36 * g.h / g.b)) or 1
		gfx.fillRect(x + (i - 1) * 18, by - hgt, 12, hgt)
		if g.res == "won" then gfx.fillRect(x + (i - 1) * 18 + 4, by + 3, 4, 4) end
	end
	gfx.fillRect(x - 2, by, 394 - x + 2, 1)
	ui.textDots(label, { "BARS: HITS", "DOT: WON" }, x, by + 10)
end

local function renderList(s)
	local t = scene.tune
	local big, label = ui.display(16), ui.label()
	gfx.clear(WHITE)
	gfx.setColor(BLACK)
	gfx.fillRect(0, 0, t.panelW, 240)
	rail(label, "PLAYERS", #s.r.players .. " OF " .. roster.tune.max)
	local visible = floor((t.listBottom - t.itemY) / t.rowH)
	if s.choice < s.top then s.top = s.choice end
	if s.choice >= s.top + visible then s.top = s.choice - visible + 1 end
	for i = s.top, math.min(#s.list + 1, s.top + visible - 1) do
		local y = t.itemY + (i - s.top) * t.rowH
		local on = i == s.choice
		if on then
			gfx.setColor(WHITE)
			gfx.fillRect(8, y - 3, t.panelW - 16, t.rowH - 2)
		end
		if i == 1 then
			ui.text(big, "+ NEW PLAYER", 16, y, not on)
		else
			local p = s.list[i - 1]
			-- the level right-aligned; a name too wide to clear it goes in the label font
			local lv = scene.levelText(p.level)
			local room = t.panelW - 14 - label:getTextWidth(lv) - 8 - 16
			local f = (big:getTextWidth(string.upper(p.name)) <= room) and big or label
			ui.text(f, p.name, 16, y + ((f == big) and 0 or 3), not on)
			ui.text(label, lv, t.panelW - 14, y + 3, not on, "right")
		end
	end
	ui.button("A", s.choice == 1 and "NEW" or "OPEN", 16, 216, true)
	ui.button("B", "TITLE", 96, 216, true)
	local p = chosen(s)
	if p then
		figures(s, p)
	else
		local x = t.rightX
		ui.text(big, "NEW PLAYER", x, 34)
		for i, line in ipairs { "A NAME, TYPED ONCE", "WITH A THROW LEVEL", "THEN PICK THEM", "FOR EVERY MATCH" } do
			ui.text(label, line, x, 64 + (i - 1) * 14)
		end
		if #s.r.players >= roster.tune.max then ui.text(label, "THE PLAYERS ARE FULL", x, 130) end
	end
end

local function renderPlayer(s)
	local t = scene.tune
	local big, label = ui.display(16), ui.label()
	gfx.clear(WHITE)
	gfx.setColor(BLACK)
	gfx.fillRect(0, 0, t.panelW, 240)
	rail(label, "PLAYERS", "GAME FILE ID " .. string.upper(s.player.id))
	local p = s.player
	for i, row in ipairs(ROWS) do
		local y = t.itemY + (i - 1) * 40
		local on = i == s.row
		if on then
			gfx.setColor(WHITE)
			gfx.fillRect(8, y - 3, t.panelW - 16, 37)
		end
		ui.text(label, row, 16, y, not on)
		local value
		if row == "NAME" then value = p.name
		elseif row == "LEVEL" then value = scene.levelText(p.level)
		elseif row == "GAMES" then value = (#historyOf(s, p.key).games) .. " RECENT"
		else value = "REMOVE " .. p.name end
		local f = (big:getTextWidth(string.upper(value)) <= t.panelW - 48) and big or label
		local vx = row == "LEVEL" and 30 or 16
		local w = ui.text(f, value, vx, y + 16, not on)
		if row == "LEVEL" then
			-- arrows either side of the level (the display face has no < >)
			gfx.setColor(on and BLACK or WHITE)
			gfx.fillTriangle(24, y + 17, 24, y + 31, 17, y + 24)
			gfx.fillTriangle(vx + w + 6, y + 17, vx + w + 6, y + 31, vx + w + 13, y + 24)
		end
	end
	local hint = ({ NAME = "A RENAME", LEVEL = "LEFT, RIGHT: THE LEVEL", GAMES = "A THEIR GAMES",
		REMOVE = "A REMOVE" })[ROWS[s.row]]
	ui.text(label, hint, 16, 190, true)
	ui.button("B", "BACK", 16, 216, true)
	figures(s, p, true)
end

local function renderGames(s)
	local t = scene.tune
	local big, label = ui.display(16), ui.label()
	gfx.clear(WHITE)
	gfx.setColor(BLACK)
	gfx.fillRect(0, 0, 400, 240)
	rail(label, string.upper(s.player.name) .. ": RECENT GAMES", "NEWEST FIRST")
	local list = historyOf(s, s.player.key).games
	local n = #list
	if n == 0 then ui.text(label, "NO GAMES YET", 16, 40, true) end
	local visible = 8
	local top = math.max(1, math.min(s.gi - 3, n - visible + 1))
	for i = top, math.min(n, top + visible - 1) do
		local e = list[n - i + 1]
		local y = 24 + (i - top) * 22
		local on = i == s.gi
		if on then
			gfx.setColor(WHITE)
			gfx.fillRect(8, y - 3, 384, 20)
		end
		ui.text(label, (e.d or ""):sub(1, 10), 16, y + 1, not on)
		ui.text(big, ((e.res == "won") and "WON V " or "LOST V ") .. e.vs, 110, y, not on)
		ui.text(label, (e.h or 0) .. "/" .. (e.b or 0) .. " HITS", 386, y + 1, not on, "right")
	end
	if n > 0 then ui.button("A", "SCORESHEET", 16, 216, true) end
	ui.button("B", "BACK", 150, 216, true)
end

local function renderConfirm(s)
	local big, label = ui.display(32), ui.label()
	gfx.clear(BLACK)
	ui.text(label, "PLAYERS", 16, 18, true)
	local q = "REMOVE " .. string.upper(s.player.name) .. "?"
	local f = (big:getTextWidth(q) <= 368) and big or ui.display(16)
	ui.text(f, q, 16, 60, true)
	ui.text(label, "THEIR HISTORY AND DRILL BESTS GO", 16, 120, true)
	ui.text(label, "THE GAME FILES STAY IN GAMES", 16, 136, true)
	ui.button("A", "REMOVE", 16, 216, true)
	ui.button("B", "KEEP", 120, 216, true)
end

function scene.draw(s)
	if s.mode == "name" then return names.draw(s.sub) end
	if s.mode == "sheet" then return tw.scenes.sheet.draw(s.sheet) end
	if not s.img then
		s.img = gfx.image.new(400, 240, WHITE)
		gfx.pushContext(s.img)
		if s.mode == "list" then renderList(s)
		elseif s.mode == "player" then renderPlayer(s)
		elseif s.mode == "games" then renderGames(s)
		else renderConfirm(s) end
		gfx.popContext()
	end
	s.img:draw(0, 0)
end

function scene.enter()
	playdate.display.setRefreshRate(30)
end

tw.scenes.players = scene
