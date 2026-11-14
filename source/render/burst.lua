-- Hit bursts (docs/design/README.md "Hit effects", boards/HitFX.png): when
-- the picture reaches the impact on the first kubb (or the king) a baton
-- toppled (the moment it was struck, not once it is down), a
-- pre-drawn burst is put up and to the left of the hit with its long spike
-- touching it, with a knock (sound.lua) at the flash, the moment of the
-- hit; the double's second knock comes with its second star. Three images per kind from
-- tools/art/build.py (images/burst/<kind>-1..3): the flash, the burst with
-- the word, the break-up with six chips flying out. Which kind and when is
-- core/burstpick. The king's flash inverts the whole screen for its two
-- frames (playdate.display.setInverted: free).
--
-- Timed in real seconds (the board's frame counts at 30 fps), not in the
-- slowed throw time, so a burst reads the same at any pace. Drawn after the
-- world, outside its caches: one image a frame, plus six fillRects in the
-- break-up. The anchor is a world point projected each frame, so the burst
-- stays on the hit while the camera moves.
import "CoreLibs/graphics"
import "core/tw"
import "core/camera"
import "core/playback"
import "core/burstpick"
import "sound"

tw.render = tw.render or {}

local gfx <const> = playdate.graphics
local camera, playback, pick = tw.camera, tw.playback, tw.burstpick
local floor, cos, sin = math.floor, math.cos, math.sin

local burst = {}

burst.tune = {
	on = true,          -- false: no bursts (the autobench measures their cost)
	flash = 2 / 30,     -- s: the flash
	burst = 12 / 30,    -- the burst with the word
	breakup = 4 / 30,   -- the break-up
	second = 3 / 30,    -- the double's second star, after the first
	lift = 0.12,        -- m above a toppled piece's centre for its anchor (when it was not the
	                    -- baton's first hit, which has a contact point)
	top = 15,           -- px: a burst stays below the rail
	chipFrom = 0.35,    -- the chips fly from this share of the image's width from its centre
	chipTo = 0.75,      -- to this, over the break-up
}

-- the scale of each kind's images (tools/art/build.py BURST_KINDS) and the
-- margin: the spike's tip is at (M + 106 S, M + 70 S) in every image
local SCALE <const> = { clean = 1.0, double_a = 0.9, double_b = 0.9, king = 1.15 }
local M <const> = 3

local IMG, AX, AY, W, H = {}, {}, {}, {}, {}
local function load()
	for kind, S in pairs(SCALE) do
		IMG[kind] = {}
		for i = 1, 3 do IMG[kind][i] = gfx.image.new("images/burst/" .. kind .. "-" .. i) end
		W[kind], H[kind] = IMG[kind][1]:getSize()
		AX[kind], AY[kind] = floor(M + 106 * S + 0.5), floor(M + 70 * S + 0.5)
	end
end

-- six chips: direction (radians, screen), size
local CHIP_A <const> = { -2.6, -1.7, -0.6, 0.3, 1.4, 2.5 }
local CHIP_W <const> = { 4, 3, 5, 3, 4, 3 }
local CHIP_H <const> = { 3, 3, 2, 3, 2, 4 }
local CHIP_C, CHIP_S = {}, {}
for i = 1, 6 do CHIP_C[i], CHIP_S[i] = cos(CHIP_A[i]), sin(CHIP_A[i]) end

function burst.new()
	return { kind = nil, done = false, age = 0, inverted = false, knocked2 = false, provisional = false }
end

-- A new throw (or none): clears the burst and the screen inversion.
function burst.reset(B)
	B.kind, B.done, B.age, B.knocked2, B.provisional, B.gap = nil, false, 0, false, false, nil
	if B.inverted then
		playdate.display.setInverted(false)
		B.inverted = false
	end
end

local function length(B)
	local t = burst.tune
	return t.flash + t.burst + t.breakup + ((B.kind == "double") and t.second or 0)
end

local KNOCK <const> = { clean = "tok", double = "klak", king = "king" }

-- The kind and anchors from core/burstpick. Until the physics has computed
-- the whole window after the first topple the kind is provisional: a later
-- topple can still make a clean burst a double, or any burst the king's.
local function classify(B, pb, showTime)
	local kind, a, b = pick.pick(pb.w, showTime)
	if not kind then return nil end
	B.kind = kind
	local fh = pb.w.firstHit
	if fh and fh.with == a.id then
		B.x1, B.y1, B.z1 = fh.x, fh.y, fh.z
	else
		local x, y, z = playback.poseAt(pb, a.index, pick.hitTime(a))
		B.x1, B.y1, B.z1 = x, y, z + burst.tune.lift
	end
	if b then
		local x, y, z = playback.poseAt(pb, b.index, pick.hitTime(b))
		B.x2, B.y2, B.z2 = x, y, z + burst.tune.lift
	end
	B.provisional = not pb.done and pb.w.time < showTime + pick.tune.window
	return kind
end

-- Once a frame while a throw plays (flight and rest): starts the burst when
-- the picture reaches the first topple, then ages it by dt (real seconds).
-- Has the king fallen by this time on screen? (A plain scan, no tables.)
local function kingDown(w, t)
	local bodies = w.bodies
	for i = 1, w.n do
		local b = bodies[i]
		if b.kind == "king" then return b.toppleT ~= nil and pick.hitTime(b) <= t end
	end
	return false
end

function burst.update(B, s, dt)
	if not burst.tune.on then return end
	local pb = s.pb
	if pb and s.projectile == "baton" and B.kind ~= "king"
		and (not B.kind or B.provisional or kingDown(pb.w, s.showTime)) then
		local was = B.kind
		local kind = classify(B, pb, s.showTime)
		if kind and not was then
			-- how far past the impact the picture is as the burst starts (the
			-- autobench reports it: 0 to a frame when the physics is ahead)
			local _, a = pick.pick(pb.w, s.showTime)
			B.gap = a and (s.showTime - pick.hitTime(a)) or nil
		end
		if kind and kind ~= was and (not was or kind == "king") then
			-- a new burst, or the king's replacing whatever showed: from the start
			B.age, B.done, B.knocked2 = 0, false, false
			tw.sound.hit(KNOCK[kind])
			return
		end
	end
	if B.done or not B.kind then return end
	B.age = B.age + dt
	if B.kind == "double" and not B.knocked2 and B.age >= burst.tune.second then
		B.knocked2 = true
		tw.sound.hit("klak")
	end
	if B.age >= length(B) then B.done = true end
end

-- One kind's image for its age (nil before its start or after its end), at
-- the projected anchor. Returns its box for the chips.
local function drawOne(cam, kind, x, y, z, age)
	local t = burst.tune
	if age < 0 then return nil end
	local phase
	if age < t.flash then phase = 1
	elseif age < t.flash + t.burst then phase = 2
	elseif age < t.flash + t.burst + t.breakup then phase = 3
	else return nil end
	local sx, sy = camera.project(cam, x, y, z)
	if not sx then return nil end
	local w, h = W[kind], H[kind]
	local left, top = floor(sx - AX[kind]), floor(sy - AY[kind])
	if left < 0 then left = 0 elseif left > 400 - w then left = 400 - w end
	if top < t.top then top = t.top elseif top > 240 - h then top = 240 - h end
	IMG[kind][phase]:draw(left, top)
	if phase == 3 then return left, top, w, h, (age - t.flash - t.burst) / t.breakup end
	return nil
end

local function chips(left, top, w, h, u)
	local t = burst.tune
	local cx, cy = left + w / 2, top + h / 2
	local d = (t.chipFrom + (t.chipTo - t.chipFrom) * u) * w
	gfx.setColor(gfx.kColorBlack)
	for i = 1, 6 do
		gfx.fillRect(floor(cx + CHIP_C[i] * d), floor(cy + CHIP_S[i] * d * 0.7), CHIP_W[i], CHIP_H[i])
	end
end

-- After the world, before the HUD.
function burst.draw(B, cam)
	local inv = false
	if B.kind and not B.done then
		local l, tp, w, h, u
		if B.kind == "double" then
			drawOne(cam, "double_a", B.x1, B.y1, B.z1, B.age)
			l, tp, w, h, u = drawOne(cam, "double_b", B.x2, B.y2, B.z2, B.age - burst.tune.second)
		else
			l, tp, w, h, u = drawOne(cam, B.kind, B.x1, B.y1, B.z1, B.age)
		end
		if l then chips(l, tp, w, h, u) end
		inv = B.kind == "king" and B.age < burst.tune.flash
	end
	if inv ~= B.inverted then
		playdate.display.setInverted(inv)
		B.inverted = inv
	end
end

-- Loaded at import, not at the first hit: loading all twelve images then
-- held that frame for 170 ms on the device (2026-11-13).
load()

tw.render.burst = burst
