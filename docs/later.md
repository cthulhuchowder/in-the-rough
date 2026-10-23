# Later

Ideas parked outside the current phase's scope (see the Phase 3 caps in `docs/plan.md`).

## Phase 3 shop ideas

- **Pupil painter:** a tiny in-game pixel paint tool (32×32, limited palette) that writes a
  texture into the eye material slot; unlocked with coins; synced to other players as a small
  byte blob. Depends on: eye material slot (done 3.1), skin/look resources (3.3), coin economy
  (3.2).

## Modes

- **Mini golf:** putter only, on custom hand-built obstacle holes (ramps, loops, windmills,
  bank walls). Reuses the putting physics and the rim ride; needs a hole format for authored
  obstacles beside the procgen terrain.
- **Campaign:** 18 hand-authored holes across the biomes (parkland first, then the others as they
  land), played in order with par targets and unlocks. Depends on more than one biome (3.2) and an
  authored-hole pipeline.
- **Lobby custom rules:** the room host picks rules before Start — club limits (e.g. putter only,
  three clubs), wind on/off or fixed, mulligans, stroke cap, gimme distance, hole count. Server
  enforces them; shown in the lobby and on the scorecard.
