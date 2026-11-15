-- core/save: a match in progress as plain data, and back.
import "core/save"
import "core/rules"
import "core/notation"
import "core/match"
local save, notation, match = tw.save, tw.notation, tw.match

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local thrower = dofile(here .. "/../../tools/thrower.lua")

local META = { start = { year = 2026, month = 11, day = 13, hour = 21, min = 0 },
	finish = { year = 2026, month = 11, day = 13, hour = 21, min = 30 }, version = "test" }

-- Through a text form like the datastore's JSON: plain data only, no shared
-- tables (save.plain refuses anything else), copied again.
local function roundTrip(d)
	return save.plain(save.plain(d))
end

test("save: a game saved and restored mid-match plays on to the same game file", function()
	local total = 0
	for seed = 1, 40 do
		local straight = thrower.playGame(seed)
		local want = notation.render(straight, META)
		local actions, swapped = 0, 0
		local resumed = thrower.playGame(seed, nil, function(g, o)
			actions = actions + 1
			-- save and restore every 7th action: mid-inkast, mid-raise, mid-batons
			if actions % 7 ~= 0 or g.phase == "over" then return nil end
			local m = { game = g, start = META.start, mode = "Pass and Play", turn = g.turn, tossed = 0, order = o }
			local d = roundTrip(save.pack(m, { names = { A = "Ash", B = "Birch" } }))
			local back, opts = save.unpack(d)
			expect.truthy(back, "unpacked")
			expect.eq(opts.names.B, "Birch")
			expect.truthy(back.order, "the throwing order is saved")
			swapped = swapped + 1
			return back.game, back.order
		end)
		total = total + swapped
		expect.eq(notation.render(resumed, META), want, "seed " .. seed .. ": same game file")
	end
	expect.truthy(total > 200, "saved and restored " .. total .. " times over 40 games")
end)

test("save: what JSON could not keep is refused, and a wrong version is not unpacked", function()
	local shared = { 1, 2 }
	expect.truthy(not pcall(save.plain, { a = shared, b = shared }), "a table met twice")
	expect.truthy(not pcall(save.plain, { f = function() end }), "a function")
	expect.truthy(not pcall(save.plain, { 1, 2, x = 3 }), "a list with named keys")
	expect.eq((save.unpack { v = 99, game = {} }), nil)
	expect.eq((save.unpack(nil)), nil)
end)

test("save: a core/match table packs whole, debris and all, and sets up again", function()
	local m = match.new { start = META.start }
	local s1 = match.setup(m)
	local d = roundTrip(save.pack(m, nil))
	local back = save.unpack(d)
	local s2 = match.setup(back)
	expect.eq(s2.kind, s1.kind)
	expect.eq(s2.label, s1.label)
	expect.eq(#s2.pieces, #s1.pieces)
end)
