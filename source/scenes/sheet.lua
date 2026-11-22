-- A score sheet on screen: a game file's lines, wrapped to the screen, under
-- a rail (the teams on the left, details on the right), scrolled by the crank
-- or up/down; B is back. The games list shows a finished game's file with it
-- (scenes/games) and a match its own game so far (scenes/match, System Menu
-- "Match: sheet"). The text is drawn once into a tall image and each screen
-- is one image redrawn only when the scroll changes.
import "CoreLibs/graphics"
import "core/tw"
import "core/gamefile"
import "render/ui"

local gfx <const> = playdate.graphics
local ui = tw.render.ui
local max, min = math.max, math.min
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

tw.scenes = tw.scenes or {}
local sheet = {}

sheet.tune = {
	lineH = 14,      -- px a score sheet line
	crankPx = 1.2,   -- px of score sheet a degree of crank
	held = 6,        -- px a frame while up or down is held
	maxW = 384,      -- px a line may run before it wraps
}

-- lines: the game file's lines; title: the rail's left text; right: a list of
-- strings for the rail's right (dots between), or nil. atEnd: open scrolled
-- to the last line (a match in progress: its latest turns).
function sheet.new(provider, lines, title, right, atEnd)
	return { input = provider, lines = lines, title = title, right = right, y = 0,
		atEnd = atEnd, textImg = nil, textH = 0, img = nil, done = false }
end

-- The game file's text as lines (a trailing newline makes no empty last line).
-- Position lines (Planet Kubb Notation 2's `@a`, `*b` and the rest, engine 0.13.1)
-- are left out, as the games list's gamefile.parse leaves them: the file keeps
-- them, and on screen one would be a blank line (gamefile.shown).
function sheet.split(text)
	local out = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		if not tw.gamefile.isPosition(line) then out[#out + 1] = line end
	end
	if out[#out] == "" then out[#out] = nil end
	return out
end

-- The rail's left text and right parts when both fit 400 px; two long team names
-- (generated names run to 16 letters) first lose their first words to initials
-- ("R. HAMMOCKS V W. TOWERS"), then the right side goes.
local function fitRail(label, left, right)
	local function rightW()
		if not right or #right == 0 then return 0 end
		local w = 0
		for _, p in ipairs(right) do w = w + label:getTextWidth(string.upper(p)) + 8 end
		return w
	end
	local room = 400 - 12 - 12
	if label:getTextWidth(string.upper(left)) + rightW() <= room then return left, right end
	local a, b = left:match("^(.-) V (.+)$")
	if a then
		local function cut(n)
			local first, rest = n:match("^(%S+) (.+)$")
			if first and first ~= "THE" and first ~= "The" then return first:sub(1, 1) .. ". " .. rest end
			return n
		end
		left = cut(a) .. " V " .. cut(b)
	end
	if label:getTextWidth(string.upper(left)) + rightW() <= room then return left, right end
	return left, nil
end

local function rail(left, right)
	local label = ui.label()
	left, right = fitRail(label, left, right)
	gfx.setColor(BLACK)
	gfx.fillRect(0, 0, 400, 14)
	ui.text(label, left, 6, 2, true)
	if right and #right > 0 then ui.textDots(label, right, 394, 2, true, "right") end
end
sheet.rail = rail

-- the text, wrapped at a space with the rest of a long line indented (the
-- sheet only scrolls up and down), drawn once; positions on the pitch are
-- left out (gamefile.shown): the file keeps them
local function textImage(s)
	local t = sheet.tune
	local label = ui.label()
	local lines = {}
	for _, line in ipairs(s.lines) do
		local cur, indent = "", ""
		for word in tw.gamefile.shown(line):gmatch("%S+") do
			local try = (cur == "") and (indent .. word) or (cur .. " " .. word)
			if cur ~= "" and label:getTextWidth(try) > t.maxW then
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
	s.textImg, s.textH = img, h
	if s.atEnd then s.y, s.atEnd = max(0, h - 200), nil end
end

-- Draw the sheet into the current context (a 400 x 240 screen).
function sheet.render(s)
	if not s.textImg then textImage(s) end
	gfx.clear(WHITE)
	s.textImg:draw(0, 14 - s.y)
	rail(s.title, s.right)
	gfx.setColor(BLACK)
	gfx.fillRect(0, 214, 400, 26)
	ui.button("B", "BACK", 10, 217, true)
	ui.text(ui.label(), "CRANK TO SCROLL", 390, 220, true, "right")
end

-- Scroll by the crank and up/down; B sets s.done. advance: read the provider
-- here (false when the caller already advanced it this frame).
function sheet.update(s, advance)
	local p = s.input
	if advance ~= false then p:advance() end
	local t = sheet.tune
	local dy = p:crank() * t.crankPx
	if p:held("down") then dy = dy + t.held elseif p:held("up") then dy = dy - t.held end
	if dy ~= 0 then
		if not s.textImg then textImage(s) end
		local y = max(0, min(max(0, s.textH - 200), s.y + dy))
		if y ~= s.y then s.y = y; s.img = nil end
	end
	if p:pressed("b") then s.done = true end
end

function sheet.draw(s)
	if not s.img then
		s.img = gfx.image.new(400, 240, WHITE)
		gfx.pushContext(s.img)
		sheet.render(s)
		gfx.popContext()
	end
	s.img:draw(0, 0)
end

tw.scenes.sheet = sheet
