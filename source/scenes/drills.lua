-- Practice drills (the Drills board). PRACTICE on the title opens this menu:
-- on the left OPEN PITCH (the free practice pitch, as before) and the drills
-- of core/drills; on the right the chosen drill's pitch from above, what it
-- is, its best, its last ten runs as bars and its hit rate. Up/down chooses,
-- A starts, B goes to the title.
--
-- A run is the drill's throws on its own pitch through the throw scene, set
-- up one throw at a time like the match (throw.prepare); the rail counts the
-- throws and the score. At the end a card gives the score and any new best
-- (records in playdate.datastore "drills"); A runs it again, B goes back to
-- the menu. During a run the System Menu's "Drill" leaves it unrecorded, for
-- the menu or the title (main.lua). Every screen but the throws is one image redrawn on a change.
import "CoreLibs/graphics"
import "core/tw"
import "core/drills"
import "core/pitch"
import "scenes/throw"
import "render/ui"

local gfx <const> = playdate.graphics
local drills, pitch, throw, ui = tw.drills, tw.pitch, tw.scenes.throw, tw.render.ui
local floor, max = math.floor, math.max
local BLACK <const>, WHITE <const> = gfx.kColorBlack, gfx.kColorWhite

tw.scenes = tw.scenes or {}
local scene = {}

scene.tune = {
	panelW = 194,      -- the black list panel
	itemY = 24, itemH = 31,
	mapX = 204, mapY = 22, mapW = 56, mapH = 90,   -- the pitch from above (5 x 8 m)
	recordsKey = "drills",
}

local OPEN <const> = { id = "open", name = "OPEN PITCH", lines = { "THE PRACTICE PITCH", "THROW AS YOU LIKE", "SYSTEM MENU: PITCH" } }

local function loadRecords(s)
	if s.scripted then return {} end
	return playdate.datastore.read(scene.tune.recordsKey) or {}
end

-- opts.scripted: no records read or written (self-tests)
function scene.new(provider, opts)
	opts = opts or {}
	local s = { input = provider, phase = "menu", choice = 1, scripted = opts.scripted, img = nil, exit = nil }
	s.items = { OPEN }
	for _, d in ipairs(drills.list) do s.items[#s.items + 1] = d end
	s.records = loadRecords(s)
	return s
end

-- ---------- the menu ----------

local function mapPoint(x, y)
	local t = scene.tune
	return t.mapX + (x + 2.5) * t.mapW / 5, t.mapY + (8 - y) * t.mapH / 8
end

local function drawMap(d)
	local t = scene.tune
	gfx.setColor(BLACK)
	gfx.setLineWidth(2)
	gfx.drawRect(t.mapX, t.mapY, t.mapW, t.mapH)
	gfx.setLineWidth(1)
	local _, cy = mapPoint(0, 4)
	local x = t.mapX
	while x < t.mapX + t.mapW do gfx.drawLine(x, cy, x + 4, cy); x = x + 7 end
	if d.id == "open" then return end
	local run = drills.newRun(d)
	local s = drills.setup(d, run)
	for _, p in ipairs(s.pieces) do
		local px, py = mapPoint(p.x, p.y)
		if p.kind == "king" then gfx.fillRect(px - 3, py - 3, 6, 6) else gfx.fillRect(px - 2, py - 2, 5, 5) end
	end
	-- where the throws come from, and the line of throw
	local bx = s.playerX or 0
	local tx, ty = mapPoint(bx, 0.2)
	if d.kind == "blast" then
		local mx, my = mapPoint(0, 6)
		gfx.drawCircleAtPoint(mx, my, 6)
		gfx.drawLine(tx, ty, mx, my + 6)
	else
		local gx, gy = mapPoint(bx, 7.4)
		local yy = ty
		while yy > gy do gfx.drawLine(tx, yy, tx, yy - 3); yy = yy - 6 end
		gfx.fillTriangle(tx, gy - 6, tx - 4, gy + 2, tx + 4, gy + 2)
	end
	-- the batons in hand
	for i = 1, d.throws do
		local hx = t.mapX + 8 + (i - 1) * 6 + ((i > 3) and 4 or 0)
		gfx.fillRect(hx, t.mapY + t.mapH - 14, 2, 10)
	end
end

local function renderMenu(s)
	local t = scene.tune
	local big, label = ui.display(16), ui.label()
	gfx.clear(WHITE)
	gfx.setColor(BLACK)
	gfx.fillRect(0, 0, t.panelW, 240)
	gfx.fillRect(0, 0, 400, 14)
	ui.text(label, "PRACTICE", 6, 2, true)
	ui.text(label, "GRASS", 394, 2, true, "right")
	for i, d in ipairs(s.items) do
		local y = t.itemY + (i - 1) * t.itemH
		if i == s.choice then
			gfx.setColor(WHITE)
			gfx.fillRect(8, y - 6, t.panelW - 16, 28)
		end
		-- a name too wide for the panel at cap 16 goes in the label font
		local f = (big:getTextWidth(d.name) <= t.panelW - 28) and big or label
		ui.text(f, d.name, 16, y + ((f == big) and 0 or 3), i ~= s.choice)
	end
	ui.button("A", "START", 16, 216, true)
	ui.button("B", "TITLE", 92, 216, true)
	-- the chosen drill
	local d = s.items[s.choice]
	drawMap(d)
	-- what it is, under the map
	for i, line in ipairs(d.lines) do ui.text(label, line, t.mapX, t.mapY + t.mapH + 8 + (i - 1) * 13) end
	if d.id ~= "open" then
		local r = s.records[d.id]
		local x = t.mapX + t.mapW + 14
		ui.text(label, "BEST", x, t.mapY + 4)
		ui.text(ui.display(32), r and (r.best .. "/" .. d.of) or ("-/" .. d.of), x, t.mapY + 22)
		gfx.setColor(BLACK)
		gfx.fillRect(t.mapX, 170, 394 - t.mapX, 2)
		ui.text(label, "LAST TEN", t.mapX, 180)
		local bx = t.mapX + 74
		for i, v in ipairs(r and r.last or {}) do
			local h = max(2, floor(20 * v / d.of))
			gfx.fillRect(bx + (i - 1) * 11, 194 - h, 7, h)
		end
		gfx.fillRect(bx - 2, 195, 112, 1)
		local rate = drills.rate(r)
		ui.textDots(label, { "HIT RATE " .. (rate and (rate .. "%") or "-"), (r and r.runs or 0) .. ((r and r.runs == 1) and " RUN" or " RUNS") }, t.mapX, 206)
	end
end

-- ---------- a run ----------

local function nextThrow(s)
	local d = s.drill
	local setup = drills.setup(d, s.run)
	if not setup then return false end
	throw.prepare(s.ts, setup)
	if setup.playerX then
		throw.showAim(s.ts, { x = setup.playerX, y = setup.lineY, swivel = 0, loftDeg = s.ts.loftDeg })
	end
	throw.setRail(s.ts, d.name, setup.projectile, setup.n, setup.of, "SCORE " .. s.run.score, nil)
	return true
end

local function startRun(s, d)
	s.drill, s.run = d, drills.newRun(d)
	s.ts = s.ts or throw.new(s.input)
	s.ts.sceneName = "practice"
	s.ts.showReadout = s.showReadout or false
	throw.enter()
	s.phase = "run"
	nextThrow(s)
end
scene.startRun = startRun

local function finishRun(s)
	local r, best = drills.record(s.records, s.drill, s.run)
	if not s.scripted then playdate.datastore.write(s.records, scene.tune.recordsKey) end
	s.newBest, s.phase, s.img = best, "result", nil
end

local function renderResult(s)
	local d, run = s.drill, s.run
	local big, label = ui.display(32), ui.label()
	gfx.clear(BLACK)
	ui.text(label, d.name, 200, 40, true, "center")
	ui.text(big, run.score .. "/" .. d.of, 200, 80, true, "center")
	ui.text(label, s.newBest and "A NEW BEST" or ("BEST " .. s.records[d.id].best .. "/" .. d.of), 200, 132, true, "center")
	ui.button("A", "AGAIN", 120, 200, true)
	ui.button("B", "DRILLS", 220, 200, true)
end

-- Leaves a run part way (the System Menu's "Drill: menu"): back to the menu,
-- nothing recorded. Safe from a menu callback: the throw scene is simply no
-- longer updated, and the next run's throw.prepare sets it up afresh.
function scene.quit(s)
	if s.phase == "menu" then return end
	playdate.display.setInverted(false)   -- a king burst's flash
	if s.ts then throw.suspend(s.ts) end  -- the drill's tilt: no sensor under the menu
	s.phase, s.img = "menu", nil
	scene.enter()
end

-- ---------- update and draw ----------

function scene.update(s)
	if s.phase == "run" then
		local ts = s.ts
		throw.update(ts)
		if ts.mode == "done" then
			local res = { toppled = ts.result and ts.result.toppled or {}, restCm = ts.last and ts.last.restCm }
			-- an illegal throw (a helicopter, II.B.1) scores nothing
			if ts.last and ts.last.legal == false then res.toppled, res.restCm = {}, nil end
			if drills.tally(s.drill, s.run, res) then
				finishRun(s)
			else
				nextThrow(s)
			end
		end
		return
	end
	local p = s.input
	p:advance()
	if s.phase == "menu" then
		local n = #s.items
		if p:pressed("down") then s.choice = s.choice % n + 1; s.img = nil
		elseif p:pressed("up") then s.choice = (s.choice - 2) % n + 1; s.img = nil end
		if p:pressed("a") then
			local d = s.items[s.choice]
			if d.id == "open" then s.exit = "practice" else startRun(s, d) end
		elseif p:pressed("b") then
			s.exit = "title"
		end
	elseif s.phase == "result" then
		if p:pressed("a") then startRun(s, s.drill)
		elseif p:pressed("b") then s.phase, s.img = "menu", nil end
	end
end

function scene.draw(s)
	if s.phase == "run" then
		throw.draw(s.ts)
		return
	end
	if not s.img then
		s.img = gfx.image.new(400, 240, WHITE)
		gfx.pushContext(s.img)
		if s.phase == "menu" then renderMenu(s) else renderResult(s) end
		gfx.popContext()
	end
	s.img:draw(0, 0)
end

function scene.enter()
	playdate.display.setRefreshRate(30)
end

tw.scenes.drills = scene
