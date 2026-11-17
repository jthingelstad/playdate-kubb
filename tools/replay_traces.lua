-- Replay recorded crank traces through source/core/swing.lua.
--
--   lua5.4 tools/replay_traces.lua [--current-sign] <traces.jsonl> [...]
--
-- traces.jsonl is written by the game when "Record crank" is on in the System
-- Menu: in the Simulator at
-- ~/Developer/PlaydateSDK/Disk/Data/com.throwingwood.playdate/traces.jsonl,
-- on the device in Data/com.throwingwood.playdate/ (Data Disk mode).
-- Each line prints what the game recorded and what today's swing tunables
-- make of the same samples, so a tuning change can be checked against real
-- throws. The swing that wrote the line is in brackets ("clock", "stop", or
-- "pass" for lines without a "release" field). Lines written before the
-- crank as a clock (2026-11-15) usually end mid-swing under today's rules
-- (they stop at the old release): those are counted apart, not as
-- differing. A line differs when the event differs or a field both results
-- have is not the same. --current-sign replays the raw deltas with today's forwardSign
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

-- A result as one line: the crank as a clock's fields, or the older swing's
-- where a line recorded before 2026-11-15 has them in their place
-- (backswing for back, peakSpeed for flickDps). "-" for what is missing.
local function f(v, pat)
	if v == nil then return "-" end
	if type(v) == "number" then return string.format(pat, v) end
	return tostring(v)
end
local function show(r)
	if not r then return "-" end
	return string.format("back %s release %s flick %s (%s) smooth %s shake %s pull %s %s, %s frames",
		f(r.back or r.backswing, "%.0f"), f(r.releaseAngle, "%.1f"), f(r.flickDps or r.peakSpeed, "%.0f"),
		f(r.flickFrac, "%.2f"), f(r.smoothness, "%.2f"), f(r.shake, "%.2f"),
		f(r.pull, "%+d"), f(r.how, "%s"), f(r.frames, "%d"))
end

-- Fields both results have under the same name, and how far apart they may be.
local COMPARE = { back = 0.5, releaseAngle = 0.5, flickDps = 1, flickFrac = 0.01, smoothness = 0.01,
	pull = 0, frames = 0 }
local function differs(ev, r, t)
	if ev ~= t.event then return true end
	local rec = t.result
	if not (r and rec) then return false end
	for k, tol in pairs(COMPARE) do
		if type(r[k]) == "number" and type(rec[k]) == "number" and math.abs(r[k] - rec[k]) > tol then
			return true
		end
	end
	return false
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

local n, differ, midSwing = 0, 0, 0
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
			print("  recorded: " .. tostring(t.event) .. "  " .. show(rec)
				.. (t.release and (" [" .. t.release .. "]") or " [pass]"))
			print("  replayed: " .. tostring(ev) .. "  " .. show(r))
			if ev == nil and t.release ~= "clock" then
				midSwing = midSwing + 1
				print("  (ends mid-swing under today's swing)")
			elseif differs(ev, r, t) then
				differ = differ + 1
				print("  (differs)")
			end
		end
	end
	f:close()
end
print(string.format("%d traces, %d replay differently, %d older lines end mid-swing", n, differ, midSwing))
