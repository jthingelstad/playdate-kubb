-- TEAMS (docs/PLAYERS.md section 4): build the two teams from the saved
-- players before a match (PASS + PLAY), or the player's team against the
-- Playdate (VS PLAYDATE). Pure state in core/lineup; the Woodcut look of
-- the Drills board, no board of its own.
--
-- Three columns: Team A, the bench (START, + PLAYER, + GUEST, then the
-- saved players on no team, most recently played first), Team B (the
-- Playdate against VS PLAYDATE). Each team column starts with its name.
--   up/down          move in a column
--   left/right       on a player: send them toward that side (bench ->
--                    team, team -> bench); anywhere else: change column
--   hold A + up/down on a team's player: move them up or down the order
--                    (the order is who throws first, core/order)
--   A                START: the match options (once both teams have a
--                    player); + PLAYER: the Names screen (a new saved player,
--                    onto the bench); + GUEST: the Names screen (this match
--                    only, not saved); a team's name: the Names screen, a
--                    generated team name (scenes/names)
--   B                back to the title
-- The lineup is kept (datastore "teams", per mode; guests are not) and
-- offered again; a kept team name typed on an older build stays as it is until it is
-- renamed (the owner's decision, kubb-engine docs/NAMES.md 10.2). The screen is one
-- image redrawn only on a change.
--
-- opts.scripted: the Names screen is scripted (scenes/names), nothing read from
-- or written to the "teams" file; opts.roster: the roster to use.
import "CoreLibs/graphics"
import "core/tw"
import "core/roster"
import "core/lineup"
import "core/notation"
import "render/ui"
import "scenes/names"
import "players"

local gfx <const> = playdate.graphics
local roster, lineup, ui = tw.roster, tw.lineup, tw.render.ui
local names, players = tw.scenes.names, tw.players
local floor = math.floor
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

tw.scenes = tw.scenes or {}
local scene = {}

scene.tune = {
	colW = 133,          -- three columns across 400 px
	headY = 20,          -- the column heads (team names, BENCH)
	listY = 44, rowH = 19, listBottom = 208,
	key = "teams",       -- the datastore file
}

local WHY = { full = "SIX A SIDE", taken = "ALREADY ON A TEAM", vs = "THE PLAYDATE PLAYS ALONE" }

local function benchRows(s)
	local rows = { { kind = "start" }, { kind = "new" }, { kind = "guest" } }
	for _, p in ipairs(roster.sorted(s.r)) do
		if not lineup.find(s.L, lineup.entry(p)) then rows[#rows + 1] = { kind = "player", entry = lineup.entry(p) } end
	end
	for _, g in ipairs(s.guests) do
		if not lineup.find(s.L, g) then rows[#rows + 1] = { kind = "player", entry = g } end
	end
	return rows
end

-- Rows of a column: a team's name row then its players; the bench's rows.
local function rows(s, col)
	if col == "M" then return benchRows(s) end
	local out = { { kind = "name" } }
	for _, e in ipairs(s.L[col]) do out[#out + 1] = { kind = "player", entry = e } end
	return out
end

local function changed(s)
	s.img = nil
	local n = #rows(s, s.col)
	if s.row > n then s.row = n end
	if s.row < 1 then s.row = 1 end
end

local function keep(s)
	if s.scripted then return end
	local d = playdate.datastore.read(players.fileKey(scene.tune.key)) or {}
	d[s.mode] = lineup.pack(s.L)
	playdate.datastore.write(d, players.fileKey(scene.tune.key))
end

-- mode "match" (PASS + PLAY) or "vs" (VS PLAYDATE)
function scene.new(provider, mode, opts)
	opts = opts or {}
	local s = { input = provider, mode = mode, scripted = opts.scripted, col = "M", row = 1, img = nil,
		exit = nil, done = false, guests = {}, flash = nil }
	s.r = opts.roster or players.load()
	local kept = (not s.scripted) and playdate.datastore.read(players.fileKey(scene.tune.key)) or nil
	s.L = lineup.unpack(kept and kept[mode], s.r, mode == "vs")
	-- the cursor on the first saved player when nobody is on a team yet
	if not lineup.ready(s.L) and #rows(s, "M") > 3 then s.row = 4 end
	return s
end

local function askName(s, what, side)
	s.asking, s.askSide = what, side
	local label = ({ new = "NEW PLAYER", guest = "GUEST", team = "TEAM NAME" })[what]
	local initial = what == "team" and s.L.names[side] or nil
	s.sub = names.new(s.input, "player", { scripted = s.scripted, label = label, nxt = "THEN BACK TO TEAMS",
		initial = initial, kind = (what == "team") and "team" or "player",
		check = (what ~= "team") and function(name)
			if what == "guest" then
				local n, why = roster.canName(s.r, name)
				if not n and why == "full" then return name end   -- a guest is not saved: the cap is not theirs
				if n and lineup.find(s.L, lineup.guest(n)) then return nil, "taken" end
				for _, g in ipairs(s.guests) do
					if tw.notation.baseId(g.name) == tw.notation.baseId(n or "") then return nil, "taken" end
				end
				return n, why
			end
			return roster.canName(s.r, name)
		end or nil })
	names.enter(s.sub)
end

local function nameDone(s)
	local name = s.sub.list.A
	local what, side = s.asking, s.askSide
	s.sub, s.asking = nil, nil
	if what == "team" then
		lineup.setName(s.L, side, name)
		keep(s)
	elseif what == "new" then
		local p = roster.add(s.r, name, nil, players.today())
		if p then
			players.save(s.r)
			-- onto an empty team at once (lineup.seatNew)
			if lineup.seatNew(s.L, lineup.entry(p)) then keep(s) end
		end
	elseif what == "guest" then
		local g = lineup.guest(name)
		s.guests[#s.guests + 1] = g
		lineup.seatNew(s.L, g)
	end
	changed(s)
end

local COLS <const> = { "A", "M", "B" }
local function colIndex(c) for i, x in ipairs(COLS) do if x == c then return i end end end

local function moveCol(s, dir)
	local i = colIndex(s.col) + dir
	if i < 1 or i > 3 then return end
	if COLS[i] == "B" and s.L.vs then return end
	s.col = COLS[i]
	changed(s)
end

function scene.update(s)
	if s.sub then
		names.update(s.sub)
		if s.sub.done then nameDone(s)
		elseif s.sub.exit then s.sub, s.asking = nil, nil; changed(s) end
		return
	end
	local p = s.input
	p:advance()
	local list = rows(s, s.col)
	local r = list[s.row]
	local n = #list
	-- hold A + up/down: move a team's player up or down the order
	if p:held("a") and s.col ~= "M" and r and r.kind == "player" and (p:pressed("up") or p:pressed("down")) then
		local i = s.row - 1
		local j = lineup.move(s.L, s.col, i, p:pressed("up") and -1 or 1)
		s.row = j + 1
		keep(s)
		changed(s)
		return
	end
	if p:pressed("up") then s.row = (s.row - 2) % n + 1; s.img = nil end
	if p:pressed("down") then s.row = s.row % n + 1; s.img = nil end
	local dir = p:pressed("left") and -1 or (p:pressed("right") and 1 or 0)
	if dir ~= 0 then
		s.flash = nil
		if r and r.kind == "player" then
			if s.col == "M" then
				local side = dir < 0 and "A" or "B"
				local ok, why = lineup.add(s.L, side, r.entry)
				if not ok then s.flash = WHY[why] end
				keep(s)
				changed(s)
			elseif (s.col == "A" and dir > 0) or (s.col == "B" and dir < 0) then
				lineup.remove(s.L, s.col, s.row - 1)
				keep(s)
				changed(s)
			end
		else
			moveCol(s, dir)
		end
	end
	if p:pressed("a") and r then
		if r.kind == "start" then
			if lineup.ready(s.L) then
				keep(s)
				s.done = true
			else
				s.flash = s.L.vs and "PUT YOURSELF ON TEAM A" or "A PLAYER ON EACH TEAM FIRST"
				s.img = nil
			end
		elseif r.kind == "new" then askName(s, "new")
		elseif r.kind == "guest" then askName(s, "guest")
		elseif r.kind == "name" and not (s.L.vs and s.col == "B") then askName(s, "team", s.col) end
	elseif p:pressed("b") then
		s.exit = "title"
	end
end

-- core/match's teams for the lineup built.
function scene.teams(s) return lineup.teams(s.L) end

-- ---------- drawing ----------

local function fitText(font, small, text, w)
	return (font:getTextWidth(string.upper(text)) <= w) and font or small
end

-- A name for a column `w` px wide: as it is, or with its first word cut to its
-- initial ("N. REDWOOD"), or without its "The", when even the label face is too wide (generated names run
-- to 16 letters; the widest is about 140 px in the label face, the column 133). A single
-- word (a name typed on an older build) is never cut.
function scene.fitName(text, w)
	local label = ui.label()
	if label:getTextWidth(string.upper(text)) <= w then return text end
	-- (a player's row starts with their place in the order: "2 Agreeable Ginkgo")
	local n, name = text:match("^(%d+ )(.+)$")
	n, name = n or "", name or text
	local first, rest = name:match("^(%S+) (.+)$")
	if first == "The" then return n .. rest end
	if first then return n .. first:sub(1, 1) .. ". " .. rest end
	return text
end

local function render(s)
	local t = scene.tune
	local big, label = ui.display(16), ui.label()
	gfx.clear(WHITE)
	gfx.setColor(BLACK)
	gfx.fillRect(0, 0, 400, 14)
	ui.text(label, s.mode == "vs" and "VS PLAYDATE" or "PASS + PLAY", 6, 2, true)
	ui.text(label, "HOLD A + UP/DOWN: THROW ORDER", 394, 2, true, "right")
	-- the bench, black
	gfx.fillRect(t.colW, 14, t.colW + 1, 226)
	ui.text(label, "BENCH", t.colW + 8, t.headY + 3, true)
	gfx.setColor(WHITE)
	gfx.fillRect(t.colW + 8, t.headY + 19, t.colW - 16, 2)
	for ci, col in ipairs(COLS) do
		local x0 = (ci - 1) * t.colW
		local onBlack = col == "M"
		local list = rows(s, col)
		local visible = floor((t.listBottom - t.listY) / t.rowH) + 1
		local top = 1
		if col == s.col and s.row > visible then top = s.row - visible + 1 end
		for i = top, math.min(#list, top + visible - 1) do
			local row = list[i]
			local y = (row.kind == "name") and t.headY or (t.listY + (i - top - ((col == "M") and 0 or 1)) * t.rowH)
			local on = (col == s.col and i == s.row)
			local ink = onBlack
			if on then
				gfx.setColor(onBlack and WHITE or BLACK)
				local by, bh = ui.capBox(y, 2)   -- centred on the caps (it cut their foot)
				gfx.fillRect(x0 + 4, by, t.colW - 8, bh)
				ink = not onBlack
			end
			local text, right
			if row.kind == "start" then text = "START"
			elseif row.kind == "new" then text = "+ PLAYER"
			elseif row.kind == "guest" then text = "+ GUEST"
			elseif row.kind == "name" then text = lineup.teamName(s.L, col)
			else
				text = row.entry.name
				-- (a person's level no longer shows: since engine 0.13 it names only the computer)
				right = row.entry.guest and "GUEST" or nil
				if col ~= "M" then text = (i - 1) .. " " .. text end
			end
			local room = t.colW - (right and 44 or 14)
			local f = fitText(big, label, text, room)
			if f == label then text = scene.fitName(text, room) end
			ui.text(f, text, x0 + 8, y + ((f == big) and 0 or 3), ink)
			if right then ui.text(label, right, x0 + t.colW - 8, y + 3, ink, "right") end
			if row.kind == "name" and not on then
				gfx.setColor(BLACK)
				gfx.fillRect(x0 + 8, y + 19, t.colW - 16, 2)
			end
		end
		if col == "B" and s.L.vs then
			ui.text(label, "THE PLAYDATE", x0 + 8, t.listY, false)
			ui.text(label, "THROWS FOR ITSELF", x0 + 8, t.listY + 14, false)
		end
		if col ~= "M" and #s.L[col] == 0 and not (col == "B" and s.L.vs) then
			ui.text(label, col == "A" and "< SEND PLAYERS" or "SEND PLAYERS >", x0 + 8, t.listY, false)
		end
	end
	if s.flash then ui.text(label, s.flash, 200, 220, true, "center")
	else
		ui.button("B", "TITLE", t.colW + 8, 218, true)
	end
end

function scene.draw(s)
	if s.sub then return names.draw(s.sub) end
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

tw.scenes.teams = scene
