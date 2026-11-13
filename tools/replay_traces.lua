-- Replay recorded crank traces through source/core/swing.lua.
--
--   lua5.4 tools/replay_traces.lua [--current-sign] <traces.jsonl> [...]
--
-- traces.jsonl is written by the game when "Record crank" is on in the System
-- Menu: in the Simulator at
-- ~/Developer/PlaydateSDK/Disk/Data/com.thingelstad.throwingwood/traces.jsonl,
-- on the device in Data/com.thingelstad.throwingwood/ (Data Disk mode).
-- Each line prints what the game recorded and what today's swing tunables
-- make of the same samples, so a tuning change can be checked against real
-- throws. --current-sign replays the raw deltas with today's forwardSign
-- instead of the sign they were recorded with.

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end
import "core/trace"
local trace = tw.trace

local function show(r)
	if not r then return "-" end
	return string.format("power %.2f smooth %.2f tilt %4.1f %-10s %d frames %s",
		r.power or 0, r.smoothness or 0, r.tilt or 0, r.legal and "LEGAL" or "HELICOPTER",
		r.frames or 0, r.how or "")
end

local useCurrent = false
local files = {}
for _, a in ipairs(arg) do
	if a == "--current-sign" then useCurrent = true else files[#files + 1] = a end
end
if #files == 0 then
	io.stderr:write("usage: lua5.4 tools/replay_traces.lua [--current-sign] <traces.jsonl> ...\n")
	os.exit(2)
end

local n, differ = 0, 0
for _, path in ipairs(files) do
	local f = assert(io.open(path))
	for line in f:lines() do
		if line:match("%S") then
			n = n + 1
			local t = trace.decode(line)
			local ev, r = trace.replay(t, useCurrent)
			local rec = t.result
			print(string.format("#%d %s %d samples%s", n, t.time or "", #(t.samples or {}),
				rec and rec.distance and string.format(", landed %.2f m at loft %s", rec.distance, tostring(rec.loft)) or ""))
			print("  recorded: " .. tostring(t.event) .. "  " .. show(rec))
			print("  replayed: " .. tostring(ev) .. "  " .. show(r))
			if ev ~= t.event or (r and rec and (math.abs(r.power - rec.power) > 0.01 or r.legal ~= rec.legal)) then
				differ = differ + 1
				print("  (differs)")
			end
		end
	end
	f:close()
end
print(string.format("%d traces, %d replay differently", n, differ))
