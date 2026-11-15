-- The match's full-screen cards in the Woodcut look: the hand-off
-- (docs/design/boards/HandOff.png) and the winner (Winner.png). Each is
-- drawn once into a 400 x 240 image from the facts core/cards gives; the
-- match scene keeps the image and copies it every frame (one image draw),
-- so no text is drawn while a card waits for a button.
--
--   rcards.handoff(c)               c = core/cards.handoff
--   rcards.settle(c)                c = core/cards.settle (the pass card before
--                                   the defender raises, PASS + PLAY)
--   rcards.winner(c, how, saved)    c = core/cards.winner; how = the
--                                   sentence (core/match.howText); saved =
--                                   the game file was written
import "CoreLibs/graphics"
import "core/tw"
import "render/ui"

local gfx <const> = playdate.graphics
local ui = tw.render.ui

tw.render = tw.render or {}
local rcards = {}

-- Positions are screen pixels from the boards (src/HandOff.html, Winner.html).
rcards.tune = {
	left = 16,
	right = 392,                -- the turn line's right edge
	-- hand-off
	nameTop = 43,               -- the name's cap top (display 32)
	ruleY = 90, ruleW = 240,    -- the 3 px rule under the name
	tookY = 104,                -- "TEAM A JUST TOOK" and its pips
	tookPip = { w = 12, h = 6, step = 16, minStep = 7 },
	tookRight = 282,            -- the row stops here, clear of the map
	throwY = 128,               -- "YOU THROW"
	kubbLineY = 150,            -- the kubb pips and "3 KUBBS IN"
	batonLineY = 174,           -- the baton pips and "THEN 6 BATONS"
	kubbPip = { w = 8, h = 15, step = 13 },
	batonPip = { w = 4, h = 15, step = 7 },
	buttonY = 215,
	orderY = 196,               -- a team of several: who throws which batons
	map = { x = 290, y = 36, w = 94, h = 148, cx = 337, base = 175, far = 45, mPerX = 18 },
	-- winner
	winNameTop = 36,            -- the winner's cap top (display 32)
	winsTop = 82,               -- WINS
	winRuleY = 128, winRuleW = 150,
	statsY = 140, statsStep = 14,
	buttonGap = 18,             -- A REMATCH to B TITLE
}

local function white() gfx.setColor(gfx.kColorWhite) end

-- The small pitch on the right: the far half is the team that just threw.
local function drawMap(c)
	local m = rcards.tune.map
	local label = ui.label()
	if c.fromName then ui.text(label, c.fromName, m.cx, m.y - 16, true, "center") end
	white()
	gfx.fillRect(m.x, m.y, m.w, m.h)
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(2)
	gfx.drawRect(m.x + 3, m.y + 3, m.w - 6, m.h - 6)
	-- the centerline, dashed 4 on 3
	local cy = (m.base + m.far) // 2
	for x = m.x + 3, m.x + m.w - 4, 7 do gfx.fillRect(x, cy - 1, 4, 2) end
	gfx.setLineWidth(1)
	local sy = (m.base - m.far) / 8
	for _, p in ipairs(c.pieces) do
		local x = math.floor(m.cx + p.x * m.mPerX + 0.5)
		local y = math.floor(m.base - p.y * sy + 0.5)
		if p.kind == "king" then
			gfx.fillRect(x - 3, y - 3, 6, 6)
			gfx.fillPolygon(x - 3, y - 3, x - 3, y - 6, x - 1, y - 4, x, y - 7, x + 1, y - 4, x + 3, y - 6, x + 3, y - 3)
		elseif p.down then
			gfx.drawRect(x - 2, y - 2, 4, 4)
		else
			gfx.fillRect(x - 2, y - 2, 4, 4)
		end
	end
	ui.text(label, c.toName, m.cx, m.y + m.h + 4, true, "center")
	ui.textDots(label, { "TURN " .. c.turn, "BASE " .. c.base[1] .. " V " .. c.base[2] }, rcards.tune.right,
		rcards.tune.buttonY + 1, true, "right")
end

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

function rcards.handoff(c)
	local t = rcards.tune
	local img = gfx.image.new(400, 240, gfx.kColorBlack)
	local label, d16, d32 = ui.label(), ui.display(16), ui.display(32)
	gfx.pushContext(img)
	ui.text(label, "PASS THE PLAYDATE TO", t.left, 18, true)
	-- a team of several: the first thrower's name (the team's on the throw line)
	ui.text(d32, c.thrower or c.toName, t.left - 1, t.nameTop - 1, true)
	white()
	gfx.fillRect(t.left, t.ruleY, t.ruleW, 3)

	-- what the other team did last turn
	if c.took then
		local n = c.took.field + c.took.base
		if n == 0 then
			ui.text(label, c.fromName .. " took none", t.left, t.tookY, true)
		else
			local x = t.left + ui.text(label, c.fromName .. " just took", t.left, t.tookY, true) + 10
			local parts = {}
			if c.took.field > 0 then parts[#parts + 1] = c.took.field .. " field" end
			if c.took.base > 0 then parts[#parts + 1] = c.took.base .. " base" end
			local count = table.concat(parts, ", ")
			-- The row must end before the map. Many kubbs: close the pips up;
			-- too many even for that: the count alone says it.
			local pip = t.tookPip
			local room = t.tookRight - x - 4 - label:getTextWidth(string.upper(count))
			local step = math.min(pip.step, room // n)
			if step >= pip.minStep then
				local w = pip.w - (pip.step - step)
				gfx.setLineWidth(1)
				white()
				for _ = 1, n do
					gfx.drawRect(x, t.tookY + 3, w, pip.h)
					x = x + step
				end
				x = x + 4
			end
			ui.text(label, count, x, t.tookY, true)
		end
	else
		ui.text(label, "the first turn", t.left, t.tookY, true)
	end

	-- what this team throws
	ui.text(label, c.thrower and (c.toName .. " throws") or "you throw", t.left, t.throwY, true)
	local lines = {}
	if c.kubbs > 0 then
		lines[#lines + 1] = { pip = t.kubbPip, n = c.kubbs, text = plural(c.kubbs, "kubb", "kubbs") .. " in"
			.. ((c.inkaster and c.inkaster ~= c.thrower) and (": " .. c.inkaster) or "") }
	end
	lines[#lines + 1] = { pip = t.batonPip, n = c.batons,
		text = (c.kubbs > 0 and "then " or "") .. plural(c.batons, "baton", "batons") }
	for i, l in ipairs(lines) do
		local y = i == 1 and t.kubbLineY or t.batonLineY
		local x = t.left
		white()
		for _ = 1, l.n do
			gfx.fillRect(x, y, l.pip.w, l.pip.h)
			x = x + l.pip.step
		end
		-- display 16: the caps sit one row into the cell; line them up with the pips
		ui.text(d16, l.text, x + 6, y - 1, true)
	end
	-- who throws which batons, in order
	if c.order then
		local parts = {}
		for i, e in ipairs(c.order) do parts[i] = e.name .. " " .. e.n end
		ui.textDots(label, parts, t.left, t.orderY, true)
	end

	local w = ui.button("A", "ready", t.left, t.buttonY, true)
	if c.thrower then ui.button("B", "change", t.left + w + t.buttonGap, t.buttonY, true) end
	drawMap(c)
	gfx.popContext()
	return img
end

-- The pass card before the defender raises kubbs and places punishment
-- kubbs (PASS + PLAY): the hand-off card's look, with what the defender does
-- and who it hands the Playdate back to.
function rcards.settle(c)
	local t = rcards.tune
	local img = gfx.image.new(400, 240, gfx.kColorBlack)
	local label, d16, d32 = ui.label(), ui.display(16), ui.display(32)
	gfx.pushContext(img)
	ui.text(label, "PASS THE PLAYDATE TO", t.left, 18, true)
	ui.text(d32, c.toName, t.left - 1, t.nameTop - 1, true)
	white()
	gfx.fillRect(t.left, t.ruleY, t.ruleW, 3)
	ui.text(label, "you raise", t.left, t.tookY, true)
	local lines = {}
	if c.raise > 0 then
		lines[#lines + 1] = { n = c.raise, text = plural(c.raise, "kubb", "kubbs") .. " up" }
	end
	if c.punish > 0 then
		lines[#lines + 1] = { n = c.punish, text = (c.raise > 0 and "and " or "") .. "place "
			.. plural(c.punish, "punishment kubb", "punishment kubbs") }
	end
	local pip = t.kubbPip
	for i, l in ipairs(lines) do
		local y = t.tookY + 24 + (i - 1) * 24
		local x = t.left
		white()
		for _ = 1, l.n do
			gfx.fillRect(x, y, pip.w, pip.h)
			x = x + pip.step
		end
		ui.text(d16, l.text, x + 6, y - 1, true)
	end
	ui.text(label, "then hand it back to " .. c.backName, t.left, t.tookY + 24 + #lines * 24 + 4, true)
	ui.button("A", "ready", t.left, t.buttonY, true)
	gfx.popContext()
	return img
end

-- The pass card inside a team (core/cards.pass): who takes the Playdate,
-- for which throws, at what level; A throws, B changes the thrower.
function rcards.pass(c)
	local t = rcards.tune
	local img = gfx.image.new(400, 240, gfx.kColorBlack)
	local label, d16, d32 = ui.label(), ui.display(16), ui.display(32)
	gfx.pushContext(img)
	ui.text(label, "PASS THE PLAYDATE TO", t.left, 18, true)
	ui.text(d32, c.name, t.left - 1, t.nameTop - 1, true)
	white()
	gfx.fillRect(t.left, t.ruleY, t.ruleW, 3)
	local parts = { c.team }
	if c.level then parts[2] = "level " .. c.level end
	ui.textDots(label, parts, t.left, t.tookY, true)
	local what
	if c.kind == "kubbs" then what = "the kubbs in"
	elseif c.from == c.to then what = "baton " .. c.from
	elseif c.to == c.from + 1 then what = "batons " .. c.from .. " and " .. c.to
	else what = "batons " .. c.from .. " to " .. c.to end
	ui.text(d16, what, t.left, t.throwY + 4, true)
	local w = ui.button("A", "throw", t.left, t.buttonY, true)
	ui.button("B", "change", t.left + w + t.buttonGap, t.buttonY, true)
	gfx.popContext()
	return img
end

-- Who takes the throw instead (core/match.candidates): the team's players,
-- the chosen one boxed, those the rules refuse with why.
rcards.WHY = { cap = "two batons already", distinct = "needs another thrower", team = "not on the team" }
function rcards.change(list, chosen, what)
	local t = rcards.tune
	local img = gfx.image.new(400, 240, gfx.kColorBlack)
	local label, d16 = ui.label(), ui.display(16)
	gfx.pushContext(img)
	ui.text(label, "who throws " .. what, t.left, 18, true)
	for i, e in ipairs(list) do
		local y = 40 + (i - 1) * 26
		local on = i == chosen
		if on then
			white()
			gfx.fillRect(t.left - 6, y - 4, 260, 24)
		end
		ui.text(d16, e.name, t.left, y, not on)
		local note = e.current and "now" or ((not e.ok) and (rcards.WHY[e.why] or "not now") or nil)
		if note then ui.text(label, note, t.left + 250, y + 3, not on, "right") end
	end
	local w = ui.button("A", "this one", t.left, t.buttonY, true)
	ui.button("B", "back", t.left + w + t.buttonGap, t.buttonY, true)
	gfx.popContext()
	return img
end

local burst = nil

function rcards.winner(c, how, saved)
	local t = rcards.tune
	burst = burst or gfx.image.new("images/winner")
	local img = gfx.image.new(400, 240, gfx.kColorBlack)
	local label, d32 = ui.label(), ui.display(32)
	gfx.pushContext(img)
	burst:draw(0, 0)
	ui.text(d32, c.winnerName, t.left - 1, t.winNameTop - 1, true)
	ui.text(d32, "wins", t.left - 1, t.winsTop - 1, true)
	white()
	gfx.fillRect(t.left, t.winRuleY, t.winRuleW, 3)
	local y = t.statsY
	local function line(parts)
		ui.textDots(label, parts, t.left, y, true)
		y = y + t.statsStep
	end
	if how and how ~= "" then line { how } end
	local first = { plural(c.turns, "turn", "turns") }
	if c.minutes then first[2] = c.minutes < 1 and "under a min" or (c.minutes .. " min") end
	-- a team of several needs the room for its players: "saved" joins this line
	if c.players then first[#first + 1] = saved and "game saved" or "not saved" end
	line(first)
	if c.thrown and c.thrown > 0 then
		line { string.format("baton hits %d%%", math.floor(100 * c.hits / c.thrown + 0.5)) }
	end
	if c.players then
		-- each player's hits over batons, three to a line
		for from = 1, #c.players, 3 do
			local parts = {}
			for i = from, math.min(#c.players, from + 2) do
				local p = c.players[i]
				parts[#parts + 1] = p.name .. " " .. p.hits .. "/" .. p.thrown
			end
			line(parts)
		end
	else
		line { saved and "game saved" or "not saved" }
	end
	local w = ui.button("A", "rematch", t.left, t.buttonY, true)
	ui.button("B", "title", t.left + w + t.buttonGap, t.buttonY, true)
	gfx.popContext()
	return img
end

tw.render.cards = rcards
