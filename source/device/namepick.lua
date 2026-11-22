-- Generated names on the Playdate (kubb-engine docs/NAMES.md, sections 8 and 10.2):
-- the state behind the Names screen (scenes/names). Pure: no playdate.*; the words and the rules are
-- core/namegen's, this only walks them. tests/lua/test_namepick.lua holds it.
--
--   namepick.new(kind, text, rand)  a picker for kind ("player" | "team") on `text`
--                                   when it is a name of that kind, else a rolled one.
--                                   rand(n) gives 1..n (the client's draw).
--   namepick.text(p)                the name it shows now
--   namepick.slots(p)               the words it shows, one per row: { "Mighty", "Maple" }
--                                   (a team's "The" is a first word like any other)
--   namepick.step(p, i, d)          row i's word moved by d (1 or -1) to the next that
--                                   makes a name; returns the name
--   namepick.shuffle(p, rand)       a whole new name; returns it
--   namepick.set(p, text)           take `text` if it is a name of p's kind (true), else
--                                   leave p as it was (false)
--
-- A team's first word runs through "The", every adjective, then every wood, so the
-- crank reaches all three of namegen's team shapes from one row; a player's first word
-- is an adjective and its second a wood. A word that would make no name with the other
-- row's word (too long, a pair namewords.never refuses, a repeat) is stepped over, as
-- namegen.step does.
import "core/tw"
import "core/namegen"
import "core/namewords"

local namegen, words = tw.namegen, tw.namewords

local namepick = {}

-- A team's first row: every (shape, word) in the order the crank meets them.
local teamFirst = nil
local function firstList()
	if not teamFirst then
		teamFirst = { { shape = "the" } }
		for _, w in ipairs(words.adjectives) do teamFirst[#teamFirst + 1] = { shape = "adj", word = w } end
		for _, w in ipairs(words.woods) do teamFirst[#teamFirst + 1] = { shape = "wood", word = w } end
	end
	return teamFirst
end

-- parts (namegen's) for a team from its first row's entry and its noun
local function teamParts(e, noun)
	if e.shape == "the" then return { shape = "the", noun } end
	return { shape = e.shape, e.word, noun }
end

local function noun(parts)
	return parts.shape == "the" and parts[1] or parts[2]
end

function namepick.new(kind, text, rand)
	local p = { kind = kind }
	if not namepick.set(p, text) then namepick.shuffle(p, rand) end
	return p
end

function namepick.set(p, text)
	local parts = namegen.parse(p.kind, text)
	if not parts then return false end
	p.parts, p.name = parts, text
	return true
end

function namepick.shuffle(p, rand)
	local name, parts = namegen.roll(p.kind, rand)
	if name then p.parts, p.name = parts, name end
	return p.name
end

function namepick.text(p) return p.name end

function namepick.slots(p)
	local parts = p.parts
	if p.kind == "team" then
		if parts.shape == "the" then return { "The", parts[1] } end
		return { parts[1], parts[2] }
	end
	return { parts[1], parts[2] }
end

function namepick.step(p, i, d)
	d = (d < 0) and -1 or 1
	local parts = p.parts
	if p.kind == "team" and i == 1 then
		-- across the shapes: The, the adjectives, the woods
		local list, n = firstList(), #firstList()
		local at = 1
		for j, e in ipairs(list) do
			if e.shape == parts.shape and (e.shape == "the" or e.word == parts[1]) then at = j break end
		end
		local nn = noun(parts)
		for k = 1, n - 1 do
			local e = list[(at - 1 + k * d) % n + 1]
			local next = teamParts(e, nn)
			local s = namegen.make("team", next)
			if s then p.parts, p.name = next, s; return s end
		end
		return p.name
	end
	-- a team's noun is its shape's last slot; a player's rows are its two slots
	local slot = i
	if p.kind == "team" then slot = (parts.shape == "the") and 1 or 2 end
	local s, next = namegen.step(p.kind, parts, slot, d)
	if s then p.parts, p.name = next, s end
	return p.name
end

tw.namepick = namepick
