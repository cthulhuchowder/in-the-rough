class_name ShopScene
extends Node3D
## The shop's fitting room (main menu → Shop): the player's golfer on a slow turntable, the ball on a
## little stand beside it, and over them tabs Hat / Shirt / Pants / Shoes / Ball / Club set. Each tab
## lists its items as cards — a swatch, the name, the price, owned / equipped — with Buy or Equip.
## Hovering a card shows it on the golfer at once; clicking one keeps it shown. Online (the game
## server answers) the server holds the coins and checks every buy and equip; offline the local
## profile does, with the same rules (ShopCatalog). Equip also saves the look for the player's own
## golfer (ShopCatalog.save_my_look); online the server keeps it for everyone else to see.

static var player_name := "Player" ## from the menu's name field
const SOUNDS: SoundParams = preload("res://data/sounds.tres")

const FEEDBACK: FeedbackParams = preload("res://data/feedback.tres")
const CHARACTER: CharacterParams = preload("res://data/character.tres")
const FEEL: SwingFeel = preload("res://data/swing_feel.tres")
const SPIN := 0.35 ## rad/s, the turntable

var online := false
var balance := 0
var _sound := AudioStreamPlayer.new() # buy and equip
var _asked: AudioStream = null # online: the sound for the request in flight, played if the server agrees
var owned: Array = []
var equipped := {}
var tab := 0
var _rig: GolferRig
var _table := Node3D.new()
var _angle := 0.0 # the turntable's turn
var _ball_view := MeshInstance3D.new()
var _camera := Camera3D.new()
var _ui := CanvasLayer.new()
var _cards := HFlowContainer.new()
var _tabs := TabBar.new()
var _balance := Label.new()
var _status := Label.new()
var _selected := "" # the card picked on this tab (kept on the golfer; hovering shows others meanwhile)
var _demo := MeshInstance3D.new() # the Trail tab: a ball flying an arc over and over, its trail behind it
var _demo_trail := BallTrail.new()
var _demo_t := 0.0
const DEMO := 2.8 ## s per demo shot (1.6 in the air)


func _ready() -> void:
	add_child(load("res://art/presets/overcast.tscn").instantiate())
	var floor_mesh := MeshInstance3D.new()
	var floor_disc := CylinderMesh.new()
	floor_disc.top_radius = 12.0
	floor_disc.bottom_radius = 12.0
	floor_disc.height = 0.1
	floor_mesh.mesh = floor_disc
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.42, 0.5, 0.4)
	floor_disc.material = floor_mat
	floor_mesh.position.y = -0.05
	add_child(floor_mesh)
	var plate := MeshInstance3D.new() # the turntable
	var plate_mesh := CylinderMesh.new()
	plate_mesh.top_radius = 1.1
	plate_mesh.bottom_radius = 1.2
	plate_mesh.height = 0.12
	plate_mesh.radial_segments = 24
	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.78, 0.76, 0.7)
	plate_mesh.material = plate_mat
	plate.mesh = plate_mesh
	plate.position.y = 0.06
	add_child(plate)
	_table.position.y = 0.12
	add_child(_table)
	_rig = GolferRig.new(CHARACTER, ShopCatalog.my_look())
	add_child(_rig) # (not on the turning table: the rig poses in world space; _process turns it as one)
	var stand := MeshInstance3D.new() # the ball's little stand
	var stand_mesh := CylinderMesh.new()
	stand_mesh.top_radius = 0.12
	stand_mesh.bottom_radius = 0.16
	stand_mesh.height = 0.9
	stand_mesh.material = plate_mat
	stand.mesh = stand_mesh
	stand.position = Vector3(1.7, 0.45, 0.2)
	add_child(stand)
	_ball_view.position = Vector3(1.7, 0.97, 0.2)
	_ball_view.scale = Vector3.ONE * 3.0 # (a ball is small; shown large)
	add_child(_ball_view)
	_demo.mesh = Ball.view_mesh()
	_demo.scale = Vector3.ONE * 2.0
	_demo.visible = false
	add_child(_demo)
	_demo_trail.ground_y = 0.0
	add_child(_demo_trail)
	_camera.fov = 45.0
	add_child(_camera)
	_camera.look_at_from_position(Vector3(-0.9, 1.45, 4.8), Vector3(-1.15, 0.95, 0.0)) # (the golfer right of the panel)
	_camera.make_current()
	_build_ui()
	_sound.bus = Settings.SFX_BUS
	add_child(_sound)
	_status.text = "Connecting…"
	Net.shop_changed.connect(_on_server)
	Net.connected.connect(func() -> void: Net.shop_open.rpc_id(1, player_name), CONNECT_ONE_SHOT)
	Net.connection_failed.connect(func(_why: String) -> void: _go_offline(), CONNECT_ONE_SHOT)
	Net.connect_to_server()
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if not online:
			_go_offline())
	_show_look()


## The table turns, and the golfer with it as one piece: idle it is turned by its transform, at
## address (the Club set tab, club in hand) by its aim — the rig poses in world space, so it stands
## on the scene, not on the table, and every point it uses (feet, ball, head's look) turns together.
func _process(delta: float) -> void:
	_angle += SPIN * delta
	_table.rotation.y = _angle
	_ball_view.rotate_y(SPIN * 1.6 * delta)
	var feet := _table.global_position
	if tab == ShopItem.Tab.CLUB:
		var aim := Vector3.RIGHT.rotated(Vector3.UP, _angle)
		var side := (-aim).cross(Vector3.UP)
		_rig.address(feet, aim, feet - side * _rig.club.stance_dist + Vector3.UP * ClubModel.BALL_RADIUS)
		_rig.pose_swing(FEEL.address_angle, 0.0)
	else:
		_rig.transform = Transform3D(Basis(Vector3.UP, _angle), feet)
		_rig.pose_idle()
	_demo.visible = tab == ShopItem.Tab.TRAIL
	if _demo.visible: # the demo shot: up from beside the golfer, over toward the stand, landing and rolling
		var was := _demo_t
		_demo_t = fmod(_demo_t + delta, DEMO)
		if _demo_t < was:
			_demo_trail.start(Vector3(-0.5, 0.05, -0.8), 0.9)
		var t := minf(_demo_t, 1.6)
		var roll := maxf(_demo_t - 1.6, 0.0)
		_demo.position = Vector3(-0.5 + 1.6 * t + 0.4 * (1.0 - exp(-roll * 3.0)), 0.05 + 4.6 * t - 2.875 * t * t, -0.8 - 0.8 * t)
		Ball.spin(_demo, Vector3(1.6, 0.0, -0.8), delta)
		_demo_trail.feed(_demo.position)
	else:
		_demo_trail.clear()


func _go_offline() -> void:
	if online or _status.text != "Connecting…":
		return
	var me := ProfileStore.mine()
	balance = int(me.balance)
	owned = me.get("owned", [])
	equipped = me.get("equipped", {})
	_status.text = "Offline: your coins on this computer"
	multiplayer.multiplayer_peer = null
	_refresh()


func _on_server(new_owned: Array, new_equipped: Dictionary, why: String) -> void:
	online = true
	balance = Net.balance
	owned = new_owned
	equipped = new_equipped
	_status.text = why if why != "" else "Online"
	if why == "" and _asked != null:
		_ding(_asked) # (the server said yes)
	_asked = null
	ShopCatalog.save_my_look(equipped) # (what the server says is worn)
	_refresh()


## Bought or put on: its sound (data/sounds.tres).
func _ding(stream: AudioStream) -> void:
	_sound.stream = stream
	_sound.volume_db = SOUNDS.shop_db
	_sound.play()


func _buy(item_id: String) -> void:
	if online:
		_asked = SOUNDS.shop_buy
		Net.shop_buy.rpc_id(1, player_name, item_id)
		return
	var me := ProfileStore.mine()
	var why := ShopCatalog.buy(me, item_id)
	if why == "":
		me.pending_buys = me.get("pending_buys", []) + [item_id] # (bought again on the server at the next connect)
		ProfileStore.offline().save()
		_ding(SOUNDS.shop_buy)
	_status.text = why if why != "" else "Bought"
	_go_offline_refresh()


func _equip(item_id: String) -> void:
	if online:
		_asked = SOUNDS.shop_equip
		Net.shop_equip.rpc_id(1, player_name, tab, item_id)
		return
	var me := ProfileStore.mine()
	var why := ShopCatalog.equip(me, tab, item_id)
	if why == "":
		me.equip_dirty = true
		ProfileStore.offline().save()
		ShopCatalog.save_my_look(me.equipped)
		_ding(SOUNDS.shop_equip)
	_status.text = why if why != "" else "Equipped"
	_go_offline_refresh()


func _go_offline_refresh() -> void:
	var me := ProfileStore.mine()
	balance = int(me.balance)
	owned = me.get("owned", [])
	equipped = me.get("equipped", {})
	_refresh()


## The golfer and ball in what is worn, with the previewed item (hovered or picked) on top.
func _show_look() -> void:
	var wearing := equipped.duplicate()
	if _selected != "": # the card picked on this tab ("standard": the tab's standard look)
		wearing[ShopCatalog.tab_key(tab)] = "" if _selected == "standard" else _selected
	var look := ShopCatalog.look_for(wearing)
	_rig.look = look
	_ball_view.mesh = Ball.view_mesh_for(look)
	_demo.mesh = _ball_view.mesh
	_demo_trail.style = look.trail_style


func _build_ui() -> void:
	add_child(_ui)
	var f := FEEDBACK
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = f.card_panel
	box.set_corner_radius_all(8)
	box.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", box)
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 24
	panel.offset_top = 24
	panel.offset_bottom = -24
	panel.custom_minimum_size.x = 620
	_ui.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	panel.add_child(rows)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	rows.add_child(head)
	var title := Label.new()
	title.text = "Shop"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", f.card_text)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(Hud.coin_icon(22.0))
	_balance.add_theme_font_size_override("font_size", 22)
	_balance.add_theme_color_override("font_color", f.card_text)
	head.add_child(_balance)
	_status.add_theme_color_override("font_color", f.card_muted)
	rows.add_child(_status)
	for name in ShopCatalog.TAB_NAMES:
		_tabs.add_tab(name)
	_tabs.tab_changed.connect(func(i: int) -> void:
		tab = i
		_selected = ""
		_refresh())
	rows.add_child(_tabs)
	_cards.add_theme_constant_override("h_separation", 10)
	_cards.add_theme_constant_override("v_separation", 10)
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(_cards)
	var back := Button.new()
	back.text = "Back to menu"
	back.pressed.connect(func() -> void:
		if online:
			multiplayer.multiplayer_peer = null
		get_tree().change_scene_to_file("res://lobby.tscn"))
	rows.add_child(back)


func _refresh() -> void:
	_balance.text = str(balance)
	for child in _cards.get_children():
		child.queue_free()
	var key := ShopCatalog.tab_key(tab)
	var wearing := str(equipped.get(key, ""))
	_cards.add_child(_card("", "Standard", 0, true, wearing == ""))
	for it in ShopCatalog.catalog().items:
		if it.tab == tab:
			_cards.add_child(_card(it.id, it.title, it.price, it.id in owned, wearing == it.id, it.color))
	_show_look()


## One item's card: swatch, name, price, its state and the button that fits (Buy / Equip / Equipped).
func _card(item_id: String, title: String, price: int, is_owned: bool, is_worn: bool, swatch := Color.TRANSPARENT) -> Control:
	var f := FEEDBACK
	var card := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = f.card_panel.lightened(0.12 if item_id == _selected or (item_id == "" and _selected == "standard") else 0.05)
	box.border_color = f.coin_color if is_worn else f.card_line
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", box)
	card.custom_minimum_size = Vector2(180, 150)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	var chip := ColorRect.new()
	chip.color = swatch if swatch.a > 0.0 else _standard_color()
	chip.custom_minimum_size = Vector2(0, 26)
	col.add_child(chip)
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_color_override("font_color", f.card_text)
	col.add_child(name_label)
	var state := Label.new()
	state.text = "Equipped" if is_worn else ("Owned" if is_owned else "%d coins" % price)
	state.add_theme_color_override("font_color", f.coin_color if not is_owned else f.card_muted)
	col.add_child(state)
	var button := Button.new()
	button.text = "Equipped" if is_worn else ("Equip" if is_owned else "Buy")
	button.disabled = is_worn or (not is_owned and price > balance)
	button.pressed.connect(func() -> void:
		if is_owned:
			_equip(item_id)
		else:
			_buy(item_id))
	col.add_child(button)
	card.mouse_entered.connect(func() -> void: _show_preview(item_id))
	card.mouse_exited.connect(_show_look)
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_selected = item_id if item_id != "" else "standard"
			_refresh())
	return card


## Hovering: the golfer in this item (the tab's standard look for "Standard").
func _show_preview(item_id: String) -> void:
	var wearing := equipped.duplicate()
	wearing[ShopCatalog.tab_key(tab)] = item_id
	var look := ShopCatalog.look_for(wearing)
	_rig.look = look
	_ball_view.mesh = Ball.view_mesh_for(look)
	_demo.mesh = _ball_view.mesh
	_demo_trail.style = look.trail_style


## The standard look's colour for this tab (its card's swatch).
func _standard_color() -> Color:
	var look := ShopCatalog.DEFAULT_LOOK
	return [look.hat, look.shirt, look.pants, look.shoes, Ball.SHADES[1], look.club, FEEDBACK.trail_color][tab]
