class_name Fleet
extends RefCounted
## One side's fleet and the shots that have been fired at it.

const N := 10
const SHIP_DEFS := [
	{"name": "Carrier", "length": 5},
	{"name": "Battleship", "length": 4},
	{"name": "Cruiser", "length": 3},
	{"name": "Submarine", "length": 3},
	{"name": "Destroyer", "length": 2},
]

var ship_at := PackedInt32Array()   # cell -> ship index or -1
var shots := PackedInt32Array()     # cell -> 0 unknown, 1 miss, 2 hit
var ships: Array = []               # {name,length,cells,hits,sunk,horizontal}
var sonar: Dictionary = {}          # centre cell -> ship tiles counted


func _init() -> void:
	reset()


func reset() -> void:
	shots.resize(N * N)
	shots.fill(0)
	sonar.clear()
	clear_ships()


func clear_ships() -> void:
	ship_at.resize(N * N)
	ship_at.fill(-1)
	ships.clear()


static func idx(x: int, y: int) -> int:
	return y * N + x


static func cx(i: int) -> int:
	return i % N


@warning_ignore("integer_division")
static func cy(i: int) -> int:
	return i / N


static func inb(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < N and y < N


func cells_for(x: int, y: int, length: int, horizontal: bool) -> Array:
	var out: Array = []
	for k in length:
		out.append(idx(x + k, y) if horizontal else idx(x, y + k))
	return out


func fits(x: int, y: int, length: int, horizontal: bool) -> bool:
	if x < 0 or y < 0:
		return false
	if horizontal and (x + length > N or y >= N):
		return false
	if not horizontal and (y + length > N or x >= N):
		return false
	for c in cells_for(x, y, length, horizontal):
		if ship_at[c] != -1:
			return false
	return true


func place(x: int, y: int, length: int, horizontal: bool, ship_name: String) -> bool:
	if not fits(x, y, length, horizontal):
		return false
	var cells := cells_for(x, y, length, horizontal)
	var id := ships.size()
	for c in cells:
		ship_at[c] = id
	ships.append({
		"name": ship_name, "length": length, "cells": cells,
		"hits": 0, "sunk": false, "horizontal": horizontal,
	})
	return true


func remove_last() -> void:
	if ships.is_empty():
		return
	var s: Dictionary = ships.pop_back()
	for c in s["cells"]:
		ship_at[c] = -1


func random_place() -> void:
	clear_ships()
	for def in SHIP_DEFS:
		var length: int = def["length"]
		var tries := 0
		while tries < 1000:
			tries += 1
			var h := randf() < 0.5
			var mx := N - (length if h else 1) + 1
			var my := N - (1 if h else length) + 1
			var x := randi() % mx
			var y := randi() % my
			if place(x, y, length, h, def["name"]):
				break


## Returns {"result": "miss"|"hit"|"sunk"|"repeat", "ship": Dictionary?}
func receive_shot(i: int) -> Dictionary:
	if shots[i] != 0:
		return {"result": "repeat"}
	if ship_at[i] == -1:
		shots[i] = 1
		return {"result": "miss"}
	shots[i] = 2
	var s: Dictionary = ships[ship_at[i]]
	s["hits"] += 1
	if s["hits"] >= s["length"]:
		s["sunk"] = true
		return {"result": "sunk", "ship": s}
	return {"result": "hit", "ship": s}


func all_sunk() -> bool:
	if ships.is_empty():
		return false
	for s in ships:
		if not s["sunk"]:
			return false
	return true


func remaining_lengths() -> Array:
	var out: Array = []
	for s in ships:
		if not s["sunk"]:
			out.append(s["length"])
	return out


## Number of still-unrevealed ship tiles in the 3x3 area around a centre cell.
func sonar_count(center: int) -> int:
	var count := 0
	var x0 := cx(center)
	var y0 := cy(center)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := x0 + dx
			var y := y0 + dy
			if inb(x, y):
				var c := idx(x, y)
				if ship_at[c] >= 0 and shots[c] == 0:
					count += 1
	return count
