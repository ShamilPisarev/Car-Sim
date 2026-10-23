class_name SaveGame
extends RefCounted
## Everything that should survive closing the game, in Godot's user folder:
## menu choices (settings.cfg), lap records (records.cfg) and an unfinished championship.

const SETTINGS := "user://settings.cfg"
const RECORDS := "user://records.cfg"

static func load_settings(first_start: bool) -> Dictionary:
	## puts saved choices back; returns laps / opponents / car for the menu
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK:
		return {}
	CarSpecs.arcade = cf.get_value("game", "arcade", false)
	Weather.time_of_day = cf.get_value("game", "time", "day")
	Weather.rain = cf.get_value("game", "rain", false)
	RacingLineAssist.mode = cf.get_value("game", "line", 0)
	CarSetup.wear_and_fuel = cf.get_value("game", "wear", false)
	RaceManager.ai_level = cf.get_value("game", "ai_level", 2)
	if first_start:
		RaceTrack.reversed = cf.get_value("game", "reversed", false)
	for k in ["downforce", "brake_bias", "springs", "arb_balance", "gearing"]:
		CarSetup.set_val(k, cf.get_value("setup", k, 0))
	return {"car": cf.get_value("game", "car", "gt"), "laps": cf.get_value("game", "laps", 3),
		"opponents": cf.get_value("game", "opponents", 5)}

static func save_settings(car_id: String, laps: int, opponents: int) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("game", "arcade", CarSpecs.arcade)
	cf.set_value("game", "time", Weather.time_of_day)
	cf.set_value("game", "rain", Weather.rain)
	cf.set_value("game", "line", RacingLineAssist.mode)
	cf.set_value("game", "wear", CarSetup.wear_and_fuel)
	cf.set_value("game", "ai_level", RaceManager.ai_level)
	cf.set_value("game", "reversed", RaceTrack.reversed)
	cf.set_value("game", "car", car_id)
	cf.set_value("game", "laps", laps)
	cf.set_value("game", "opponents", opponents)
	for k in ["downforce", "brake_bias", "springs", "arb_balance", "gearing"]:
		cf.set_value("setup", k, CarSetup.get_val(k))
	cf.save(SETTINGS)

# ------------------------------------------------------------------ lap records
static func _record_key(car_id: String) -> Array:
	var layout := "reverse" if RaceTrack.reversed else "forward"
	var cond := "%s%s%s" % [Weather.time_of_day, "_wet" if Weather.rain else "", "_arcade" if CarSpecs.arcade else ""]
	return [layout, "%s|%s" % [car_id, cond]]

static func record_lap(car_id: String, t: float) -> bool:
	## true when this is a new record for the car, circuit and conditions
	if t <= 0.0:
		return false
	var cf := ConfigFile.new()
	cf.load(RECORDS)
	var key := _record_key(car_id)
	var best: float = cf.get_value(key[0], key[1], 0.0)
	if best > 0.0 and t >= best:
		return false
	cf.set_value(key[0], key[1], t)
	cf.save(RECORDS)
	return true

static func best_lap(car_id: String) -> float:
	var cf := ConfigFile.new()
	if cf.load(RECORDS) != OK:
		return 0.0
	var key := _record_key(car_id)
	return cf.get_value(key[0], key[1], 0.0)

# ------------------------------------------------------------------ championship
static func save_championship() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("championship", "active", Championship.active and Championship.round_index < Championship.ROUNDS.size())
	cf.set_value("championship", "round", Championship.round_index)
	cf.set_value("championship", "points", Championship.points)
	cf.save(SETTINGS)

static func saved_championship_round() -> int:
	## the round to continue from, or -1 when there is no unfinished championship
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK or not cf.get_value("championship", "active", false):
		return -1
	return cf.get_value("championship", "round", 0)

static func load_championship() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK:
		return
	Championship.active = true
	Championship.round_index = cf.get_value("championship", "round", 0)
	Championship.points = cf.get_value("championship", "points", {})
