-- The game's sounds, made by the Playdate's synths at run time (no sample
-- files). So far the hit bursts' knocks (docs/design/README.md "Hit
-- effects": "with the sound"): a dry wood knock for TOK, two lower ones for
-- KLAK KLAK, a deep knock and a short bright chord for KING.
import "core/tw"

local snd <const> = playdate.sound

local sound = {}
sound.on = true          -- the self-tests turn it off (main.lua)

-- Pitches in Hz, volumes 0..1, lengths in s. Guesses, to tune by ear on the
-- device.
sound.tune = {
	tok = { pitch = 980, vol = 0.8, len = 0.06, click = 0.45 },
	klak = { pitch = 640, vol = 0.9, len = 0.08, click = 0.55 },
	king = { pitch = 210, vol = 0.9, len = 0.14, click = 0.6, chord = { 523.25, 783.99 }, chordVol = 0.35,
		chordLen = 0.45 },
	clickLen = 0.02,
}

local knock, click, ring1, ring2
local function make()
	knock = snd.synth.new(snd.kWaveSine)
	knock:setADSR(0, 0.07, 0, 0.02)
	click = snd.synth.new(snd.kWaveNoise)
	click:setADSR(0, 0.02, 0, 0.01)
	ring1 = snd.synth.new(snd.kWaveTriangle)
	ring1:setADSR(0.004, 0.4, 0, 0.1)
	ring2 = snd.synth.new(snd.kWaveTriangle)
	ring2:setADSR(0.004, 0.4, 0, 0.1)
end

-- kind: "tok" | "klak" | "king"
function sound.hit(kind)
	if not sound.on then return end
	if not knock then make() end
	local t = sound.tune
	local k = t[kind] or t.tok
	knock:playNote(k.pitch, k.vol, k.len)
	click:playNote(2000, k.click, t.clickLen)
	if k.chord then
		ring1:playNote(k.chord[1], k.chordVol, k.chordLen)
		ring2:playNote(k.chord[2], k.chordVol, k.chordLen)
	end
end

tw.sound = sound
