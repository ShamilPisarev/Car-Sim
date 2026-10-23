class_name Championship
extends RefCounted
## A four-round season: the same field races in changing conditions, points after every
## round (25-18-15-12-10-8 for the top six), the champion crowned after the last.

const POINTS := [25, 18, 15, 12, 10, 8]
const ROUNDS := [
	{"name": "Round 1 - Afternoon", "time": "day", "rain": false},
	{"name": "Round 2 - Sunset", "time": "sunset", "rain": false},
	{"name": "Round 3 - Wet", "time": "day", "rain": true},
	{"name": "Round 4 - Night", "time": "night", "rain": false},
]

static var active := false
static var round_index := 0
static var points := {}              # driver name -> points
static var last_result: Array = []   # [[name, points scored this round], ...] in finishing order

static func start() -> void:
	active = true
	round_index = 0
	points.clear()
	last_result.clear()

static func stop() -> void:
	active = false

static func current() -> Dictionary:
	return ROUNDS[clampi(round_index, 0, ROUNDS.size() - 1)]

static func is_last_round() -> bool:
	return round_index >= ROUNDS.size() - 1

static func record(order: Array) -> void:
	## order: driver names in finishing order (retired cars at the end score nothing)
	last_result.clear()
	for k in order.size():
		var nm: String = order[k]
		var p: int = POINTS[k] if k < POINTS.size() else 0
		points[nm] = int(points.get(nm, 0)) + p
		last_result.append([nm, p])

static func next_round() -> void:
	round_index += 1

static func table() -> Array:
	## [[name, points], ...] best first
	var rows := []
	for nm in points.keys():
		rows.append([nm, points[nm]])
	rows.sort_custom(func(a, b) -> bool: return a[1] > b[1])
	return rows
