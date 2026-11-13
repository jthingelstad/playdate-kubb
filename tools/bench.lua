-- The physics benchmark on the desktop (make bench). The same scenario as
-- the System Menu "Bench" item on the device: source/core/bench.lua.
--
--   lua5.4 tools/bench.lua [runs]

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end
import "core/bench"
local bench = tw.bench

local runs = tonumber(arg[1]) or 3
local best
for i = 1, runs do
	local r = bench.run(os.clock)
	print(bench.line(r, "desktop run " .. i))
	if not best or r.seconds < best.seconds then best = r end
end
print(string.format("best: %.0f steps/s, %.1f ms per simulated second (%.3f ms/step)",
	best.stepsPerSecond, best.msPerSimSecond, best.msPerStep))
