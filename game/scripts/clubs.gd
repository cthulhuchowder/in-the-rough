class_name Clubs
## The bag in key order (1-0 = driver..sand wedge, P = putter). Shots name clubs by index.

const ALL: Array[ClubData] = [
	preload("res://data/clubs/driver.tres"),
	preload("res://data/clubs/iron_3.tres"),
	preload("res://data/clubs/iron_4.tres"),
	preload("res://data/clubs/iron_5.tres"),
	preload("res://data/clubs/iron_6.tres"),
	preload("res://data/clubs/iron_7.tres"),
	preload("res://data/clubs/iron_8.tres"),
	preload("res://data/clubs/iron_9.tres"),
	preload("res://data/clubs/pitching_wedge.tres"),
	preload("res://data/clubs/sand_wedge.tres"),
	preload("res://data/clubs/putter.tres"),
]


## Auto caddy, in order: on the green the putter; in sand the sand wedge; on a hole's first shot
## the driver if the pin is beyond every other club's carry; else the club whose carry from this
## lie is closest to but not less than the distance to the pin, or the longest one (never the
## driver past the first shot). Bag order: driver first, sand wedge then putter last.
static func caddy_pick(clubs: Array, lie: SurfaceData, to_pin: float, first_shot: bool) -> int:
	var putter := clubs.size() - 1
	var kind := ClubData.lie_kind(lie)
	if kind == "green":
		return putter
	if kind == "sand":
		return putter - 1
	var best := -1
	var longest := 1
	for i in range(1, putter): # every club but the driver and the putter
		var carry: float = clubs[i].carry_for(lie)
		if carry > clubs[longest].carry_for(lie):
			longest = i
		if carry >= to_pin and (best < 0 or carry < clubs[best].carry_for(lie)):
			best = i
	if first_shot and to_pin > clubs[longest].carry_for(lie):
		return 0
	return best if best >= 0 else longest
