-- Practice drills (the Drills board): what each drill sets up, how a run is
-- scored and the records kept. Pure: no playdate.*.
--
-- A run is a fixed number of throws on its own pitch. drills.setup(d, run)
-- gives the next throw as a core/match-style setup (pieces in the view frame,
-- the line, the projectile, the targets) for scenes/throw's prepare;
-- drills.tally(d, run, res) takes what the throw did ({ toppled = {ids},
-- restCm = n }) and says whether the run is over; drills.record(rec, d, run)
-- folds a finished run into the saved records.
import "core/tw"
import "core/pitch"

local pitch = tw.pitch

local drills = {}

local function standing(id, kind, x, y)
	return { id = id, kind = kind, role = kind == "king" and "king" or "base", x = x, y = y,
		qw = 1, qx = 0, qy = 0, qz = 0, toppled = false }
end

local BASE_X <const> = { -2, -1, 0, 1, 2 }

-- the drills, in the board's order. score: what one point is; of: the
-- points a run can make; throws: per run.
drills.list = {
	{ id = "8m", name = "8 METERS", lines = { "SIX BATONS", "FIVE BASE KUBBS", "FROM THE BASELINE" },
		throws = 6, of = 5, kind = "base" },
	{ id = "house", name = "THE HOUSE", lines = { "SIX BATONS", "FIVE FIELD KUBBS", "IN A HOUSE AT 4 M" },
		throws = 6, of = 5, kind = "house" },
	{ id = "king", name = "KING SHOTS", lines = { "SIX BATONS", "AT THE KING ALONE", "FROM THE BASELINE" },
		throws = 6, of = 6, kind = "king" },
	{ id = "blast", name = "BLAST", lines = { "SIX KUBBS DRILLED", "TO THE MARKER", "WITHIN HALF A METRE" },
		throws = 6, of = 6, kind = "blast" },
	{ id = "around", name = "AROUND THE PITCH", lines = { "FIVE BATONS", "ONE AT EACH BASE KUBB", "FROM IN FRONT OF IT" },
		throws = 5, of = 5, kind = "around" },
}

drills.tune = {
	blastCm = 50,          -- a drilled kubb resting this near the marker scores
	blastMarkerY = 6,      -- m from the baseline: BLAST's marker, fixed (scores stay comparable)
	house = { { 0.00, 4.20 }, { 0.10, 4.30 }, { -0.10, 4.32 }, { 0.03, 4.42 }, { -0.06, 4.52 } },
	lastN = 10,            -- the scores kept for LAST TEN
}

function drills.byId(id)
	for _, d in ipairs(drills.list) do if d.id == id then return d end end
	return nil
end

-- A new run of drill d.
function drills.newRun(d)
	return { id = d.id, n = 0, score = 0, down = {}, done = false }
end

-- The pieces standing for this run now (kubbs knocked down stay down; the
-- king is stood back up after each throw).
local function pieces(d, run)
	local out = {}
	if d.kind == "base" or d.kind == "around" then
		for i, x in ipairs(BASE_X) do
			local id = "b" .. i
			if not run.down[id] then out[#out + 1] = standing(id, "kubb", x, pitch.length) end
		end
	elseif d.kind == "house" then
		for i, p in ipairs(drills.tune.house) do
			local id = "f" .. i
			if not run.down[id] then out[#out + 1] = standing(id, "kubb", p[1], p[2]) end
		end
	end
	if d.kind ~= "blast" then out[#out + 1] = standing("king", "king", pitch.king.x, pitch.king.y) end
	return out
end

-- The next throw's setup, or nil when the run is over.
function drills.setup(d, run)
	if run.done then return nil end
	local ps = pieces(d, run)
	local s = { kind = "baton", side = "A", pieces = ps, lineY = 0, forwardY = 0, projectile = "baton",
		n = run.n + 1, of = d.throws, batonId = "baton" }
	local targets = {}
	for _, p in ipairs(ps) do
		if p.kind == "kubb" then targets[#targets + 1] = p.id end
	end
	if d.kind == "king" or #targets == 0 then targets = { "king" } end
	s.targets = targets
	if d.kind == "blast" then
		s.kind, s.projectile, s.kubb, s.targets = "toss", "kubb", "d1", nil
		s.markerX, s.markerY = 0, drills.tune.blastMarkerY   -- fixed: the d-pad does not move it
	elseif d.kind == "around" then
		-- from in front of the kubb whose turn it is (the next standing one)
		s.playerX = BASE_X[run.n + 1]
	end
	return s
end

-- What a throw did: res.toppled (ids), res.restCm (a drilled kubb's rest
-- from the marker). Returns true when the run is over.
function drills.tally(d, run, res)
	run.n = run.n + 1
	if d.kind == "blast" then
		if res.restCm and res.restCm <= drills.tune.blastCm then run.score = run.score + 1 end
	elseif d.kind == "king" then
		for _, id in ipairs(res.toppled or {}) do
			if id == "king" then run.score = run.score + 1 break end
		end
	else
		for _, id in ipairs(res.toppled or {}) do
			if id ~= "king" and not run.down[id] then
				run.down[id] = true
				run.score = run.score + 1
			end
		end
	end
	-- over after its throws, or when nothing is left standing to knock down
	if run.n >= d.throws or ((d.kind == "base" or d.kind == "house" or d.kind == "around") and run.score >= d.of) then
		run.done = true
	end
	return run.done
end

-- Records: { [id] = { best, runs, points, possible, last = {...} } }.
-- Folds a finished run in; returns the drill's record and whether it is a
-- new best.
function drills.record(rec, d, run)
	local r = rec[d.id]
	if not r then
		r = { best = 0, runs = 0, points = 0, possible = 0, last = {} }
		rec[d.id] = r
	end
	local best = run.score > r.best
	if best then r.best = run.score end
	r.runs, r.points, r.possible = r.runs + 1, r.points + run.score, r.possible + d.of
	r.last[#r.last + 1] = run.score
	while #r.last > drills.tune.lastN do table.remove(r.last, 1) end
	return r, best
end

-- A record's rate (whole percent of the points possible), or nil.
function drills.rate(r)
	if not r or r.possible == 0 then return nil end
	return math.floor(100 * r.points / r.possible + 0.5)
end

tw.drills = drills
