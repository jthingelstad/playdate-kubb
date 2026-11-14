-- The game's sounds.
--
-- Knocks (Jamie, 2026-11-14: "an audio recording of a Kubb hit. There are
-- multiple to use so they are not all the same ... if the baton hits
-- multiple kubbs you could play multiple overlapping files"): nine takes of
-- a baton hitting a kubb, cut from Jamie's recording by tools/sounds.py
-- (rumble filtered out, tails faded, levels matched), sounds/knock-1..9. One
-- plays for every piece struck (a kubb, the king, a lying baton, a stake:
-- "if wood hits wood play a sound"), as the picture reaches the moment
-- (scenes/throw, core/burstpick.touches): a different take from the last,
-- at a slightly different rate, each on its own player, so knocks that come
-- together overlap.
--
-- The king's fall adds a short bright chord made by the synths (render/burst).
import "core/tw"

local snd <const> = playdate.sound

local sound = {}
sound.on = true          -- the self-tests turn it off (main.lua)

-- Volumes 0..1, rates (1 = as recorded), lengths in s. To tune by ear on the
-- device.
sound.tune = {
	knocks = 9,          -- sounds/knock-1 .. knock-<knocks>
	knockVol = 0.8,
	knockRate = 0.06,    -- each knock plays at 1 +- this (uniform): no two alike
	king = { chord = { 523.25, 783.99 }, vol = 0.35, len = 0.45 },
}

local players, last = nil, 0
sound.played = 0         -- knocks played (the knocks self-test counts them)
local ring1, ring2

local function load()
	players = {}
	for i = 1, sound.tune.knocks do
		local s = snd.sample.new("sounds/knock-" .. i)
		if s then players[#players + 1] = snd.sampleplayer.new(s) end
	end
end

-- One knock: a take other than the last one played and, when it can, one
-- not playing now (so overlapping knocks are different takes).
function sound.knock()
	if not sound.on then return end
	if not players then load() end
	local n = #players
	if n == 0 then return end
	local t = sound.tune
	local i = math.random(n)
	for _ = 1, n do
		if i ~= last and not players[i]:isPlaying() then break end
		i = i % n + 1
	end
	last = i
	sound.played = sound.played + 1
	local p = players[i]
	p:setVolume(t.knockVol)
	p:setRate(1 + (2 * math.random() - 1) * t.knockRate)
	p:play()
end

-- How many knock takes loaded (the knocks self-test).
function sound.loaded()
	if not players then load() end
	return #players
end

-- The king's fall: a short bright chord over its knock.
function sound.king()
	if not sound.on then return end
	if not ring1 then
		ring1 = snd.synth.new(snd.kWaveTriangle)
		ring1:setADSR(0.004, 0.4, 0, 0.1)
		ring2 = snd.synth.new(snd.kWaveTriangle)
		ring2:setADSR(0.004, 0.4, 0, 0.1)
	end
	local k = sound.tune.king
	ring1:playNote(k.chord[1], k.vol, k.len)
	ring2:playNote(k.chord[2], k.vol, k.len)
end

tw.sound = sound
