-- Which hit burst a baton throw shows, and when (docs/design/README.md "Hit
-- effects"). Pure: reads a core/world (its bodies' kind, toppleT and index)
-- and the time on screen.
--
-- A burst starts when the picture reaches the first kubb or king the throw
-- toppled (world bodies carry toppleT, the simulated time they went down).
-- What kind: the king among the toppled pieces is "king" (the winning hit or
-- the losing one); two or more kubbs down within `window` s of the first is
-- "double"; one is "clean". A baton that touches a kubb and leaves it
-- standing, or a miss, gets nothing. Pieces already down when the throw
-- started have no toppleT and never count.
import "core/tw"

local burstpick = {}

burstpick.tune = {
	window = 0.4,   -- s after the first topple that a second one makes it a double
}

-- Returns nil before the first topple is on screen (or when there is none),
-- else kind, first body, second body (the double's second kubb) or nil.
-- No tables are made.
function burstpick.pick(w, showTime)
	local bodies, n = w.bodies, w.n
	local first, ft = nil, nil
	for i = 1, n do
		local b = bodies[i]
		local tt = b.toppleT
		if tt and (b.kind == "kubb" or b.kind == "king") and (not ft or tt < ft) then first, ft = b, tt end
	end
	if not first or ft > showTime then return nil end
	local limit = ft + burstpick.tune.window
	local second, king = nil, first.kind == "king" and first or nil
	for i = 1, n do
		local b = bodies[i]
		local tt = b.toppleT
		if b ~= first and tt and tt <= limit then
			if b.kind == "king" then king = b
			elseif b.kind == "kubb" and (not second or tt < second.toppleT) then second = b end
		end
	end
	if king then return "king", king, nil end
	if second then return "double", first, second end
	return "clean", first, nil
end

tw.burstpick = burstpick
