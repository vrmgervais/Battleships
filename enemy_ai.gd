class_name EnemyAI
extends RefCounted
## The computer opponent. Difficulty 0 = Easy, 1 = Normal, 2 = Hard.

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var difficulty := 1
var sonar_left := 2
var air_left := 1
var clear: Dictionary = {}   # cells sonar says are empty
var hot: Dictionary = {}     # cell -> extra weight from sonar contacts
var turns := 0


func reset(d: int) -> void:
	difficulty = d
	sonar_left = 2
	air_left = 1
	clear.clear()
	hot.clear()
	turns = 0


func unresolved_hits(f: Fleet) -> Array:
	var out: Array = []
	for i in Fleet.N * Fleet.N:
		if f.shots[i] == 2:
			var s: Dictionary = f.ships[f.ship_at[i]]
			if not s["sunk"]:
				out.append(i)
	return out


func choose_shot(f: Fleet) -> int:
	match difficulty:
		0:
			return _easy(f)
		2:
			return _hard(f)
		_:
			return _normal(f)


## Decide whether to use a power this turn: {"type": "none"|"sonar"|"air", "cell": int}
func decide_power(f: Fleet) -> Dictionary:
	turns += 1
	if difficulty == 0:
		return {"type": "none"}
	if air_left > 0 and turns >= 6 and randf() < 0.35:
		var c := choose_shot(f)
		if _plus_unshot(f, c).size() >= 4:
			return {"type": "air", "cell": c}
	if sonar_left > 0 and turns >= 2 and turns <= 28 and randf() < 0.22 \
			and unresolved_hits(f).is_empty():
		var options: Array = []
		for y in range(1, Fleet.N - 1):
			for x in range(1, Fleet.N - 1):
				var c := Fleet.idx(x, y)
				var open := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if f.shots[Fleet.idx(x + dx, y + dy)] == 0:
							open += 1
				if open >= 7 and not clear.has(c):
					options.append(c)
		if not options.is_empty():
			return {"type": "sonar", "cell": options.pick_random()}
	return {"type": "none"}


func record_sonar(center: int, count: int, f: Fleet) -> void:
	var x0 := Fleet.cx(center)
	var y0 := Fleet.cy(center)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := x0 + dx
			var y := y0 + dy
			if not Fleet.inb(x, y):
				continue
			var c := Fleet.idx(x, y)
			if f.shots[c] != 0:
				continue
			if count == 0:
				clear[c] = true
			else:
				hot[c] = hot.get(c, 0.0) + 6.0 * count


func plus_cells(f: Fleet, center: int) -> Array:
	return _plus_unshot(f, center)


func _plus_unshot(f: Fleet, center: int) -> Array:
	var out: Array = []
	var x0 := Fleet.cx(center)
	var y0 := Fleet.cy(center)
	var pts := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in pts:
		var x: int = x0 + d.x
		var y: int = y0 + d.y
		if Fleet.inb(x, y) and f.shots[Fleet.idx(x, y)] == 0:
			out.append(Fleet.idx(x, y))
	return out


func _random_unshot(f: Fleet) -> int:
	var cand: Array = []
	for i in Fleet.N * Fleet.N:
		if f.shots[i] == 0:
			cand.append(i)
	return cand.pick_random()


func _easy(f: Fleet) -> int:
	var un := unresolved_hits(f)
	if not un.is_empty() and randf() < 0.55:
		var h: int = un.pick_random()
		var nb: Array = []
		for d in DIRS:
			var x: int = Fleet.cx(h) + d.x
			var y: int = Fleet.cy(h) + d.y
			if Fleet.inb(x, y) and f.shots[Fleet.idx(x, y)] == 0:
				nb.append(Fleet.idx(x, y))
		if not nb.is_empty():
			return nb.pick_random()
	return _random_unshot(f)


func _normal(f: Fleet) -> int:
	var un := unresolved_hits(f)
	if not un.is_empty():
		var score := {}
		for h in un:
			for d in DIRS:
				var x: int = Fleet.cx(h) + d.x
				var y: int = Fleet.cy(h) + d.y
				if not Fleet.inb(x, y):
					continue
				var j := Fleet.idx(x, y)
				if f.shots[j] != 0:
					continue
				var w := 1.0
				var px: int = Fleet.cx(h) - d.x
				var py: int = Fleet.cy(h) - d.y
				if Fleet.inb(px, py) and f.shots[Fleet.idx(px, py)] == 2:
					w += 4.0   # extend an existing line of hits
				score[j] = score.get(j, 0.0) + w
		if not score.is_empty():
			return _best(score)
	# Hunt mode: follow sonar hints, otherwise checkerboard.
	var best_hot := -1
	var best_val := 0.0
	for k in hot:
		if f.shots[k] == 0 and hot[k] > best_val:
			best_val = hot[k]
			best_hot = k
	if best_hot >= 0 and randf() < 0.7:
		return best_hot
	var cand: Array = []
	for i in Fleet.N * Fleet.N:
		if f.shots[i] == 0 and not clear.has(i) and (Fleet.cx(i) + Fleet.cy(i)) % 2 == 0:
			cand.append(i)
	if cand.is_empty():
		return _random_unshot(f)
	return cand.pick_random()


func _hard(f: Fleet) -> int:
	var score := PackedFloat32Array()
	score.resize(Fleet.N * Fleet.N)
	for length in f.remaining_lengths():
		for horizontal in [true, false]:
			for y in Fleet.N:
				for x in Fleet.N:
					if horizontal and x + length > Fleet.N:
						continue
					if not horizontal and y + length > Fleet.N:
						continue
					var cells := f.cells_for(x, y, length, horizontal)
					var ok := true
					var covered := 0
					for c in cells:
						if f.shots[c] == 1 or clear.has(c):
							ok = false
							break
						if f.shots[c] == 2:
							if f.ships[f.ship_at[c]]["sunk"]:
								ok = false
								break
							covered += 1
					if not ok:
						continue
					var w := 1.0 + covered * covered * 14.0
					for c in cells:
						if f.shots[c] == 0:
							score[c] += w
	var best := -1
	var best_v := -1.0
	for i in Fleet.N * Fleet.N:
		if f.shots[i] != 0:
			continue
		var v: float = score[i] + hot.get(i, 0.0) + randf() * 0.05
		if v > best_v:
			best_v = v
			best = i
	if best < 0:
		return _random_unshot(f)
	return best


func _best(score: Dictionary) -> int:
	var best_v := -1.0
	var best: Array = []
	for k in score:
		var v: float = score[k]
		if v > best_v + 0.0001:
			best_v = v
			best = [k]
		elif absf(v - best_v) <= 0.0001:
			best.append(k)
	return best.pick_random()
