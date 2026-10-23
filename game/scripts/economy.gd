class_name Economy
## Coins per hole (docs/plan.md Phase 3), worked out on the server: a base by par for a holed ball
## (none when picked up), a bonus per stroke under par, a hole-in-one bonus, and the room's longest
## drive (first shot, par 4 and 5) and closest to the pin (par 3 tee shot on the green). Offline
## (single player) pays `share` of each. Values in data/economy.tres.

const PARAMS: EconomyParams = preload("res://data/economy.tres")
const CATEGORIES := ["base", "under_par", "hole_in_one", "longest_drive", "closest_to_pin"]
const NAMES := {base = "Hole", under_par = "Under par", hole_in_one = "Hole in one", longest_drive = "Longest drive",
	closest_to_pin = "Closest to pin"}


## {base, under_par, hole_in_one, longest_drive, closest_to_pin, total} for one player's hole.
static func award(par: int, score: int, picked_up: bool, longest: bool, closest: bool, share := 1.0) -> Dictionary:
	var p := PARAMS
	var out := {base = 0, under_par = 0, hole_in_one = 0, longest_drive = 0, closest_to_pin = 0}
	if not picked_up and score > 0:
		out.base = [0, 0, 0, p.base_par3, p.base_par4, p.base_par5][clampi(par, 3, 5)]
		out.under_par = maxi(par - score, 0) * p.under_par_per_stroke
		out.hole_in_one = p.hole_in_one if score == 1 else 0
	out.longest_drive = p.longest_drive if longest else 0
	out.closest_to_pin = p.closest_to_pin if closest else 0
	var total := 0
	for k in CATEGORIES:
		out[k] = int(floor(out[k] * share))
		total += out[k]
	out.total = total
	return out


## Category sums of `awards` (round totals).
static func add(into: Dictionary, award_: Dictionary) -> Dictionary:
	for k in CATEGORIES + ["total"]:
		into[k] = int(into.get(k, 0)) + int(award_.get(k, 0))
	return into
