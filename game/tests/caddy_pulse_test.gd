extends SceneTree
## Caddy pulse: a pick pulses the HUD's club chip. At tee-off the pick comes during the flyover (HUD
## hidden): the pulse waits until the HUD has faded back in (hud_fade after the flyover ends), then
## runs and settles back; a new pick restarts it.
## Game time at a fixed 120 fps (script runs skip the real flyover; a stand-in plays its part).
## Run: godot --headless --fixed-fps 120 --path game -s res://tests/caddy_pulse_test.gd

const FLYOVER: FlyoverParams = preload("res://data/flyover.tres")

var _failed := false
var _main: Node


func _check(ok: bool, what: String) -> void:
	_failed = _failed or not ok
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	_main.random_course = false
	root.add_child(_main)
	for i in 5:
		await physics_frame
	_main.load_hole(load("res://holes/test_hole.tscn").instantiate())
	await _wait(1.0)
	var hud: Hud = _main._hud
	if hud.pulse_tween:
		hud.pulse_tween.kill()

	# Tee-off: the pick comes during the flyover
	_main._flyover = Flyover.new() # stand-in: a flyover is playing
	_new_lie(Vector3(0, 0, -40))
	await _wait(1.0)
	var during := hud.pulse_tween != null and hud.pulse_tween.is_valid()
	_main._flyover_done()
	await _wait(FLYOVER.hud_fade * 0.6)
	var fading := hud.pulse_tween != null and hud.pulse_tween.is_valid()
	await _wait(FLYOVER.hud_fade * 0.4 + 0.15)
	var shown_scale := hud.chip_scale()
	_check(not during and not fading and shown_scale > 1.02, "no pulse during the flyover (%s) nor the HUD fade-in (%s); then it pulses (chip ×%.2f)" % [
		during, fading, shown_scale])
	await _wait(5.0)
	_check(is_equal_approx(hud.chip_scale(), 1.0) and not hud.pulse_tween.is_running(), "it settles back (chip ×%.2f)" % hud.chip_scale())

	# A new pick restarts it
	_new_lie(Vector3(0, 0, -60))
	await _wait(0.2)
	var first := hud.pulse_tween
	_new_lie(Vector3(0, 0, -80))
	await _wait(0.1)
	_check(not first.is_valid() and hud.pulse_tween.is_running(), "a new pick restarts the pulse")
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _new_lie(at: Vector3) -> void:
	_main._ball.place(_main._hole.rest_point(at, 0.05))
	_main._address()


## Game seconds, counted in frames (fixed 120 fps).
func _wait(seconds: float) -> void:
	for i in roundi(seconds * 120.0):
		await process_frame
