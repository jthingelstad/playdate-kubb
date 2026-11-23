-- The physics benchmark on the desktop (make bench). The same scenario as
-- the practice pitch's System Menu "Pitch: bench" on the device (shown with the
-- debug file): source/core/bench.lua.
--
--   lua5.4 tools/bench.lua [runs] [--profile] [--micro]
-- --profile adds the per-phase breakdown of world.step, --micro the micro
-- benchmarks of device/microbench (the device autobench runs both).

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end
import "core/bench"
import "device/microbench"
local bench = tw.bench

local runs, profile, micro = 3, false, false
for _, a in ipairs(arg) do
	if a == "--profile" then profile = true
	elseif a == "--micro" then micro = true
	elseif tonumber(a) then runs = tonumber(a) end
end
local best
for i = 1, runs do
	local r = bench.run(os.clock)
	print(bench.line(r, "desktop run " .. i))
	if not best or r.seconds < best.seconds then best = r end
end
print(string.format("best: %.0f steps/s, %.1f ms per simulated second (%.3f ms/step)",
	best.stepsPerSecond, best.msPerSimSecond, best.msPerStep))
-- the same throw with a full turn's debris lying on the pitch (asleep)
local bestD
for i = 1, runs do
	local r = bench.run(os.clock, nil, nil, true)
	print(bench.line(r, "with debris run " .. i))
	if not bestD or r.seconds < bestD.seconds then bestD = r end
end
print(string.format("best with debris: %.0f steps/s, %.3f ms/step (%+.0f%%), collision phase %.3f ms/step (%+.0f%%)",
	bestD.stepsPerSecond, bestD.msPerStep, (bestD.msPerStep / best.msPerStep - 1) * 100,
	bestD.hotMsPerStep, (bestD.hotMsPerStep / best.hotMsPerStep - 1) * 100))
-- the match case's physics with the lone flight off and on
local world = tw.world
local lone = world.loneFlight
for _, on in ipairs { false, true } do
	world.loneFlight = on
	print(bench.matchPhysics(os.clock))
end
world.loneFlight = lone
if profile then
	for _, l in ipairs(bench.profile(os.clock)) do print(l) end
end
if micro then
	for _, l in ipairs(tw.microbench.lines(tw.microbench.run(os.clock, 2000000))) do print(l) end
end
