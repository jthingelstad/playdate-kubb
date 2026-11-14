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
SIM_TIMEOUT := 60

# Every source/selftest/*.lua is a scenario except the runner and helpers named _*.
SCENARIOS := $(filter-out runner _%,$(basename $(notdir $(wildcard source/selftest/*.lua))))
SOURCES   := $(shell find source -type f)

# Refresh the vendored notation parser and scorer from a pk-kubb-score checkout,
# then show what changed. Review, run `make test` and `make games`, commit.
sync-notation:
	cp "$(PKSCORE)/site/assets/notation-parser.js" "$(PKSCORE)/site/assets/kubb.js" tests/vendor/pk-kubb-score/
	git --no-pager diff --stat -- tests/vendor/pk-kubb-score

.PHONY: sync-notation build test test-lua test-node games selftest bench clean

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
	  if [ $$rc -eq 124 ] || [ $$rc -eq 137 ]; then echo "selftest $$s: TIMEOUT after $(SIM_TIMEOUT)s (log: build/selftest/$$s.log)"; fail=1; continue; fi; \
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

# The physics benchmark on the desktop (the device runs the same scenario from
# the System Menu "Bench" item).
bench:
	"$(LUA)" tools/bench.lua

clean:
	rm -rf build
