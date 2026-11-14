-- Which hit burst a baton throw shows, and when (docs/design/README.md "Hit
-- effects"). Pure: reads a core/world (its bodies' kind, toppleT and index)
-- and the time on screen.
--
-- A burst starts when the picture reaches the moment the first kubb or king
-- the throw toppled was struck (world bodies carry touchT, the first time
-- something struck them, and toppleT, the time they went down; Jamie: the
-- burst and its knock at the impact, not once the piece is down). The
-- topple is known only once the physics has run past it, which the slow
-- motion around the hit gives it time to do.
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
	window = 0.4,   -- s after the first topple that a second one makes it a double
}

-- The moment a toppled body was struck (its topple when nothing recorded a
-- touch).
local function hitTime(b)
	return b.touchT or b.toppleT
end
burstpick.hitTime = hitTime

-- Returns nil before the first toppled piece's impact is on screen (or when
-- nothing toppled), else kind, first body, second body (the double's second
-- kubb) or nil. No tables are made.
function burstpick.pick(w, showTime)
	local bodies, n = w.bodies, w.n
	local first, ft = nil, nil
	for i = 1, n do
		local b = bodies[i]
		if b.toppleT and (b.kind == "kubb" or b.kind == "king") then
			local ht = hitTime(b)
			if not ft or ht < ft then first, ft = b, ht end
		end
	end
	if not first or ft > showTime then return nil end
	local limit = ft + burstpick.tune.window
	local second, king = nil, first.kind == "king" and first or nil
	for i = 1, n do
		local b = bodies[i]
		if b ~= first and b.toppleT then
			local ht = hitTime(b)
			if b.kind == "king" then
				if ht <= limit or ht <= showTime then king = b end
			elseif b.kind == "kubb" and ht <= limit and (not second or ht < hitTime(second)) then
				second = b
			end
		end
	end
	if king then return "king", king, nil end
	if second then return "double", first, second end
	return "clean", first, nil
end

tw.burstpick = burstpick
