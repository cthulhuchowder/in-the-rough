extends SceneTree
## Carry calibration: for every club, a full-power straight shot (power 1, path 0) from the
## fairway, the rough and sand of the flat test hole in still air, through Ball.launch and the real
## physics; the horizontal distance to first landing is written into data/clubs/*.tres as
## carry_fairway / carry_rough / carry_sand (the club wheel and the auto caddy read them).
## Re-run after changing a club's launch numbers, the flight feel or how a lie affects a shot.
## Run: godot --headless --fixed-fps 120 --path game -s res://art/carry_calibration.gd

const LIES := { ## field → a spot on that surface of holes/test_hole.tscn, firing downrange (−Z)
	"carry_fairway": Vector3(0, 0, -40),
	"carry_rough": Vector3(35, 0, -40),
	"carry_sand": Vector3(-14, 0, -210),
}


func _initialize() -> void:
	var hole: Hole = load("res://holes/test_hole.tscn").instantiate()
	root.add_child(hole)
	hole.wind = Vector3.ZERO
	var ball: Ball = load("res://ball.tscn").instantiate() # alone, like the server's (no round, no camera)
	root.add_child(ball)
	ball.course = hole
	for i in 5:
		await physics_frame
	for club: ClubData in Clubs.ALL:
		if club.model == ClubData.Model.PUTTER:
			continue # it rolls: the wheel shows its longest putt instead
		var line := "%-3s" % club.label
		for field in LIES:
			ball.place(hole.rest_point(LIES[field], 0.05)) # resting on it, as a drop
			for i in 5:
				await physics_frame
			var lie := ball.lie.resource_name
			ball.launch(Vector3.FORWARD, 0.0, 1.0, club, Vector3.RIGHT)
			var ticks := 0
			while ball.carry < 0.0 and ticks < 120 * 20:
				await physics_frame
				ticks += 1
			club.set(field, snappedf(ball.carry, 0.1))
			line += "  %s %.1f m (%s)" % [field.trim_prefix("carry_"), ball.carry, lie]
		print(line)
		_write(club)
	quit()


func _write(club: ClubData) -> void:
	var path := ProjectSettings.globalize_path(club.resource_path)
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for k in lines.size():
		for field in LIES:
			if lines[k].begins_with(field + " = "):
				lines[k] = "%s = %s" % [field, str(club.get(field))]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
