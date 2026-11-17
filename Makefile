# Kubb: Throwing Wood. Full SDK paths; PLAYDATE_SDK_PATH is not needed.

SDK      := $(HOME)/Developer/PlaydateSDK
PDC      := $(SDK)/bin/pdc
SIM      := $(SDK)/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator
GAMEDATA := $(SDK)/Disk/Data/com.thingelstad.throwingwood
SIMDATA  := $(GAMEDATA)/selftest
LUA      := /opt/homebrew/opt/lua@5.4/bin/lua5.4
NODE     := /opt/homebrew/bin/node
PKSCORE  := $(or $(PK_KUBB_SCORE),$(HOME)/Projects/pk-kubb-score)

PDX      := build/ThrowingWood.pdx
OUT      := $(CURDIR)/build/selftest
# Whole-match scenarios (cards, match-whole) play at the Simulator's pace: cards took
# 163 s on 2026-11-16, so 60 s timed out runs that were only slow.
SIM_TIMEOUT := 300

# Every source/selftest/*.lua is a scenario except the runner and helpers named _*.
SCENARIOS := $(filter-out runner _%,$(basename $(notdir $(wildcard source/selftest/*.lua))))
SOURCES   := $(shell find source -type f)

.PHONY: sync-notation build test test-lua test-node games realgames selftest bench clean release

build: $(PDX)

$(PDX): $(SOURCES)
	@mkdir -p build
	"$(PDC)" -sdkpath "$(SDK)" -q source $(PDX)

test: test-lua test-node

test-lua:
	"$(LUA)" tests/lua/run.lua

test-node:
	"$(NODE)" tests/node/notation-gate.mjs tests/fixtures/games
	"$(NODE)" tests/node/gate-rejects.mjs
	"$(NODE)" tools/realgames.mjs tests/fixtures/games tests/fixtures/games > /dev/null

# Headless games: GAMES_N seeded random games through the rules engine
# (tools/games.lua, no physics) into build/games, then the notation gate over
# all of them. Same seed, same files.
GAMES_N    := 500
GAMES_SEED := 1

#
# Then PHYS_N matches with real physics (tools/physmatch.lua: core/match
# driven by core/autothrow, every throw run by core/world, the match scene's
# path without the screen) into build/physgames, gated the same way.
PHYS_N := 5

games:
	@rm -rf build/games build/physgames
	"$(LUA)" tools/games.lua --n $(GAMES_N) --seed $(GAMES_SEED) --out build/games
	"$(NODE)" tests/node/notation-gate.mjs build/games
	"$(LUA)" tools/physmatch.lua --n $(PHYS_N) --seed $(GAMES_SEED) --out build/physgames
	"$(NODE)" tests/node/notation-gate.mjs build/physgames

# Real games against the game's own (tools/realgames.mjs): REAL_N physics
# matches into build/realgames, then the same figures from them and from the
# games people scored in a pk-kubb-score checkout (read only; not on GitHub).
REAL_N    := 150
REAL_SEED := 2
REAL_SCATTER := 1

realgames:
	@test -d "$(PKSCORE)/games" || { echo "realgames: no games folder in a pk-kubb-score checkout (set PK_KUBB_SCORE)"; exit 1; }
	@rm -rf build/realgames
	"$(LUA)" tools/physmatch.lua --n $(REAL_N) --seed $(REAL_SEED) --scatter $(REAL_SCATTER) --out build/realgames
	"$(NODE)" tools/realgames.mjs "$(PKSCORE)/games" build/realgames

# Each scenario is its own Simulator launch, killed after SIM_TIMEOUT seconds.
# The runner writes its marker in the game's Data folder (the only place Lua
# can write a text file); this copies it into build/selftest and fails unless
# it says DONE and every frame it counted exists at 400x240 and 800x480.
# A marker that names a game file (file=games/...: match-whole) has that file
# copied into build/selftest/games, and the notation gate runs over them.
selftest: build
	@rm -rf build/selftest
	@mkdir -p build/selftest
	@fail=0; for s in $(SCENARIOS); do \
	  rm -f "$(SIMDATA)/$$s.done"; \
	  start=$$(date +%s); \
	  timeout -k 5 $(SIM_TIMEOUT) "$(SIM)" "$(CURDIR)/$(PDX)" selftest=$$s out="$(OUT)" > "$(OUT)/$$s.log" 2>&1; \
	  rc=$$?; secs=$$(( $$(date +%s) - start )); \
	  if [ $$rc -eq 124 ] || [ $$rc -eq 137 ]; then \
	    if grep -q '^DONE' "$(SIMDATA)/$$s.done" 2>/dev/null; then echo "selftest $$s: the Simulator hung after DONE (exit $$rc); counted by its marker"; \
	    else echo "selftest $$s: TIMEOUT after $(SIM_TIMEOUT)s (log: build/selftest/$$s.log)"; fail=1; continue; fi; \
	  fi; \
	  if [ ! -f "$(SIMDATA)/$$s.done" ]; then echo "selftest $$s: no marker (Simulator exit $$rc; log: build/selftest/$$s.log)"; fail=1; continue; fi; \
	  cp "$(SIMDATA)/$$s.done" "$(OUT)/$$s.done"; \
	  status=$$(cat "$(OUT)/$$s.done"); \
	  case "$$status" in DONE*) ;; *) echo "selftest $$s: $$status"; fail=1; continue;; esac; \
	  n=$$(echo "$$status" | sed -n 's/.*frames=\([0-9]*\).*/\1/p'); \
	  if [ -z "$$n" ] || [ "$$n" -lt 1 ]; then echo "selftest $$s: no frames saved"; fail=1; continue; fi; \
	  for i in $$(seq -f %02g 1 $$n); do \
	    for f in "$$s-$$i.png:400x240" "$$s-$$i@2x.png:800x480"; do \
	      png=$${f%%:*}; want=$${f##*:}; \
	      if [ ! -f "$(OUT)/$$png" ]; then echo "selftest $$s: missing $$png"; fail=1; continue; fi; \
	      got=$$(sips -g pixelWidth -g pixelHeight "$(OUT)/$$png" | awk '/pixelWidth/{w=$$2} /pixelHeight/{h=$$2} END{print w "x" h}'); \
	      if [ "$$got" != "$$want" ]; then echo "selftest $$s: $$png is $$got, want $$want"; fail=1; else echo "  $$png $$got"; fi; \
	    done; \
	  done; \
	  echo "selftest $$s: $$status in $${secs}s"; \
	  gf=$$(echo "$$status" | sed -n 's/.* file=\([^ ]*\).*/\1/p'); \
	  if [ -n "$$gf" ]; then mkdir -p "$(OUT)/games"; cp "$(GAMEDATA)/$$gf" "$(OUT)/games/" || fail=1; fi; \
	done; \
	if [ -d "$(OUT)/games" ]; then "$(NODE)" tests/node/notation-gate.mjs "$(OUT)/games" || fail=1; fi; \
	exit $$fail

# The reference-engine comparison (tools/mjref, AGENTS.md "Reference engine"):
# the same throws through core/world and MuJoCo, the report in build/mjref.
# MJPY is a Python with mujoco and numpy (python3 -m venv <dir>, then
# <dir>/bin/pip install mujoco numpy; make mjref MJPY=<dir>/bin/python).
MJPY  ?= python3
MJREF := build/mjref

.PHONY: mjref
mjref:
	@mkdir -p $(MJREF)
	"$(LUA)" tools/mjref/export.lua $(MJREF)
	"$(LUA)" tools/mjref/ours.lua $(MJREF)
	"$(MJPY)" tools/mjref/mjsim.py $(MJREF)
	"$(MJPY)" tools/mjref/compare.py $(MJREF)

# The physics benchmark on the desktop (the device runs the same scenario from
# the System Menu "Bench" item).
bench:
	"$(LUA)" tools/bench.lua

clean:
	rm -rf build

# A build for friends to sideload (play.date/account/sideload takes a zipped
# .pdx): from a clean build/, so nothing stale rides along, zipped as
# build/ThrowingWood-<version>.pdx.zip. Raise buildNumber in source/pdxinfo for
# each one, or a Playdate that has the last one will not take it, and the same
# pair in source/core/version.lua (the title shows it; the web gets it through
# its vendor sync): the release stops first when the two disagree.
VERSION := $(shell sed -n 's/^version=//p' source/pdxinfo)
release:
	"$(LUA)" tests/lua/run.lua tests/lua/test_version.lua
	$(MAKE) clean
	$(MAKE) build
	cd build && zip -qr -X ThrowingWood-$(VERSION).pdx.zip ThrowingWood.pdx -x '*.DS_Store'
	@echo "build/ThrowingWood-$(VERSION).pdx.zip"

# Refresh the vendored notation parser and scorer from a pk-kubb-score checkout,
# then show what changed. Review, run `make test` and `make games`, commit.
sync-notation:
	cp "$(PKSCORE)/site/assets/notation-parser.js" "$(PKSCORE)/site/assets/kubb.js" tests/vendor/pk-kubb-score/
	git --no-pager diff --stat -- tests/vendor/pk-kubb-score
