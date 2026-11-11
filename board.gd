class_name BoardView
extends Control
## Draws one 10x10 ocean grid (classic tabletop or modern radar style), the
## ships, shot markers and every animation effect. All art is drawn in code.

signal cell_clicked(idx: int, button: int)
signal cell_hovered(idx: int)

const N := 10
const CELL := 46.0
const MARGIN := 30.0
const BOARD_PX := 460.0
const SIZE_PX := 496.0

var fleet: Fleet
var show_ships := false        # draw this fleet's ships (your own board)
var reveal_all := false        # game over: reveal the enemy's remaining ships
var modern := true
var interactive := false
var accent := Color(0.30, 0.90, 1.00)

var hover := -1
var preview: Array = []
var preview_ok := true
var preview_kind := "fire"
var ghost: Dictionary = {}     # placement preview ship

var time := 0.0
var shake := 0.0
var fx: Array = []
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(SIZE_PX, SIZE_PX)
	size = custom_minimum_size
	mouse_exited.connect(_on_mouse_exited)


# ------------------------------------------------------------------ geometry

func cell_rect(i: int) -> Rect2:
	return Rect2(MARGIN + (i % N) * CELL, MARGIN + (i / N) * CELL, CELL, CELL)


func cell_center(i: int) -> Vector2:
	return cell_rect(i).get_center()


func pos_to_cell(p: Vector2) -> int:
	if p.x < MARGIN or p.y < MARGIN:
		return -1
	var x := int(floor((p.x - MARGIN) / CELL))
	var y := int(floor((p.y - MARGIN) / CELL))
	if x < 0 or y < 0 or x >= N or y >= N:
		return -1
	return y * N + x


# --------------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseMotion:
		var c := pos_to_cell(event.position)
		if c != hover:
			hover = c
			cell_hovered.emit(c)
	elif event is InputEventMouseButton and event.pressed:
		cell_clicked.emit(pos_to_cell(event.position), event.button_index)


func _on_mouse_exited() -> void:
	if hover != -1:
		hover = -1
		cell_hovered.emit(-1)


# ------------------------------------------------------------- effect spawns

func launch_missile(cell: int, delay: float, cb: Callable) -> void:
	var target := cell_center(cell)
	var start := Vector2(target.x + randf_range(-140.0, 140.0), -100.0)
	fx.append({"type": "missile", "age": -delay, "dur": 0.65, "start": start, "end": target, "cb": cb})


func add_splash(cell: int) -> void:
	var drops: Array = []
	for i in 12:
		drops.append({"a": randf() * TAU, "s": randf_range(40.0, 120.0)})
	fx.append({"type": "splash", "age": 0.0, "dur": 1.0, "pos": cell_center(cell), "drops": drops})


func add_explosion(cell: int, big: bool) -> void:
	var parts: Array = []
	var n := 30 if big else 16
	for i in n:
		parts.append({"a": randf() * TAU, "s": randf_range(50.0, 200.0 if big else 130.0),
			"c": randi() % 3, "r": randf_range(2.0, 5.5)})
	fx.append({"type": "boom", "age": 0.0, "dur": 1.3 if big else 0.9, "pos": cell_center(cell),
		"parts": parts, "big": big})
	shake = maxf(shake, 1.0 if big else 0.55)


func add_sonar(cell: int) -> void:
	fx.append({"type": "sonar", "age": 0.0, "dur": 1.4, "pos": cell_center(cell)})


func add_text(cell: int, text: String, color: Color) -> void:
	fx.append({"type": "text", "age": 0.0, "dur": 1.5, "pos": cell_center(cell), "text": text, "color": color})


# ------------------------------------------------------------------- update

func _process(delta: float) -> void:
	time += delta
	shake = maxf(0.0, shake - delta * 2.5)
	for e in fx.duplicate():
		e["age"] += delta
		if e["age"] >= e["dur"]:
			e["done"] = true
			var cb = e.get("cb")
			if cb is Callable and cb.is_valid():
				cb.call()
	fx = fx.filter(func(e): return not e.get("done", false))
	queue_redraw()


# --------------------------------------------------------------------- draw

func _draw() -> void:
	var off := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * 5.0
	draw_set_transform(off, 0.0, Vector2.ONE)
	_draw_base()
	if fleet != null:
		_draw_ships()
		_draw_shots()
		_draw_sonar_marks()
	_draw_preview()
	_draw_fx()


func _draw_base() -> void:
	var full := Rect2(0, 0, SIZE_PX, SIZE_PX)
	var water := Rect2(MARGIN, MARGIN, BOARD_PX, BOARD_PX)
	var label_col: Color
	if modern:
		label_col = accent
		draw_rect(full, Color(0.02, 0.05, 0.09, 0.93))
		draw_rect(full, accent.darkened(0.35), false, 2.0)
		draw_rect(water, Color(0.02, 0.10, 0.15))
		var sc := Color(accent.r, accent.g, accent.b, 0.035)
		for i in range(0, int(BOARD_PX), 4):
			draw_line(Vector2(MARGIN, MARGIN + i), Vector2(MARGIN + BOARD_PX, MARGIN + i), sc, 1.0)
		var c := water.get_center()
		var sweep := time * 0.9
		for k in 18:
			var a := sweep - k * 0.035
			draw_line(c, c + Vector2(cos(a), sin(a)) * 228.0,
				Color(accent.r, accent.g, accent.b, 0.20 * (1.0 - k / 18.0)), 3.0)
		for r in [76.0, 152.0, 228.0]:
			draw_arc(c, r, 0.0, TAU, 64, Color(accent.r, accent.g, accent.b, 0.10), 1.0)
		for i in N + 1:
			var p := MARGIN + i * CELL
			var a := 0.34 if (i > 0 and i < N) else 0.9
			var col := Color(accent.r, accent.g, accent.b, a)
			draw_line(Vector2(p, MARGIN), Vector2(p, MARGIN + BOARD_PX), col, 1.0 if a < 0.5 else 2.0)
			draw_line(Vector2(MARGIN, p), Vector2(MARGIN + BOARD_PX, p), col, 1.0 if a < 0.5 else 2.0)
	else:
		label_col = Color(0.97, 0.90, 0.72)
		draw_rect(full, Color(0.43, 0.27, 0.13))
		for i in 14:
			draw_line(Vector2(0, 6 + i * 36.0), Vector2(SIZE_PX, 10 + i * 36.0), Color(0, 0, 0, 0.07), 2.0)
		draw_rect(full, Color(0.25, 0.14, 0.06), false, 4.0)
		draw_rect(Rect2(MARGIN - 6, MARGIN - 6, BOARD_PX + 12, BOARD_PX + 12), Color(0.14, 0.07, 0.03))
		draw_rect(water, Color(0.16, 0.42, 0.70))
		for j in 16:
			var pts := PackedVector2Array()
			var y0 := MARGIN + 14.0 + j * 28.0
			for xi in range(0, 47):
				var x := MARGIN + xi * 10.0
				pts.append(Vector2(x, y0 + sin(x * 0.05 + time * 1.4 + j) * 3.0))
			draw_polyline(pts, Color(1, 1, 1, 0.08), 2.0)
		for i in N + 1:
			var p := MARGIN + i * CELL
			draw_line(Vector2(p, MARGIN), Vector2(p, MARGIN + BOARD_PX), Color(1, 1, 1, 0.55), 1.5)
			draw_line(Vector2(MARGIN, p), Vector2(MARGIN + BOARD_PX, p), Color(1, 1, 1, 0.55), 1.5)
		for i in N * N:
			draw_circle(cell_center(i), 2.2, Color(0, 0.05, 0.15, 0.28))
	for i in N:
		draw_string(font, Vector2(MARGIN + i * CELL, MARGIN - 9.0), char(65 + i),
			HORIZONTAL_ALIGNMENT_CENTER, CELL, 16, label_col)
		draw_string(font, Vector2(0.0, MARGIN + i * CELL + CELL * 0.5 + 6.0), str(i + 1),
			HORIZONTAL_ALIGNMENT_CENTER, MARGIN - 4.0, 16, label_col)


func _pt(p0: Vector2, ax: Vector2, pp: Vector2, u: float, v: float) -> Vector2:
	return p0 + ax * u + pp * v


func _draw_ships() -> void:
	for ship in fleet.ships:
		if show_ships:
			_draw_ship(ship, 1.0, Color(0, 0, 0, 0))
		elif ship["sunk"]:
			_draw_ship(ship, 1.0, Color(0, 0, 0, 0))
		elif reveal_all:
			_draw_ship(ship, 0.55, Color(0, 0, 0, 0))
	if not ghost.is_empty():
		var tint := Color(0.2, 1.0, 0.4, 1.0) if ghost["ok"] else Color(1.0, 0.2, 0.2, 1.0)
		_draw_ship(ghost, 0.7, tint)


func _draw_ship(ship: Dictionary, alpha: float, tint: Color) -> void:
	var cells: Array = ship["cells"]
	var length: int = ship["length"]
	var horiz: bool = ship["horizontal"]
	var a := cell_rect(cells[0])
	var L := length * CELL
	var W := CELL * 0.78
	var p0: Vector2
	var ax: Vector2
	var pp: Vector2
	if horiz:
		p0 = Vector2(a.position.x, a.position.y + CELL * 0.5)
		ax = Vector2.RIGHT
		pp = Vector2.DOWN
	else:
		p0 = Vector2(a.position.x + CELL * 0.5, a.position.y)
		ax = Vector2.DOWN
		pp = Vector2.LEFT
	var sunk: bool = ship.get("sunk", false)

	var cols: Array
	if modern:
		cols = [Color(0.10, 0.20, 0.30), Color(0.16, 0.34, 0.46), accent, Color(0.70, 0.95, 1.0)]
	else:
		cols = [Color(0.50, 0.54, 0.60), Color(0.68, 0.72, 0.77), Color(0.20, 0.22, 0.26), Color(0.38, 0.41, 0.46)]
	for k in cols.size():
		var c: Color = cols[k]
		if sunk:
			c = c.lerp(Color(0.14, 0.02, 0.02), 0.62)
		if tint.a > 0.0:
			c = c.lerp(Color(tint.r, tint.g, tint.b), 0.55)
		c.a = alpha
		cols[k] = c
	var hull_c: Color = cols[0]
	var deck_c: Color = cols[1]
	var edge_c: Color = cols[2]
	var detail_c: Color = cols[3]

	var hull := PackedVector2Array([
		_pt(p0, ax, pp, 4.0, -W * 0.34), _pt(p0, ax, pp, L * 0.2, -W * 0.5),
		_pt(p0, ax, pp, L - W * 0.95, -W * 0.5), _pt(p0, ax, pp, L - 4.0, 0.0),
		_pt(p0, ax, pp, L - W * 0.95, W * 0.5), _pt(p0, ax, pp, L * 0.2, W * 0.5),
		_pt(p0, ax, pp, 4.0, W * 0.34),
	])
	draw_colored_polygon(hull, hull_c)
	var closed := hull.duplicate()
	closed.append(hull[0])
	if modern:
		draw_polyline(closed, Color(edge_c.r, edge_c.g, edge_c.b, edge_c.a * 0.25), 6.0)
	draw_polyline(closed, edge_c, 2.0)

	var deck := PackedVector2Array([
		_pt(p0, ax, pp, 10.0, -W * 0.24), _pt(p0, ax, pp, L - W * 1.2, -W * 0.30),
		_pt(p0, ax, pp, L - W * 0.75, 0.0), _pt(p0, ax, pp, L - W * 1.2, W * 0.30),
		_pt(p0, ax, pp, 10.0, W * 0.24),
	])
	draw_colored_polygon(deck, deck_c)

	var sname: String = ship["name"]
	if sname == "Carrier":
		for k in 6:
			var u := 16.0 + k * ((L - W * 1.5) / 6.0)
			draw_line(_pt(p0, ax, pp, u, 0.0), _pt(p0, ax, pp, u + 12.0, 0.0), detail_c, 2.0)
		draw_colored_polygon(PackedVector2Array([
			_pt(p0, ax, pp, L * 0.55, W * 0.30), _pt(p0, ax, pp, L * 0.72, W * 0.30),
			_pt(p0, ax, pp, L * 0.72, W * 0.5), _pt(p0, ax, pp, L * 0.55, W * 0.5)]), detail_c)
	elif sname == "Submarine":
		draw_circle(_pt(p0, ax, pp, L * 0.45, 0.0), W * 0.16, detail_c)
		draw_line(_pt(p0, ax, pp, L * 0.45, 0.0), _pt(p0, ax, pp, L * 0.45 + 8.0, 0.0), edge_c, 2.0)
	else:
		draw_colored_polygon(PackedVector2Array([
			_pt(p0, ax, pp, L * 0.38, -W * 0.17), _pt(p0, ax, pp, L * 0.58, -W * 0.17),
			_pt(p0, ax, pp, L * 0.58, W * 0.17), _pt(p0, ax, pp, L * 0.38, W * 0.17)]), detail_c)
		draw_circle(_pt(p0, ax, pp, L * 0.2, 0.0), W * 0.11, detail_c)
		if length >= 3:
			draw_circle(_pt(p0, ax, pp, L * 0.76, 0.0), W * 0.11, detail_c)
	if modern and not sunk and alpha >= 0.9:
		var blink := 0.5 + 0.5 * sin(time * 4.0 + length)
		draw_circle(_pt(p0, ax, pp, L * 0.5, 0.0), 2.5, Color(1, 1, 1, blink))


func _draw_shots() -> void:
	for i in N * N:
		var s := fleet.shots[i]
		if s == 0:
			continue
		var c := cell_center(i)
		if s == 1:
			_draw_miss(c)
		else:
			var sunk: bool = fleet.ships[fleet.ship_at[i]]["sunk"]
			_draw_hit(c, i, sunk)


func _draw_miss(c: Vector2) -> void:
	if modern:
		draw_arc(c, 8.0, 0.0, TAU, 20, Color(accent.r, accent.g, accent.b, 0.75), 1.6)
		draw_circle(c, 2.4, Color(accent.r, accent.g, accent.b, 0.85))
	else:
		draw_circle(c + Vector2(2, 3), 8.5, Color(0, 0, 0, 0.28))
		draw_circle(c, 8.5, Color(0.95, 0.95, 0.97))
		draw_arc(c, 8.5, 0.0, TAU, 20, Color(0.6, 0.62, 0.68), 1.2)
		draw_circle(c + Vector2(-2.5, -2.5), 3.0, Color(1, 1, 1))


func _draw_hit(c: Vector2, i: int, sunk: bool) -> void:
	if modern:
		draw_circle(c, 11.0, Color(1.0, 0.35, 0.1, 0.30))
		draw_arc(c, 9.0, 0.0, TAU, 20, Color(1.0, 0.45, 0.15), 2.0)
		draw_line(c + Vector2(-5, -5), c + Vector2(5, 5), Color(1.0, 0.8, 0.5), 2.0)
		draw_line(c + Vector2(-5, 5), c + Vector2(5, -5), Color(1.0, 0.8, 0.5), 2.0)
	else:
		draw_circle(c + Vector2(2, 3), 9.5, Color(0, 0, 0, 0.3))
		draw_circle(c, 9.5, Color(0.82, 0.10, 0.08))
		draw_arc(c, 9.5, 0.0, TAU, 20, Color(0.45, 0.04, 0.03), 1.4)
		draw_circle(c + Vector2(-3, -3), 3.0, Color(1.0, 0.7, 0.65))
	_draw_flame(c, i, 0.55 if sunk else 1.0, sunk)


func _draw_flame(c: Vector2, seed_i: int, sc: float, sunk: bool) -> void:
	var t := time * 9.0 + seed_i * 1.7
	var h := (13.0 + sin(t) * 3.5 + sin(t * 2.3) * 2.0) * sc
	draw_circle(c, 17.0 * sc, Color(1.0, 0.45, 0.05, 0.16))
	var base := c + Vector2(0, 6.0 * sc)
	for k in 3:
		var dx := (k - 1) * 5.5 * sc
		var hh := h * (1.0 - 0.25 * absi(k - 1)) + sin(t * 1.3 + k * 2.0) * 2.0
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(dx - 5.0 * sc, 0), base + Vector2(dx, -hh), base + Vector2(dx + 5.0 * sc, 0)]),
			Color(1.0, 0.42, 0.08, 0.88))
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(dx - 2.5 * sc, 0), base + Vector2(dx, -hh * 0.6), base + Vector2(dx + 2.5 * sc, 0)]),
			Color(1.0, 0.9, 0.3, 0.9))
	if sunk:
		for k in 3:
			var p := fmod(time * 0.6 + k * 0.33 + seed_i * 0.1, 1.0)
			draw_circle(c + Vector2(sin(p * 6.0 + k) * 5.0, -p * 28.0), 4.0 + p * 6.0,
				Color(0.1, 0.1, 0.1, 0.35 * (1.0 - p)))


func _draw_sonar_marks() -> void:
	for key in fleet.sonar:
		var center: int = key
		var count: int = fleet.sonar[key]
		var x0 := maxi(0, center % N - 1)
		var y0 := maxi(0, center / N - 1)
		var x1 := mini(N - 1, center % N + 1)
		var y1 := mini(N - 1, center / N + 1)
		var r := Rect2(MARGIN + x0 * CELL, MARGIN + y0 * CELL, (x1 - x0 + 1) * CELL, (y1 - y0 + 1) * CELL)
		var col := Color(1.0, 0.45, 0.35) if show_ships else Color(1.0, 0.9, 0.35)
		var pulse := 0.5 + 0.2 * sin(time * 3.0)
		draw_rect(r, Color(col.r, col.g, col.b, 0.07))
		draw_rect(r.grow(-1.5), Color(col.r, col.g, col.b, pulse), false, 2.0)
		var badge := cell_rect(center).position + Vector2(11, 12)
		draw_circle(badge, 9.0, Color(0, 0, 0, 0.7))
		var txt_col := Color(0.4, 1.0, 0.5) if count == 0 else col
		draw_string(font, badge + Vector2(-9, 5), str(count), HORIZONTAL_ALIGNMENT_CENTER, 18.0, 14, txt_col)


func _draw_preview() -> void:
	if not interactive or hover < 0 or preview.is_empty() or not ghost.is_empty():
		return
	var col: Color
	match preview_kind:
		"sonar":
			col = Color(0.3, 0.85, 1.0, 0.24)
		"air":
			col = Color(1.0, 0.6, 0.15, 0.28)
		_:
			col = Color(1.0, 0.3, 0.25, 0.26) if preview_ok else Color(0.7, 0.7, 0.7, 0.18)
	for c in preview:
		draw_rect(cell_rect(c).grow(-2.0), col)
	var ctr := cell_center(hover)
	var pulse := 1.0 + 0.08 * sin(time * 8.0)
	var rc := Color(1.0, 0.3, 0.25) if preview_ok else Color(0.7, 0.7, 0.7)
	if preview_kind == "sonar":
		rc = Color(0.4, 0.9, 1.0)
	elif preview_kind == "air":
		rc = Color(1.0, 0.65, 0.2)
	draw_arc(ctr, 16.0 * pulse, 0.0, TAU, 28, rc, 2.0)
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(ctr + d * 10.0, ctr + d * 24.0, rc, 2.0)


# ---------------------------------------------------------------- effects

func _missile_pos(e: Dictionary, p: float) -> Vector2:
	var q := p * p * (3.0 - 2.0 * p) * 0.35 + p * 0.65
	var s: Vector2 = e["start"]
	var t: Vector2 = e["end"]
	return s.lerp(t, q)


func _draw_fx() -> void:
	for e in fx:
		var age: float = e["age"]
		if age < 0.0:
			continue
		var p := clampf(age / float(e["dur"]), 0.0, 1.0)
		match e["type"]:
			"missile":
				_fx_missile(e, p)
			"splash":
				_fx_splash(e, p)
			"boom":
				_fx_boom(e, p)
			"sonar":
				_fx_sonar(e, p)
			"text":
				_fx_text(e, p)


func _fx_missile(e: Dictionary, p: float) -> void:
	var tp: Vector2 = e["end"]
	var r := lerpf(36.0, 14.0, p)
	draw_arc(tp, r, 0.0, TAU, 28, Color(1.0, 0.3, 0.2, 0.35 + 0.5 * p), 2.0)
	draw_arc(tp, r * 0.5, 0.0, TAU, 20, Color(1.0, 0.3, 0.2, 0.25 + 0.4 * p), 1.5)
	var pos := _missile_pos(e, p)
	var ahead := _missile_pos(e, minf(p + 0.02, 1.0))
	var dir := (ahead - pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	for k in 10:
		var pk := maxf(0.0, p - k * 0.025)
		draw_circle(_missile_pos(e, pk), maxf(1.0, 5.0 - k * 0.4),
			Color(1.0, maxf(0.2, 0.65 - k * 0.04), 0.2, maxf(0.0, 0.6 - k * 0.055)))
	var perp := Vector2(-dir.y, dir.x)
	var body := PackedVector2Array([
		pos + dir * 12.0, pos + perp * 3.5 + dir * 3.0, pos + perp * 3.5 - dir * 8.0,
		pos - perp * 3.5 - dir * 8.0, pos - perp * 3.5 + dir * 3.0])
	draw_colored_polygon(body, Color(0.85, 0.87, 0.9))
	draw_colored_polygon(PackedVector2Array([
		pos - dir * 3.0 + perp * 3.5, pos - dir * 9.0 + perp * 7.5, pos - dir * 9.0 + perp * 3.5]), Color(0.9, 0.2, 0.15))
	draw_colored_polygon(PackedVector2Array([
		pos - dir * 3.0 - perp * 3.5, pos - dir * 9.0 - perp * 7.5, pos - dir * 9.0 - perp * 3.5]), Color(0.9, 0.2, 0.15))
	draw_circle(pos - dir * 10.0, 4.0 + sin(time * 40.0), Color(1.0, 0.9, 0.4, 0.9))


func _fx_splash(e: Dictionary, p: float) -> void:
	var pos: Vector2 = e["pos"]
	var age: float = e["age"]
	for k in 2:
		var pk := clampf((age - k * 0.12) / 0.8, 0.0, 1.0)
		if pk > 0.0 and pk < 1.0:
			draw_arc(pos, 6.0 + pk * (34.0 + k * 10.0), 0.0, TAU, 28,
				Color(1, 1, 1, (1.0 - pk) * 0.85), 2.6 - k * 0.8)
	draw_circle(pos, 9.0 * (1.0 - p), Color(1, 1, 1, 0.5 * (1.0 - p)))
	for d in e["drops"]:
		var dir := Vector2(cos(d["a"]), sin(d["a"]))
		var dspd: float = d["s"]
		draw_circle(pos + dir * dspd * p * 0.55, 2.8 * (1.0 - p) + 0.4, Color(0.88, 0.96, 1.0, 1.0 - p))


func _fx_boom(e: Dictionary, p: float) -> void:
	var pos: Vector2 = e["pos"]
	var big: bool = e["big"]
	var sc := 1.6 if big else 1.0
	if p < 0.3:
		var q := p / 0.3
		draw_circle(pos, (10.0 + q * 38.0) * sc, Color(1.0, 0.96, 0.75, 1.0 - q))
	draw_circle(pos, (8.0 + p * 26.0) * sc, Color(1.0, 0.5, 0.1, (1.0 - p) * 0.65))
	draw_circle(pos, (5.0 + p * 14.0) * sc, Color(1.0, 0.9, 0.35, (1.0 - p) * 0.7))
	draw_arc(pos, p * 95.0 * sc, 0.0, TAU, 40, Color(1.0, 0.85, 0.6, (1.0 - p) * 0.7), 3.0)
	for d in e["parts"]:
		var dir := Vector2(cos(d["a"]), sin(d["a"]))
		var q := pow(p, 0.6)
		var spd: float = d["s"]
		var pp: Vector2 = pos + dir * spd * q * 0.7 + Vector2(0, 30.0 * p * p)
		var col: Color
		match int(d["c"]):
			0:
				col = Color(1.0, 0.55, 0.1)
			1:
				col = Color(1.0, 0.9, 0.35)
			_:
				col = Color(0.35, 0.33, 0.32)
		col.a = 1.0 - p
		draw_circle(pp, float(d["r"]) * (1.0 - p * 0.7), col)


func _fx_sonar(e: Dictionary, p: float) -> void:
	var pos: Vector2 = e["pos"]
	var radius := p * CELL * 3.2
	draw_circle(pos, radius, Color(0.3, 0.9, 1.0, 0.07 * (1.0 - p)))
	draw_arc(pos, radius, 0.0, TAU, 48, Color(0.4, 0.95, 1.0, 1.0 - p), 3.0)
	var r2 := maxf(0.0, p - 0.18) * CELL * 3.2
	draw_arc(pos, r2, 0.0, TAU, 48, Color(0.4, 0.95, 1.0, (1.0 - p) * 0.6), 2.0)
	var a := p * TAU * 2.0
	draw_line(pos, pos + Vector2(cos(a), sin(a)) * radius, Color(0.6, 1.0, 1.0, 0.8 * (1.0 - p)), 2.0)


func _fx_text(e: Dictionary, p: float) -> void:
	var pos: Vector2 = e["pos"]
	var col: Color = e["color"]
	col.a = 1.0 - p * p
	var at := pos + Vector2(-70.0, -18.0 - p * 38.0)
	draw_string_outline(font, at, e["text"], HORIZONTAL_ALIGNMENT_CENTER, 140.0, 20, 6, Color(0, 0, 0, col.a))
	draw_string(font, at, e["text"], HORIZONTAL_ALIGNMENT_CENTER, 140.0, 20, col)
