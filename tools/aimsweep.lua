-- Where a clean baton is aimed, and what it hits (Tyler's report, 2026-11-16:
-- "all of them went clean over the field kubb"). A lone standing kubb d m
-- straight out; the plan's clean throw at it (plan.solve, the field arc
-- unless --release, its centre aimed through the kubb at plan.aimZFor's
-- height), with the aim point moved along the line by a length error (m,
-- - short, + long), every tumble from 0.8 to 1.2 times the plan's and a few
-- ground seeds, each run to rest. Prints, for each range, the share that
-- toppled the kubb by length error and over all of them, and for the throws
-- that missed, how many went over it (the baton rests past it) or stopped
-- short.
--
--   lua5.4 tools/aimsweep.lua [--ranges 3,5.27,8] [--release 60] [--seeds 8]
--     [--surface grass] [--set plan.aimHeightShare=0]
-- --set plan.aimHeightShare=0 is the aim at the kubb's foot (before 2026-11-16).
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local sourceDir = here .. "/../source"
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(sourceDir .. "/" .. name .. ".lua"))()
end
import "core/tw"
import "core/world"
import "core/throwplan"

local world, plan = tw.world, tw.plan

local ranges, release, seeds, surface = { 3, 5.27, 8 }, 60, 8, "grass"
local i = 1
while i <= #arg do
	local a, v = arg[i], arg[i + 1]
	if a == "--ranges" then
		ranges = {}
		for x in v:gmatch("[^,]+") do ranges[#ranges + 1] = tonumber(x) end
		i = i + 1
	elseif a == "--release" then release = tonumber(v); i = i + 1
	elseif a == "--seeds" then seeds = tonumber(v); i = i + 1
	elseif a == "--surface" then surface = v; i = i + 1
	elseif a == "--set" then
		local key, val = v:match("^plan%.([%w_]+)=(.+)$")
		assert(key, "--set plan.name=value")
		plan.tune[key] = tonumber(val)
		i = i + 1
	end
	i = i + 1
end

local OFFS = { -0.4, -0.3, -0.2, -0.1, 0, 0.1, 0.2 }
local TUMBLE = { 0.8, 0.9, 1.0, 1.1, 1.2 }
local zAim = plan.aimZFor and plan.aimZFor("kubb") or 0
print(string.format("lone kubb, %s, release %d (loft %.0f), aim height %.3f m, %d seeds x %d tumbles a cell",
	surface, release, plan.loftFor(release), zAim, seeds, #TUMBLE))
for _, d in ipairs(ranges) do
	local row, hitAll, nAll, over, short = {}, 0, 0, 0, 0
	for _, off in ipairs(OFFS) do
		local hit, n = 0, 0
		for seed = 1, seeds do
			for _, f in ipairs(TUMBLE) do
				local sol = plan.solve({ projectile = "baton", px = 0, py = 0, tx = 0, ty = d + off,
					release = release, level = "club", aimZ = zAim }, {})
				local w = world.new { surface = surface, pieces = { { id = "k", kind = "kubb", x = 0, y = d } },
					stakes = false, groundSeed = seed }
				local b = world.launchBaton(w, 0, 0, sol.swivel, sol.loft, sol.speed, sol.tumble * f, 0)
				for _ = 1, 240 * 10 do
					world.step(w)
					if world.isAtRest(w) then break end
				end
				n = n + 1
				if w.byId.k.toppled then hit = hit + 1
				elseif b.y > d then over = over + 1
				else short = short + 1 end
			end
		end
		row[#row + 1] = string.format("%+.1f %3.0f%%", off, 100 * hit / n)
		hitAll, nAll = hitAll + hit, nAll + n
	end
	print(string.format("%5.2f m  %s  | all %.0f%%, missed over %d short %d of %d", d,
		table.concat(row, "  "), 100 * hitAll / nAll, over, short, nAll))
end
