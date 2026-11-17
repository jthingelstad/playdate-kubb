# Kubb: Throwing Wood. Full SDK paths; PLAYDATE_SDK_PATH is not needed.

SDK      := $(HOME)/Developer/PlaydateSDK
PDC      := $(SDK)/bin/pdc
SIM      := $(SDK)/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator
GAMEDATA := $(SDK)/Disk/Data/com.throwingwood.playdate
SIMDATA  := $(GAMEDATA)/selftest
LUA      := /opt/homebrew/opt/lua@5.4/bin/lua5.4
NODE     := /opt/homebrew/bin/node
# pk-kubb-score: the sibling checkout, else its home in the throwingwood folder (for worktrees elsewhere).
PKSCORE  := $(or $(PK_KUBB_SCORE),$(firstword $(wildcard $(CURDIR)/../pk-kubb-score) $(HOME)/Projects/throwingwood/pk-kubb-score))

PDX      := build/ThrowingWood.pdx
OUT      := $(CURDIR)/build/selftest
# Whole-match scenarios (cards, match-whole) play at the Simulator's pace: cards took
# 163 s on 2026-11-16, so 60 s timed out runs that were only slow.
SIM_TIMEOUT := 300

# Every source/selftest/*.lua is a scenario except the runner and helpers named _*.
SCENARIOS := $(filter-out runner _%,$(basename $(notdir $(wildcard source/selftest/*.lua))))
SOURCES   := $(shell find source -type f)

.PHONY: sync-notation vendor-sync vendor-check build test test-lua test-node games realgames physfuzz mjref selftest bench clean release

build: $(PDX)

$(PDX): $(SOURCES)
	@mkdir -p build
	"$(PDC)" -sdkpath "$(SDK)" -q source $(PDX)

test: vendor-check test-lua test-node

# source/core is kubb-engine's core/ at the tag in engine-core.json, byte for
# byte (tools/vendor-engine.mjs). Never edit it: fix the engine, tag, then
# `make vendor-sync TAG=vX.Y.Z`. The engine is read from $(KUBB_ENGINE) or
# ../kubb-engine through git, at the tag.
TAG ?=
vendor-sync:
	"$(NODE)" tools/vendor-engine.mjs sync $(TAG)
	git --no-pager diff --stat -- source/core engine-core.json

vendor-check:
	"$(NODE)" tools/vendor-engine.mjs check

test-lua:
	"$(LUA)" tests/lua/run.lua

test-node:
	"$(NODE)" tests/node/notation-gate.mjs tests/fixtures/games
	"$(NODE)" tests/node/gate-rejects.mjs

# The core's tests and measuring tools moved to kubb-engine with the core.
games realgames physfuzz mjref:
	@echo "make $@ lives in kubb-engine now (with the core's tests and tools): run it there"; exit 2

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
# pair in source/device/version.lua (the title shows it): the release stops
# first when the two disagree.
VERSION := $(shell sed -n 's/^version=//p' source/pdxinfo)
release:
	"$(LUA)" tests/lua/run.lua tests/lua/test_version.lua
	$(MAKE) clean
	$(MAKE) build
	cd build && zip -qr -X ThrowingWood-$(VERSION).pdx.zip ThrowingWood.pdx -x '*.DS_Store'
	@echo "build/ThrowingWood-$(VERSION).pdx.zip"

# Refresh the vendored notation parser and scorer (the gate over the game files
# the self-tests write) from a pk-kubb-score checkout, then show what changed.
# Review, run `make test`, commit.
sync-notation:
	cp "$(PKSCORE)/site/assets/notation-parser.js" "$(PKSCORE)/site/assets/kubb.js" tests/vendor/pk-kubb-score/
	git --no-pager diff --stat -- tests/vendor/pk-kubb-score
