-- Which hit burst a baton throw shows, and when (docs/design/README.md "Hit
-- effects"). Pure: reads a core/world (its bodies' kind, toppleT and index)
-- and the time on screen.
--
-- A burst starts when the picture reaches the moment the first kubb or king
-- the throw knocks over was struck (Jamie: the burst and its knock at the
-- impact, not once the piece is down). World bodies carry touchT, the first
-- time something struck them, and toppleT, the time they went down; a piece
-- struck hard enough (falling, below) is taken as going down at its impact,
-- before the physics has run as far as its topple.
-- What kind: the king toppled within `window` s of the first topple, or by
-- now (whenever it fell), is "king" (the winning hit or the losing one); two
-- or more kubbs down within `window` s of the first is "double"; one is
-- "clean". So a king that falls well after a kubb turns the burst into the
-- king's when the picture reaches it (render/burst restarts it). A baton that touches a kubb and leaves it
-- standing, or a miss, gets nothing. Pieces already down when the throw
-- started have no toppleT and never count.
import "core/tw"

local burstpick = {}

burstpick.tune = {
	window = 0.4,     -- s after the first impact that a second one makes it a double
	-- A struck kubb is taken as falling at its impact when, just after the
	-- strike, it moves faster than this or turns faster than this: a 7 x 7 x 15
	-- cm kubb tips over with about 0.39 m/s or 4.1 rad/s about its edge, and a
	-- baton strike gives far more. On the device the physics cannot reach the
	-- topple before the picture reaches the impact (it was 260 ms of shown
	-- time late), so the burst cannot wait for it.
	fallV = 0.5,      -- m/s
	fallW = 5,        -- rad/s
	judgeFor = 0.5,   -- s after the strike the speeds are read (later, the topple or the rest decides)
}

-- The moment a body was struck (its topple when nothing recorded a touch).
local function hitTime(b)
	return b.touchT or b.toppleT
end
burstpick.hitTime = hitTime

-- Is body b falling, as far as the physics knows at world time w.time?
-- Returns falling, sure: sure when it has toppled; a fast-moving struck
-- piece is falling but not sure (its burst may be taken back).
local function falling(b, w)
	if b.kind ~= "kubb" and b.kind ~= "king" then return false end
	if b.toppleT then return true, true end
	if b.toppled then return false end          -- down before this throw
	local ht = b.touchT
	if not ht or w.time - ht > burstpick.tune.judgeFor or not b.awake then return false end
	local t = burstpick.tune
	local v2 = b.vx * b.vx + b.vy * b.vy + b.vz * b.vz
	local w2 = b.wx * b.wx + b.wy * b.wy + b.wz * b.wz
	return (v2 >= t.fallV * t.fallV or w2 >= t.fallW * t.fallW), false
end
burstpick.falling = falling

-- Returns nil before the first falling piece's impact is on screen (or when
-- nothing is falling), else kind, first body, second body (the double's
-- second kubb) or nil, and whether the first is sure (toppled). No tables
-- are made.
function burstpick.pick(w, showTime)
	local bodies, n = w.bodies, w.n
	local first, ft, sure = nil, nil, false
	for i = 1, n do
		local b = bodies[i]
		local f, s = falling(b, w)
		if f then
			local ht = hitTime(b)
			if not ft or ht < ft then first, ft, sure = b, ht, s end
		end
	end
	if not first or ft > showTime then return nil end
	local limit = ft + burstpick.tune.window
	local second, king = nil, first.kind == "king" and first or nil
	for i = 1, n do
		local b = bodies[i]
		if b ~= first and falling(b, w) then
			local ht = hitTime(b)
			if b.kind == "king" then
				if ht <= limit or ht <= showTime then king = b end
			elseif ht <= limit and (not second or ht < hitTime(second)) then
				second = b
			end
		end
	end
	if king then return "king", king, nil, sure end
	if second then return "double", first, second, sure end
	return "clean", first, nil, sure
end

-- Was a body taken as falling at its impact in the end left standing? (Its
-- burst is taken back.) True once it has gone to sleep, or the throw is
-- over, without toppling.
function burstpick.stoodUp(b, done)
	return not b.toppleT and (done or not b.awake)
end

tw.burstpick = burstpick
