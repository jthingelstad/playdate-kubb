-- Keeps the recordings in the Data folder from growing without end: before a
-- line is appended to traces.jsonl or frames.jsonl, a file past maxBytes is
-- renamed to <name>-1.jsonl (replacing the older one) and a fresh one is
-- started, so each log holds at most about 2 x maxBytes on the device (Tyler's
-- play test of 2026-11-15 added 115 swings, about 150 KB of traces; a match is
-- about 200 to 250 KB of both). One file size check per line written.
import "core/tw"

local logcap = {
	maxBytes = 1000000,   -- bytes a log may reach before it is rotated
}

-- "traces.jsonl" -> "traces-1.jsonl"
function logcap.older(path)
	return (path:gsub("%.jsonl$", "-1.jsonl"))
end

-- Rotate path when it is past maxBytes. Never raises.
function logcap.check(path)
	local size = playdate.file.getSize(path)
	if size and size > logcap.maxBytes then
		local old = logcap.older(path)
		if playdate.file.exists(old) then playdate.file.delete(old) end
		playdate.file.rename(path, old)
	end
end

tw.logcap = logcap
