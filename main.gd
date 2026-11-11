extends Control
## Battleships: Deep Strike - game flow, UI and turn logic.

const SETTINGS_PATH := "user://battleships.cfg"
const BOARD_Y := 120.0
const LEFT_X := 50.0
const RIGHT_X := 1280.0 - 50.0 - 496.0

var player := Fleet.new()
var enemy := Fleet.new()
var ai := EnemyAI.new()
var sfx: Sfx

var modern := true
var difficulty := 1
var sound_on := true

var phase := "menu"        # menu, placing, player_turn, enemy_turn, over
var busy := false
var armed := "fire"        # fire, sonar, air
var horizontal := true
var sonar_left := 2
var air_left := 1
var shots_fired := 0
var hits_landed := 0
var enemy_sunk := 0
var turn_count := 0
var msgs: Array = []
var game_id := 0

var backdrop: Backdrop
var board_p: BoardView
var board_e: BoardView
var fleet_panel: FleetPanel
var title_lbl: Label
var sub_lbl: Label
var status_lbl: Label
var hint_lbl: Label
var name_p: Label
var name_e: Label
var btn_rotate: Button
var btn_undo: Button
var btn_random: Button
var btn_start: Button
var btn_fire: Button
var btn_sonar: Button
var btn_air: Button
var btn_theme: Button
var btn_sound: Button
var btn_menu: Button
var menu_overlay: Control
var end_overlay: Control
var menu_theme_opt: OptionButton
var menu_diff_opt: OptionButton
var menu_sound_chk: CheckButton
var menu_resume: Button
var end_title: Label
var end_stats: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_settings()
	theme = _make_theme()

	sfx = Sfx.new()
	add_child(sfx)
	sfx.set_enabled(sound_on)

	backdrop = Backdrop.new()
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE

	title_lbl = _label("BATTLESHIPS", 40, Vector2(0, 0), 1280.0)
	sub_lbl = _label("D E E P   S T R I K E", 13, Vector2(0, 46), 1280.0)
	status_lbl = _label("", 21, Vector2(0, 66), 1280.0)
	name_p = _label("YOUR FLEET", 16, Vector2(LEFT_X, 94), 496.0)
	name_e = _label("ENEMY WATERS", 16, Vector2(RIGHT_X, 94), 496.0)
	hint_lbl = _label("", 14, Vector2(0, 686), 1280.0)

	board_p = BoardView.new()
	board_p.position = Vector2(LEFT_X, BOARD_Y)
	board_p.fleet = player
	board_p.show_ships = true
	add_child(board_p)
	board_p.cell_clicked.connect(_on_player_cell_clicked)
	board_p.cell_hovered.connect(_on_player_cell_hovered)

	board_e = BoardView.new()
	board_e.position = Vector2(RIGHT_X, BOARD_Y)
	board_e.fleet = enemy
	add_child(board_e)
	board_e.cell_clicked.connect(_on_enemy_cell_clicked)
	board_e.cell_hovered.connect(_on_enemy_cell_hovered)

	fleet_panel = FleetPanel.new()
	fleet_panel.position = Vector2(558, 150)
	fleet_panel.size = Vector2(164, 440)
	fleet_panel.player = player
	fleet_panel.enemy = enemy
	fleet_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fleet_panel)

	# Placement buttons (under your board)
	var by := 630.0
	btn_rotate = _button("Rotate [R]", Vector2(LEFT_X, by), Vector2(118, 44), _on_rotate)
	btn_undo = _button("Undo", Vector2(LEFT_X + 126, by), Vector2(118, 44), _on_undo)
	btn_random = _button("Random", Vector2(LEFT_X + 252, by), Vector2(118, 44), _on_random)
	btn_start = _button("START", Vector2(LEFT_X + 378, by), Vector2(118, 44), _on_start_battle)
	# Power buttons (under enemy board)
	btn_fire = _button("Fire [1]", Vector2(RIGHT_X, by), Vector2(160, 44), _on_arm.bind("fire"))
	btn_sonar = _button("Sonar [2]", Vector2(RIGHT_X + 168, by), Vector2(160, 44), _on_arm.bind("sonar"))
	btn_air = _button("Airstrike [3]", Vector2(RIGHT_X + 336, by), Vector2(160, 44), _on_arm.bind("air"))
	for b in [btn_fire, btn_sonar, btn_air]:
		b.toggle_mode = true

	# Top-right controls
	btn_theme = _button("", Vector2(1280 - 12 - 3 * 134, 12), Vector2(130, 34), _on_toggle_theme)
	btn_sound = _button("", Vector2(1280 - 12 - 2 * 134, 12), Vector2(130, 34), _on_toggle_sound)
	btn_menu = _button("Menu", Vector2(1280 - 12 - 134, 12), Vector2(130, 34), _show_menu)
	for b in [btn_theme, btn_sound, btn_menu]:
		b.add_theme_font_size_override("font_size", 15)

	_build_menu()
	_build_end_overlay()
	_apply_theme()
	_show_menu()


# --------------------------------------------------------------- UI helpers

func _label(text: String, font_size: int, pos: Vector2, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(width, font_size * 1.6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _button(text: String, pos: Vector2, sz: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	add_child(b)
	return b


func _sb(bg: Color, border: Color, radius: int, bw: int, mh: float, mv: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = mh
	s.content_margin_right = mh
	s.content_margin_top = mv
	s.content_margin_bottom = mv
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	var panel_bg: Color
	var border: Color
	var btn: Color
	var btn_h: Color
	var btn_p: Color
	var fcol: Color
	if modern:
		panel_bg = Color(0.04, 0.09, 0.14, 0.95)
		border = Color(0.25, 0.85, 1.0)
		btn = Color(0.07, 0.16, 0.24)
		btn_h = Color(0.10, 0.28, 0.40)
		btn_p = Color(0.14, 0.40, 0.55)
		fcol = Color(0.86, 0.97, 1.0)
	else:
		panel_bg = Color(0.27, 0.16, 0.08, 0.96)
		border = Color(0.86, 0.70, 0.40)
		btn = Color(0.46, 0.29, 0.14)
		btn_h = Color(0.60, 0.38, 0.19)
		btn_p = Color(0.34, 0.20, 0.10)
		fcol = Color(1.0, 0.95, 0.80)
	t.default_font_size = 18
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, _sb(btn, border, 8, 2, 12, 6))
		t.set_stylebox("hover", cls, _sb(btn_h, border, 8, 2, 12, 6))
		t.set_stylebox("pressed", cls, _sb(btn_p, border.lightened(0.2), 8, 3, 12, 6))
		t.set_stylebox("hover_pressed", cls, _sb(btn_p.lightened(0.1), border.lightened(0.2), 8, 3, 12, 6))
		t.set_stylebox("disabled", cls, _sb(btn.darkened(0.45), border.darkened(0.6), 8, 2, 12, 6))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, fcol)
		t.set_color("font_hover_color", cls, fcol.lightened(0.2))
		t.set_color("font_pressed_color", cls, fcol.lightened(0.3))
		t.set_color("font_hover_pressed_color", cls, fcol.lightened(0.3))
		t.set_color("font_focus_color", cls, fcol)
		t.set_color("font_disabled_color", cls, fcol.darkened(0.5))
	t.set_stylebox("panel", "PanelContainer", _sb(panel_bg, border, 14, 3, 28, 24))
	t.set_color("font_color", "Label", fcol)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("outline_size", "Label", 4)
	return t


func _text_color() -> Color:
	return Color(0.86, 0.97, 1.0) if modern else Color(1.0, 0.95, 0.80)


func _apply_theme() -> void:
	theme = _make_theme()
	backdrop.modern = modern
	board_p.modern = modern
	board_e.modern = modern
	fleet_panel.modern = modern
	var tc := _text_color()
	title_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0) if modern else Color(1.0, 0.92, 0.70))
	sub_lbl.add_theme_color_override("font_color", tc.darkened(0.25))
	status_lbl.add_theme_color_override("font_color", tc)
	hint_lbl.add_theme_color_override("font_color", tc.darkened(0.2))
	name_p.add_theme_color_override("font_color", tc)
	name_e.add_theme_color_override("font_color", tc)
	btn_theme.text = "Style: " + ("Modern" if modern else "Classic")
	btn_sound.text = "Sound: " + ("On" if sound_on else "Off")
	if menu_theme_opt != null:
		menu_theme_opt.select(1 if modern else 0)
		menu_diff_opt.select(difficulty)
		menu_sound_chk.set_pressed_no_signal(sound_on)


func _set_status(text: String) -> void:
	status_lbl.text = text


func _coord(c: int) -> String:
	return char(65 + Fleet.cx(c)) + str(Fleet.cy(c) + 1)


# ---------------------------------------------------------------- overlays

func _fullrect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_menu() -> void:
	menu_overlay = Control.new()
	add_child(menu_overlay)
	_fullrect(menu_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.68)
	menu_overlay.add_child(dim)
	_fullrect(dim)
	var center := CenterContainer.new()
	menu_overlay.add_child(center)
	_fullrect(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(540, 0)
	panel.add_child(box)

	var t := Label.new()
	t.text = "BATTLESHIPS"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 44)
	box.add_child(t)
	var s := Label.new()
	s.text = "D E E P   S T R I K E"
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_theme_font_size_override("font_size", 16)
	box.add_child(s)
	box.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	var l1 := Label.new()
	l1.text = "Graphics"
	l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(l1)
	menu_theme_opt = OptionButton.new()
	menu_theme_opt.add_item("Classic tabletop", 0)
	menu_theme_opt.add_item("Modern radar", 1)
	menu_theme_opt.custom_minimum_size = Vector2(250, 0)
	menu_theme_opt.item_selected.connect(_on_menu_theme)
	grid.add_child(menu_theme_opt)
	var l2 := Label.new()
	l2.text = "Enemy admiral"
	grid.add_child(l2)
	menu_diff_opt = OptionButton.new()
	menu_diff_opt.add_item("Rookie (easy)", 0)
	menu_diff_opt.add_item("Officer (normal)", 1)
	menu_diff_opt.add_item("Admiral (hard)", 2)
	menu_diff_opt.item_selected.connect(_on_menu_diff)
	grid.add_child(menu_diff_opt)
	var l3 := Label.new()
	l3.text = "Sound"
	grid.add_child(l3)
	menu_sound_chk = CheckButton.new()
	menu_sound_chk.text = "Effects & ambience"
	menu_sound_chk.toggled.connect(_on_menu_sound)
	grid.add_child(menu_sound_chk)

	var rules := Label.new()
	rules.text = "Place your fleet, then trade shots with the enemy admiral. Neither side can see the other's ships.\n\n" \
		+ "MODERN TWIST - every captain carries special gear (using it costs your turn):\n" \
		+ "  SONAR x2: ping a 3x3 zone and learn how many hidden ship tiles lurk inside.\n" \
		+ "  AIRSTRIKE x1: bomb a plus-shaped area of 5 tiles at once.\n" \
		+ "The enemy has the same gear - watch for its sonar pings on your board."
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.custom_minimum_size = Vector2(540, 0)
	rules.add_theme_font_size_override("font_size", 15)
	box.add_child(rules)

	var start := Button.new()
	start.text = "NEW GAME"
	start.focus_mode = Control.FOCUS_NONE
	start.custom_minimum_size = Vector2(0, 46)
	start.pressed.connect(_on_menu_start)
	box.add_child(start)
	menu_resume = Button.new()
	menu_resume.text = "Resume game"
	menu_resume.focus_mode = Control.FOCUS_NONE
	menu_resume.pressed.connect(_hide_menu)
	box.add_child(menu_resume)


func _build_end_overlay() -> void:
	end_overlay = Control.new()
	add_child(end_overlay)
	_fullrect(end_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	end_overlay.add_child(dim)
	_fullrect(dim)
	var center := CenterContainer.new()
	end_overlay.add_child(center)
	_fullrect(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(420, 0)
	panel.add_child(box)
	end_title = Label.new()
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_title.add_theme_font_size_override("font_size", 40)
	box.add_child(end_title)
	end_stats = Label.new()
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(end_stats)
	var again := Button.new()
	again.text = "Play again"
	again.focus_mode = Control.FOCUS_NONE
	again.custom_minimum_size = Vector2(0, 44)
	again.pressed.connect(_on_menu_start)
	box.add_child(again)
	var back := Button.new()
	back.text = "Menu"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_show_menu)
	box.add_child(back)
	end_overlay.hide()


func _show_menu() -> void:
	menu_resume.visible = phase != "menu" and phase != "over"
	end_overlay.hide()
	menu_overlay.show()
	menu_overlay.move_to_front()
	sfx.play("click")


func _hide_menu() -> void:
	menu_overlay.hide()
	sfx.play("click")


func _on_menu_theme(i: int) -> void:
	modern = (i == 1)
	_apply_theme()
	_save_settings()
	sfx.play("click")


func _on_menu_diff(i: int) -> void:
	difficulty = i
	_save_settings()
	sfx.play("click")


func _on_menu_sound(on: bool) -> void:
	sound_on = on
	sfx.set_enabled(on)
	_apply_theme()
	_save_settings()
	sfx.play("click")


func _on_menu_start() -> void:
	menu_overlay.hide()
	end_overlay.hide()
	_new_game()


func _on_toggle_theme() -> void:
	modern = not modern
	_apply_theme()
	_save_settings()
	sfx.play("click")


func _on_toggle_sound() -> void:
	sound_on = not sound_on
	sfx.set_enabled(sound_on)
	_apply_theme()
	_save_settings()
	sfx.play("click")


# ---------------------------------------------------------------- settings

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		modern = cf.get_value("game", "modern", true)
		difficulty = cf.get_value("game", "difficulty", 1)
		sound_on = cf.get_value("game", "sound", true)


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "modern", modern)
	cf.set_value("game", "difficulty", difficulty)
	cf.set_value("game", "sound", sound_on)
	cf.save(SETTINGS_PATH)


# --------------------------------------------------------------- game flow

func _new_game() -> void:
	game_id += 1
	player.reset()
	enemy.reset()
	enemy.random_place()          # fresh random enemy layout every game
	ai.reset(difficulty)
	sonar_left = 2
	air_left = 1
	shots_fired = 0
	hits_landed = 0
	enemy_sunk = 0
	turn_count = 0
	armed = "fire"
	horizontal = true
	busy = false
	msgs.clear()
	for b in [board_p, board_e]:
		b.fx.clear()
		b.ghost = {}
		b.preview = []
		b.hover = -1
		b.reveal_all = false
		b.shake = 0.0
	board_p.interactive = true
	board_e.interactive = false
	phase = "placing"
	_update_ghost()
	_set_status(_placing_status())
	_refresh_ui()
	sfx.play("ready")


func _placing_status() -> String:
	if player.ships.size() >= Fleet.SHIP_DEFS.size():
		return "Fleet deployed! Press START or tweak your layout."
	var def: Dictionary = Fleet.SHIP_DEFS[player.ships.size()]
	return "Deploy your fleet: place the %s (%d tiles)." % [def["name"], def["length"]]


func _refresh_ui() -> void:
	var placing := phase == "placing"
	var battle := phase == "player_turn" or phase == "enemy_turn" or phase == "over"
	btn_rotate.visible = placing
	btn_undo.visible = placing
	btn_random.visible = placing
	btn_start.visible = placing
	btn_undo.disabled = player.ships.is_empty()
	btn_start.disabled = player.ships.size() < Fleet.SHIP_DEFS.size()
	btn_fire.visible = battle
	btn_sonar.visible = battle
	btn_air.visible = battle
	var can := phase == "player_turn" and not busy
	btn_fire.disabled = not can
	btn_sonar.text = "Sonar [2]  x%d" % sonar_left
	btn_sonar.disabled = (not can) or sonar_left <= 0
	btn_air.text = "Airstrike [3]  x%d" % air_left
	btn_air.disabled = (not can) or air_left <= 0
	btn_fire.set_pressed_no_signal(armed == "fire")
	btn_sonar.set_pressed_no_signal(armed == "sonar")
	btn_air.set_pressed_no_signal(armed == "air")
	match phase:
		"placing":
			hint_lbl.text = "Left-click to place  |  Right-click or R to rotate  |  or use Random"
		"player_turn", "enemy_turn":
			hint_lbl.text = "Click a tile on Enemy Waters  |  1 Fire   2 Sonar   3 Airstrike  |  Esc: menu"
		_:
			hint_lbl.text = ""
	name_e.text = "ENEMY WATERS"
	name_p.text = "YOUR FLEET"
	if phase == "player_turn" and not busy:
		name_e.text = "ENEMY WATERS  -  YOUR TURN"
	elif phase == "enemy_turn":
		name_p.text = "YOUR FLEET  -  UNDER FIRE"


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if menu_overlay.visible or end_overlay.visible:
		if event.keycode == KEY_ESCAPE and phase != "menu" and phase != "over" and menu_overlay.visible:
			_hide_menu()
		return
	match event.keycode:
		KEY_R:
			if phase == "placing":
				_on_rotate()
		KEY_1:
			_on_arm("fire")
		KEY_2:
			_on_arm("sonar")
		KEY_3:
			_on_arm("air")
		KEY_ESCAPE:
			if armed != "fire":
				_on_arm("fire")
			elif phase != "menu":
				_show_menu()


# --------------------------------------------------------------- placement

func _on_rotate() -> void:
	if phase != "placing":
		return
	horizontal = not horizontal
	sfx.play("click")
	_update_ghost()


func _on_undo() -> void:
	if phase != "placing" or player.ships.is_empty():
		return
	player.remove_last()
	sfx.play("click")
	_update_ghost()
	_set_status(_placing_status())
	_refresh_ui()


func _on_random() -> void:
	if phase != "placing":
		return
	player.random_place()
	sfx.play("place")
	_update_ghost()
	_set_status(_placing_status())
	_refresh_ui()


func _update_ghost() -> void:
	board_p.ghost = {}
	if phase != "placing" or player.ships.size() >= Fleet.SHIP_DEFS.size():
		return
	var h := board_p.hover
	if h < 0:
		return
	var def: Dictionary = Fleet.SHIP_DEFS[player.ships.size()]
	var length: int = def["length"]
	var x := mini(Fleet.cx(h), Fleet.N - (length if horizontal else 1))
	var y := mini(Fleet.cy(h), Fleet.N - (1 if horizontal else length))
	board_p.ghost = {
		"cells": player.cells_for(x, y, length, horizontal), "length": length,
		"horizontal": horizontal, "name": def["name"],
		"ok": player.fits(x, y, length, horizontal), "x": x, "y": y,
	}


func _on_player_cell_hovered(_i: int) -> void:
	_update_ghost()


func _on_player_cell_clicked(_i: int, button: int) -> void:
	if phase != "placing":
		return
	if button == MOUSE_BUTTON_RIGHT:
		_on_rotate()
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	_update_ghost()
	var g := board_p.ghost
	if g.is_empty() or not g["ok"]:
		sfx.play("error")
		return
	player.place(g["x"], g["y"], g["length"], g["horizontal"], g["name"])
	sfx.play("place")
	_update_ghost()
	_set_status(_placing_status())
	_refresh_ui()


func _on_start_battle() -> void:
	if phase != "placing" or player.ships.size() < Fleet.SHIP_DEFS.size():
		return
	board_p.ghost = {}
	board_p.interactive = false
	board_p.hover = -1
	board_e.interactive = true
	sfx.play("sonar", 1.0, -6.0)
	_player_turn()


# ------------------------------------------------------------------ battle

func _player_turn() -> void:
	phase = "player_turn"
	busy = false
	armed = "fire"
	turn_count += 1
	_set_status("Your turn, Admiral. Choose a target on Enemy Waters.")
	_refresh_ui()
	_update_preview()


func _area3(c: int) -> Array:
	var out: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := Fleet.cx(c) + dx
			var y := Fleet.cy(c) + dy
			if Fleet.inb(x, y):
				out.append(Fleet.idx(x, y))
	return out


func _plus(c: int) -> Array:
	var out: Array = []
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var x: int = Fleet.cx(c) + d.x
		var y: int = Fleet.cy(c) + d.y
		if Fleet.inb(x, y):
			out.append(Fleet.idx(x, y))
	return out


func _unshot(f: Fleet, cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		if f.shots[c] == 0:
			out.append(c)
	return out


func _on_arm(mode: String) -> void:
	if phase != "player_turn" or busy:
		return
	if mode == "sonar" and sonar_left <= 0:
		sfx.play("error")
		return
	if mode == "air" and air_left <= 0:
		sfx.play("error")
		return
	armed = mode
	sfx.play("click")
	match mode:
		"fire":
			_set_status("Your turn, Admiral. Choose a target on Enemy Waters.")
		"sonar":
			_set_status("SONAR armed - pick the centre of a 3x3 zone to scan.")
		"air":
			_set_status("AIRSTRIKE armed - pick the centre of a plus-shaped strike.")
	_refresh_ui()
	_update_preview()


func _update_preview() -> void:
	board_e.preview = []
	if phase != "player_turn" or busy:
		return
	var h := board_e.hover
	if h < 0:
		return
	board_e.preview_kind = armed
	match armed:
		"fire":
			board_e.preview = [h]
			board_e.preview_ok = enemy.shots[h] == 0
		"sonar":
			board_e.preview = _area3(h)
			board_e.preview_ok = true
		"air":
			board_e.preview = _plus(h)
			board_e.preview_ok = not _unshot(enemy, board_e.preview).is_empty()


func _on_enemy_cell_hovered(_i: int) -> void:
	_update_preview()


func _on_enemy_cell_clicked(i: int, button: int) -> void:
	if phase != "player_turn" or busy:
		return
	if button == MOUSE_BUTTON_RIGHT:
		_on_arm("fire")
		return
	if button != MOUSE_BUTTON_LEFT or i < 0:
		return
	match armed:
		"fire":
			if enemy.shots[i] != 0:
				sfx.play("error")
				return
			_player_fire([i], false)
		"sonar":
			_player_sonar(i)
		"air":
			var cells := _unshot(enemy, _plus(i))
			if cells.is_empty():
				sfx.play("error")
				return
			air_left -= 1
			sfx.play("alert")
			_player_fire(cells, true)


func _player_fire(cells: Array, is_air: bool) -> void:
	busy = true
	armed = "fire"
	board_e.preview = []
	shots_fired += cells.size()
	msgs.clear()
	_set_status("AIRSTRIKE inbound!" if is_air else "Missile away...")
	_refresh_ui()
	_volley(enemy, board_e, cells, true)


func _player_sonar(c: int) -> void:
	if sonar_left <= 0:
		sfx.play("error")
		return
	busy = true
	sonar_left -= 1
	armed = "fire"
	board_e.preview = []
	board_e.add_sonar(c)
	sfx.play("sonar")
	_set_status("Sonar pinging around %s..." % _coord(c))
	_refresh_ui()
	var gid := game_id
	await get_tree().create_timer(1.3).timeout
	if gid != game_id:
		return
	var count := enemy.sonar_count(c)
	enemy.sonar[c] = count
	var word := "contact" if count == 1 else "contacts"
	board_e.add_text(c, "%d %s" % [count, word], Color(0.5, 1.0, 0.9))
	sfx.play("contact" if count > 0 else "clear")
	_set_status("Sonar: %d hidden ship tile%s near %s." % [count, "" if count == 1 else "s", _coord(c)])
	await get_tree().create_timer(1.2).timeout
	if gid != game_id:
		return
	_enemy_turn()


func _play_sfx(sound: String) -> void:
	sfx.play(sound)


## Fire one or more missiles at `defender`'s board. Calls back when all have landed.
func _volley(defender: Fleet, board: BoardView, cells: Array, by_player: bool) -> void:
	var state := {"pending": cells.size(), "gid": game_id}
	for k in cells.size():
		var c: int = cells[k]
		var delay := k * 0.2
		get_tree().create_timer(delay).timeout.connect(_play_sfx.bind("missile"))
		board.launch_missile(c, delay, _on_missile_land.bind(defender, board, c, by_player, state))


func _on_missile_land(defender: Fleet, board: BoardView, c: int, by_player: bool, state: Dictionary) -> void:
	if state["gid"] != game_id:
		return
	_impact(defender, board, c, by_player)
	state["pending"] -= 1
	if state["pending"] == 0:
		_after_volley(defender, by_player)


func _impact(defender: Fleet, board: BoardView, c: int, by_player: bool) -> void:
	var r := defender.receive_shot(c)
	var where := _coord(c)
	match r["result"]:
		"miss":
			board.add_splash(c)
			sfx.play("splash", randf_range(0.92, 1.08))
			board.add_text(c, "MISS", Color(0.85, 0.93, 1.0))
			msgs.append("%s: miss" % where)
		"hit":
			board.add_explosion(c, false)
			sfx.play("explosion", randf_range(0.9, 1.1))
			board.add_text(c, "HIT!", Color(1.0, 0.62, 0.2))
			if by_player:
				hits_landed += 1
			msgs.append("%s: HIT!" % where)
		"sunk":
			board.add_explosion(c, true)
			sfx.play("sunk")
			var sname: String = r["ship"]["name"]
			board.add_text(c, "SUNK!", Color(1.0, 0.25, 0.2))
			if by_player:
				hits_landed += 1
				enemy_sunk += 1
				msgs.append("%s: you sank the enemy %s!" % [where, sname])
			else:
				msgs.append("%s: your %s was sunk!" % [where, sname])


func _after_volley(defender: Fleet, by_player: bool) -> void:
	var gid := game_id
	_set_status(("You: " if by_player else "Enemy: ") + "  |  ".join(msgs))
	await get_tree().create_timer(1.0).timeout
	if gid != game_id:
		return
	if defender.all_sunk():
		_game_over(by_player)
	elif by_player:
		_enemy_turn()
	else:
		_player_turn()


func _enemy_turn() -> void:
	phase = "enemy_turn"
	busy = true
	board_e.preview = []
	msgs.clear()
	_set_status("The enemy admiral is plotting...")
	_refresh_ui()
	var gid := game_id
	await get_tree().create_timer(0.9).timeout
	if gid != game_id:
		return
	var act := ai.decide_power(player)
	match act["type"]:
		"sonar":
			ai.sonar_left -= 1
			var c: int = act["cell"]
			board_p.add_sonar(c)
			sfx.play("sonar")
			_set_status("Enemy sonar pinging near %s!" % _coord(c))
			await get_tree().create_timer(1.4).timeout
			if gid != game_id:
				return
			var count := player.sonar_count(c)
			player.sonar[c] = count
			ai.record_sonar(c, count, player)
			board_p.add_text(c, "SCANNED", Color(1.0, 0.5, 0.4))
			await get_tree().create_timer(1.0).timeout
			if gid != game_id:
				return
			_player_turn()
		"air":
			ai.air_left -= 1
			var cells := ai.plus_cells(player, act["cell"])
			sfx.play("alert")
			_set_status("ENEMY AIRSTRIKE inbound at %s!" % _coord(act["cell"]))
			_volley(player, board_p, cells, false)
		_:
			var c: int = ai.choose_shot(player)
			_set_status("Enemy fires at %s..." % _coord(c))
			_volley(player, board_p, [c], false)


func _game_over(player_won: bool) -> void:
	phase = "over"
	busy = true
	board_e.reveal_all = true
	board_e.interactive = false
	board_e.preview = []
	var gid := game_id
	sfx.play("win" if player_won else "lose")
	_set_status("VICTORY! The enemy fleet is destroyed!" if player_won else "DEFEAT. Your fleet lies on the seabed.")
	_refresh_ui()
	var target := board_e if player_won else board_p
	for k in 14:
		get_tree().create_timer(k * 0.14).timeout.connect(_celebrate.bind(target, gid))
	await get_tree().create_timer(2.4).timeout
	if gid != game_id:
		return
	var acc := 0
	if shots_fired > 0:
		acc = int(round(100.0 * hits_landed / shots_fired))
	end_title.text = "VICTORY!" if player_won else "DEFEAT"
	end_stats.text = "Turns: %d\nShots fired: %d   Hits: %d   Accuracy: %d%%\nEnemy ships sunk: %d / %d\nYour ships afloat: %d / %d" % [
		turn_count, shots_fired, hits_landed, acc, enemy_sunk, Fleet.SHIP_DEFS.size(),
		player.remaining_lengths().size(), Fleet.SHIP_DEFS.size()]
	end_overlay.show()


func _celebrate(board: BoardView, gid: int) -> void:
	if gid != game_id:
		return
	board.add_explosion(randi() % (BoardView.N * BoardView.N), randf() < 0.3)
	sfx.play("explosion", randf_range(1.0, 1.4), -8.0)


# --------------------------------------------------------- inner view classes

## Animated background: wooden table (classic) or drifting radar grid (modern).
class Backdrop extends Control:
	var modern := true
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if modern:
			for i in 36:
				var f := float(i) / 35.0
				draw_rect(Rect2(0, h * i / 36.0, w, h / 36.0 + 1.0),
					Color(0.02 + 0.03 * f, 0.05 + 0.07 * f, 0.10 + 0.10 * f))
			var off := fmod(t * 14.0, 56.0)
			for gx in range(-1, int(w / 56.0) + 2):
				draw_line(Vector2(gx * 56.0 + off, 0), Vector2(gx * 56.0 + off, h), Color(0.3, 0.9, 1.0, 0.035), 1.0)
			for gy in range(-1, int(h / 56.0) + 2):
				draw_line(Vector2(0, gy * 56.0 + off), Vector2(w, gy * 56.0 + off), Color(0.3, 0.9, 1.0, 0.035), 1.0)
			var c := Vector2(w * 0.5, h * 0.5)
			for r in [180.0, 360.0, 540.0]:
				draw_arc(c, r + sin(t * 0.5) * 8.0, 0.0, TAU, 96, Color(0.3, 0.9, 1.0, 0.05), 2.0)
			for i in 46:
				var x := fmod(i * 173.3 + t * (6.0 + i % 7), w)
				var y := fmod(i * 97.1 + sin(t * 0.3 + i) * 30.0 + t * 3.0, h)
				draw_circle(Vector2(x, y), 1.5 + i % 3, Color(0.5, 0.95, 1.0, 0.12))
		else:
			draw_rect(Rect2(0, 0, w, h), Color(0.30, 0.18, 0.09))
			for i in 9:
				var x := i * 160.0
				var shade := 0.03 * sin(i * 3.1)
				draw_rect(Rect2(x, 0, 160.0, h), Color(0.30 + shade, 0.18 + shade, 0.09 + shade * 0.5))
				draw_line(Vector2(x, 0), Vector2(x, h), Color(0, 0, 0, 0.35), 3.0)
				for j in 7:
					var gy := fmod(j * 113.0 + i * 41.0, h)
					draw_line(Vector2(x + 20, gy), Vector2(x + 140, gy + 6 * sin(i + j)), Color(0, 0, 0, 0.07), 2.0)
			for k in 22:
				draw_rect(Rect2(k, k, w - 2.0 * k, h - 2.0 * k), Color(0, 0, 0, 0.012 * (22 - k)), false, 2.0)


## Centre column: fleet status lists for both sides.
class FleetPanel extends Control:
	var player: Fleet
	var enemy: Fleet
	var modern := true
	var font: Font

	func _ready() -> void:
		font = ThemeDB.fallback_font

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		_section("ENEMY FLEET", enemy, 0.0)
		_section("YOUR FLEET", player, 222.0)

	func _section(title: String, f: Fleet, y0: float) -> void:
		var tc := Color(0.7, 0.95, 1.0) if modern else Color(1.0, 0.92, 0.7)
		draw_string(font, Vector2(0, y0 + 16), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, tc)
		draw_line(Vector2(10, y0 + 24), Vector2(size.x - 10, y0 + 24), Color(tc.r, tc.g, tc.b, 0.5), 1.5)
		for k in Fleet.SHIP_DEFS.size():
			var def: Dictionary = Fleet.SHIP_DEFS[k]
			var row := y0 + 36.0 + k * 36.0
			var ship = null
			for s in f.ships:
				if s["name"] == def["name"]:
					ship = s
			var sunk: bool = ship != null and ship["sunk"]
			var name_col := tc
			if sunk:
				name_col = Color(1.0, 0.4, 0.35)
			draw_string(font, Vector2(8, row + 12), def["name"], HORIZONTAL_ALIGNMENT_LEFT, size.x, 14, name_col)
			var length: int = def["length"]
			for p in length:
				var r := Rect2(10 + p * 21, row + 18, 18, 9)
				var col := Color(0.35, 0.4, 0.45, 0.5)
				if ship != null:
					col = Color(0.55, 0.65, 0.72) if modern else Color(0.62, 0.66, 0.72)
					if p < ship["hits"]:
						col = Color(0.95, 0.25, 0.15)
				draw_rect(r, col)
				draw_rect(r, Color(0, 0, 0, 0.5), false, 1.0)
			if sunk:
				draw_line(Vector2(6, row + 7), Vector2(size.x - 10, row + 7), Color(1.0, 0.3, 0.25, 0.8), 2.0)
