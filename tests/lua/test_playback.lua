import "core/playback"
local playback = tw.playback

test("slow motion: real time before a hit, slow around it, easing back after", function()
	local k = playback.slow
	expect.eq(playback.speed(1.0, nil), 1, "no hit known")
	expect.eq(playback.speed(0.5, 2.0), 1, "long before the hit")
	expect.eq(playback.speed(2.0 - k.lead * 0.5, 2.0), k.rate, "just before")
	expect.eq(playback.speed(2.0 + k.hold * 0.5, 2.0), k.rate, "during")
	local mid = playback.speed(2.0 + k.hold + k.ease * 0.5, 2.0)
	expect.truthy(mid > k.rate and mid < 1, "easing " .. mid)
	expect.eq(playback.speed(2.0 + k.hold + k.ease + 0.1, 2.0), 1, "back to real time")
end)
