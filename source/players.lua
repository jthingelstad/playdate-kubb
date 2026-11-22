-- Saved players on the Playdate (docs/PLAYERS.md section 2): the roster
-- (core/roster) in the datastore "players" and each player's history
-- (core/history) in "player-<key>". Self-test runs (tw.selftestRun) use
-- their own files ("selftest-players", "selftest-player-<key>") and never
-- read a player's.
--
-- The first load with no roster saved makes one from what earlier builds
-- kept: the names typed for matches (datastore "names") become players, and
-- the drill records (datastore "drills") go to the first of them ("You"
-- when there was none), so nobody's bests vanish. Those files are left as
-- they were.
--
-- Names are generated (kubb-engine docs/NAMES.md): a player whose kept name is not
-- a generated player name (typed on a build before 0.12.0) is renamed at load to a
-- generated one, rolled from their key and old name (device/namepick.fallback: the
-- same name every time, never one another player has), and the roster is saved. The
-- game files keep the old name; the history follows the key.
import "core/tw"
import "core/roster"
import "core/history"
import "core/names"
import "core/namegen"
import "device/namepick"

local roster, history = tw.roster, tw.history
local store = playdate.datastore

local players = {}

local function key(name)
	return tw.selftestRun and ("selftest-" .. name) or name
end
players.fileKey = key

local function pad(n) return (n < 10 and "0" or "") .. n end

-- "YYYY-MM-DD" and "YYYY-MM-DD HH:MM" now.
function players.today()
	local t = playdate.getTime()
	return t.year .. "-" .. pad(t.month) .. "-" .. pad(t.day)
end
function players.now()
	local t = playdate.getTime()
	return players.today() .. " " .. pad(t.hour) .. ":" .. pad(t.minute)
end

-- Give every player with a typed name a generated one; true when any changed.
function players.generateNames(r)
	local changed = false
	for _, p in ipairs(r.players) do
		if not tw.namegen.valid("player", p.name) then
			local name = tw.namepick.fallback("player", p.name, tw.namepick.seedOf(p.key .. " " .. p.name),
				function(n) return not roster.canName(r, n, p.key) end)
			if name and roster.rename(r, p.key, name) then changed = true end
		end
	end
	return changed
end

-- The roster (made, from the old files, the first time).
function players.load()
	local d = store.read(key("players"))
	if d then
		local r = roster.valid(d)
		if players.generateNames(r) then players.save(r) end
		return r
	end
	local r = roster.new()
	if not tw.selftestRun then
		local today = players.today()
		local added = roster.migrateNames(r, store.read("names"), today)
		local recs = store.read("drills")
		if type(recs) == "table" and next(recs) then
			local owner = added[1] or roster.add(r, tw.names.defaults.you, nil, today)
			if owner then
				local h = history.valid { drills = recs }
				store.write(h, key("player-" .. owner.key))
			end
		end
	end
	players.generateNames(r)
	players.save(r)
	return r
end

function players.save(r)
	store.write(r, key("players"))
end

function players.history(k)
	return history.valid(store.read(key("player-" .. k)))
end

function players.saveHistory(k, h)
	store.write(h, key("player-" .. k))
end

-- Remove a player and their history file, and save the roster.
function players.remove(r, k)
	if not roster.remove(r, k) then return false end
	store.delete(key("player-" .. k))
	players.save(r)
	return true
end

tw.players = players
