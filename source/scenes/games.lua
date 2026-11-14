-- The games list and score sheets (the Games board): every finished game in
-- the Data folder's games/, newest first. A row: the date, the two teams with
-- a crown on the winner, turns and minutes; the chosen row is black. Under
-- the list, the chosen game's baton hit rates and the baton the king fell
-- to. The crank or up/down moves through it, A shows the game's score sheet
-- (the game file as written, the crank or up/down scrolls it, B back), B
-- goes back to the title. Reached from the title's System Menu ("Games").
--
-- Game files are read and parsed (core/gamefile) only as their rows come on
-- screen; each screen is one image redrawn only when the choice or the
-- scroll changes.
import "CoreLibs/graphics"
import "core/tw"
import "core/gamefile"
import "render/ui"

local gfx <const> = playdate.graphics
local gamefile, ui = tw.gamefile, tw.render.ui
local floor, max, min = math.floor, math.max, math.min
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

tw.scenes = tw.scenes or {}
local scene = {}

scene.tune = {
	rowH = 35,          -- px a row
	rows = 5,           -- rows on screen
	listTop = 14,       -- under the rail
	footY = 190,        -- the black footer
	crankRow = 30,      -- degrees of crank a row
	lineH = 14,         -- px a score sheet line
	crankPx = 1.2,      -- px of score sheet a degree of crank
	nameX = 76,         -- px where the teams start (after the widest date)
	statGap = 10,       -- px kept clear between the teams and the turns and minutes
	dir = "games",
}

-- the game files, newest first (names start with the date and time)
local function listFiles(dir)
	local out = {}
	for _, f in ipairs(playdate.file.listFiles(dir) or {}) do
		if f:match("%.txt$") then out[#out + 1] = f end
	end
	table.sort(out, function(a, b) return a > b end)
	return out
end

local function readFile(path)
	local size = playdate.file.getSize(path)
	if not size or size == 0 then return nil end
	local f = playdate.file.open(path, playdate.file.kFileRead)
	if not f then return nil end
	local text = f:read(size)
	f:close()
	return text
end

-- opts.dir: the folder to read (self-tests point it at their own)
function scene.new(provider, opts)
	opts = opts or {}
	local dir = opts.dir or scene.tune.dir
	return { input = provider, dir = dir, files = listFiles(dir), cache = {}, sel = 1, top = 1,
		view = "list", sheetY = 0, crankAcc = 0, img = nil, exit = nil }
end

-- the chosen file's summary (parsed once)
local function summary(s, i)
	local c = s.cache[i]
	if c == nil then
		c = gamefile.parse(readFile(s.dir .. "/" .. s.files[i])) or false
		s.cache[i] = c
	end
	return c or nil
end
scene.summary = summary

local function crown(x, y, white)
	gfx.setColor(white and WHITE or BLACK)
	gfx.fillPolygon(x, y + 8, x, y + 1, x + 3, y + 4, x + 6, y, x + 9, y + 4, x + 12, y + 1, x + 12, y + 8)
end

local function rail(left, right)
	local f = ui.label()
	gfx.setColor(BLACK)
	gfx.fillRect(0, 0, 400, 14)
	ui.text(f, left, 6, 2, true)
	if right then ui.textDots(f, right, 394, 2, true, "right") end
end

local function renderList(s)
	local t = scene.tune
	local label, big = ui.label(), ui.display(16)
	gfx.clear(WHITE)
	local n = #s.files
	-- the chosen game's surface, from its file
	local chosen = n > 0 and summary(s, s.sel)
	local surf = chosen and chosen.headers and chosen.headers.Surface or "Grass"
	rail("GAMES", n > 0 and { s.sel .. " OF " .. n, string.upper(surf) } or nil)
	if n == 0 then
		ui.text(big, "NO GAMES YET", 200, 80, false, "center")
		ui.text(label, "A FINISHED MATCH IS SAVED HERE", 200, 110, false, "center")
	end
	for r = 0, t.rows - 1 do
		local i = s.top + r
		if i > n then break end
		local y = t.listTop + r * t.rowH
		local chosen = (i == s.sel)
		if chosen then
			gfx.setColor(BLACK)
			gfx.fillRect(0, y, 388, t.rowH)
		elseif r < t.rows - 1 and i < n then
			gfx.setColor(BLACK)
			gfx.fillRect(0, y + t.rowH - 1, 388, 1)
		end
		local g = summary(s, i)
		if g then
			local ty = y + floor((t.rowH - 16) / 2)
			ui.text(label, g.date, 10, y + floor((t.rowH - 12) / 2), chosen)
			-- the names get what the turns and minutes leave of the row: those on
			-- one line if the names fit at cap 16, else on two lines, and the names
			-- in the label font if they still do not fit (clipped as a last resort)
			local stats = { g.turns .. " TURNS", g.minutes .. " MIN" }
			local oneW = label:getTextWidth(stats[1]) + label:getTextWidth(stats[2]) + 10
			local twoW = max(label:getTextWidth(stats[1]), label:getTextWidth(stats[2]))
			local fixed = 10 + label:getTextWidth("V") + (g.winner and 16 or 0)
			local bigW = big:getTextWidth(string.upper(g.a)) + big:getTextWidth(string.upper(g.b)) + fixed
			local room = 380 - t.statGap - t.nameX
			local f, fy, stacked = big, ty, false
			if bigW > room - oneW then
				stacked = true
				if bigW > room - twoW then f, fy = label, ty + 3 end
			end
			if stacked then
				ui.text(label, stats[1], 380, y + 4, chosen, "right")
				ui.text(label, stats[2], 380, y + t.rowH - 17, chosen, "right")
			else
				ui.textDots(label, stats, 380, y + floor((t.rowH - 12) / 2), chosen, "right")
			end
			gfx.setClipRect(0, y, 380 - (stacked and twoW or oneW) - t.statGap, t.rowH)
			local x = t.nameX
			if g.winner == "A" then crown(x, ty - 2, chosen); x = x + 16 end
			x = x + ui.text(f, g.a, x, fy, chosen)
			x = x + 5 + ui.text(label, "V", x + 5, ty + 3, chosen) + 5
			if g.winner == "B" then crown(x, ty - 2, chosen); x = x + 16 end
			ui.text(f, g.b, x, fy, chosen)
			gfx.clearClipRect()
		else
			ui.text(label, s.files[i], 10, y + 10, chosen)
		end
	end
	-- the scroll bar
	if n > t.rows then
		local h = t.footY - t.listTop
		gfx.setColor(BLACK)
		gfx.drawRect(392, t.listTop + 2, 6, h - 4)
		local bh = max(8, floor((h - 8) * t.rows / n))
		local by = t.listTop + 4 + floor((h - 8 - bh) * (s.top - 1) / (n - t.rows))
		gfx.fillRect(394, by, 2, bh)
	end
	-- the footer: the chosen game's hit rates and king
	gfx.setColor(BLACK)
	gfx.fillRect(0, t.footY, 400, 240 - t.footY)
	local g = n > 0 and summary(s, s.sel)
	if g then
		local parts = {}
		local ra, rb = gamefile.rate(g, "A"), gamefile.rate(g, "B")
		if ra then parts[#parts + 1] = string.upper(g.a) .. " " .. ra .. "% HITS" end
		if rb then parts[#parts + 1] = string.upper(g.b) .. " " .. rb .. "%" end
		if g.kingBaton then parts[#parts + 1] = "KING ON BATON " .. g.kingBaton end
		if #parts > 0 then ui.textDots(label, parts, 10, t.footY + 7, true) end
		ui.button("A", "SCORESHEET", 10, t.footY + 24, true)
	end
	ui.button("B", "TITLE", 140, t.footY + 24, true)
	if n > 1 then ui.text(label, "CRANK TO SCROLL", 390, t.footY + 27, true, "right") end
end

local function renderSheet(s)
	local t = scene.tune
	local g = summary(s, s.sel)
	local label = ui.label()
	gfx.clear(WHITE)
	if not s.sheetImg then
		-- long lines wrap at a space, the rest indented (the sheet only scrolls
		-- up and down)
		local lines = {}
		local maxW = 384
		for _, line in ipairs(g and g.lines or { "(this game file could not be read)" }) do
			local cur, indent = "", ""
			for word in line:gmatch("%S+") do
				local try = (cur == "") and (indent .. word) or (cur .. " " .. word)
				if cur ~= "" and label:getTextWidth(try) > maxW then
					lines[#lines + 1] = cur
					cur, indent = "    " .. word, "    "
				else
					cur = try
				end
			end
			lines[#lines + 1] = cur
		end
		local h = 8 + #lines * t.lineH
		local img = gfx.image.new(400, h, WHITE)
		gfx.pushContext(img)
		gfx.setImageDrawMode(gfx.kDrawModeFillBlack)
		for i, line in ipairs(lines) do label:drawText(line, 8, 4 + (i - 1) * t.lineH) end
		gfx.setImageDrawMode(gfx.kDrawModeCopy)
		gfx.popContext()
		s.sheetImg, s.sheetH = img, h
	end
	s.sheetImg:draw(0, 14 - s.sheetY)
	rail(g and (string.upper(g.a) .. " V " .. string.upper(g.b)) or "SCORESHEET", g and { g.date, g.turns .. " TURNS" } or nil)
	gfx.setColor(BLACK)
	gfx.fillRect(0, 214, 400, 26)
	ui.button("B", "BACK", 10, 217, true)
	ui.text(label, "CRANK TO SCROLL", 390, 220, true, "right")
end

local function moveTo(s, sel)
	local n, rows = #s.files, scene.tune.rows
	sel = max(1, min(n, sel))
	if sel ~= s.sel then
		s.sel = sel
		if sel < s.top then s.top = sel elseif sel > s.top + rows - 1 then s.top = sel - rows + 1 end
		s.img = nil
	end
end
scene.moveTo = moveTo

function scene.update(s)
	local p = s.input
	p:advance()
	local t = scene.tune
	if s.view == "list" then
		local step = 0
		if p:pressed("down") then step = 1 elseif p:pressed("up") then step = -1 end
		s.crankAcc = s.crankAcc + p:crank()
		while s.crankAcc >= t.crankRow do s.crankAcc = s.crankAcc - t.crankRow; step = step + 1 end
		while s.crankAcc <= -t.crankRow do s.crankAcc = s.crankAcc + t.crankRow; step = step - 1 end
		if step ~= 0 and #s.files > 0 then moveTo(s, s.sel + step) end
		if p:pressed("a") and #s.files > 0 then
			s.view, s.sheetY, s.sheetImg, s.img = "sheet", 0, nil, nil
		elseif p:pressed("b") then
			s.exit = "title"
		end
	else
		local dy = p:crank() * t.crankPx
		if p:held("down") then dy = dy + 6 elseif p:held("up") then dy = dy - 6 end
		if dy ~= 0 then
			local maxY = max(0, (s.sheetH or 0) - 200)
			local y = max(0, min(maxY, s.sheetY + dy))
			if y ~= s.sheetY then s.sheetY = y; s.img = nil end
		end
		if p:pressed("b") then s.view, s.img = "list", nil end
	end
end

function scene.draw(s)
	if not s.img then
		s.img = gfx.image.new(400, 240, WHITE)
		gfx.pushContext(s.img)
		if s.view == "list" then renderList(s) else renderSheet(s) end
		gfx.popContext()
	end
	s.img:draw(0, 0)
end

function scene.enter()
	playdate.display.setRefreshRate(30)
end

tw.scenes.games = scene
