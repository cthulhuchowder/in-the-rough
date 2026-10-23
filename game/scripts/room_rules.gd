class_name RoomRules
## A room's custom rules, as the plain Dictionary that travels over the network:
## {holes, shot_clock (s, 0 = off), wind (0 off / 1 normal / 2 strong), mulligans (per round),
## gimme (m, 0 = off), biome (BIOMES: 0 mixed, else one biome)}. The host picks them in the lobby;
## the server cleans what it is sent.

const HOLES := [3, 6, 9, 18]
const SHOT_CLOCK := [0, 30, 60, 90] ## the lobby's choices; the server takes any whole 0..SHOT_CLOCK_MAX
const SHOT_CLOCK_MAX := 300
const WIND := ["Off", "Normal", "Strong"]
const MULLIGANS := [0, 1, 2, 3]
const GIMME := [0.0, 0.5, 1.0]
const BIOMES := ["Mixed", "Parkland", "Oasis", "Underwater", "Magma", "Mystic forest", "Deep forest", "Cemetery"] ## 0: mixed; k: ProcgenParams.biomes[k − 1] for the whole course


static func defaults(holes := 9) -> Dictionary:
	return {holes = holes, shot_clock = 0, wind = 1, mulligans = 0, gimme = 0.0, biome = 0}


## Untrusted input → valid rules: anything missing or out of range falls back to `base`'s value.
static func clean(wanted: Variant, base: Dictionary) -> Dictionary:
	var out := base.duplicate()
	if not wanted is Dictionary:
		return out
	var w: Dictionary = wanted
	if int(w.get("holes", -1)) in HOLES:
		out.holes = int(w.holes)
	var clock := int(w.get("shot_clock", -1))
	if clock >= 0 and clock <= SHOT_CLOCK_MAX:
		out.shot_clock = clock
	if int(w.get("wind", -1)) in range(WIND.size()):
		out.wind = int(w.wind)
	if int(w.get("mulligans", -1)) in MULLIGANS:
		out.mulligans = int(w.mulligans)
	var gimme := float(w.get("gimme", -1.0))
	for g in GIMME:
		if is_equal_approx(gimme, g):
			out.gimme = g
	if int(w.get("biome", -1)) in range(BIOMES.size()):
		out.biome = int(w.biome)
	return out


## "9 holes · shot clock 30 s · wind strong · 2 mulligans · gimme 1 m"
static func describe(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	var parts := ["%d holes" % int(r.holes)]
	parts.append("shot clock %d s" % int(r.shot_clock) if int(r.shot_clock) > 0 else "no shot clock")
	parts.append("wind %s" % WIND[int(r.wind)].to_lower())
	var m := int(r.mulligans)
	parts.append("no mulligans" if m == 0 else "%d mulligan%s" % [m, "" if m == 1 else "s"])
	parts.append("gimme %s m" % str(float(r.gimme)) if float(r.gimme) > 0.0 else "no gimmes")
	var biome := int(r.get("biome", 0))
	parts.append("mixed biomes" if biome == 0 else BIOMES[biome].to_lower())
	return " · ".join(parts)


## How much of the hole's generated wind blows under these rules.
static func wind_scale(r: Dictionary, rules: RulesData) -> float:
	return [0.0, 1.0, rules.wind_strong_scale][int(r.get("wind", 1))]
