class_name SoundSettings
extends RefCounted
## Volume settings: everything, your own car (engine, tyres, crashes) and the opponents.
## Each runs on its own audio bus so the levels can be changed while driving.

const BUSES := ["Player", "Opponents"]
const SETTINGS := "user://settings.cfg"

static var master := 0.8
static var player := 1.0
static var opponents := 0.7

static func ensure_buses() -> void:
	for nm in BUSES:
		if AudioServer.get_bus_index(nm) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, nm)
			AudioServer.set_bus_send(i, "Master")

static func apply() -> void:
	ensure_buses()
	_set_bus("Master", master)
	_set_bus("Player", player)
	_set_bus("Opponents", opponents)

static func _set_bus(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))

static func load_saved() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		master = cf.get_value("audio", "master", master)
		player = cf.get_value("audio", "player", player)
		opponents = cf.get_value("audio", "opponents", opponents)
	apply()

static func save() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("audio", "master", master)
	cf.set_value("audio", "player", player)
	cf.set_value("audio", "opponents", opponents)
	cf.save(SETTINGS)

static func value(key: String) -> float:
	match key:
		"master":
			return master
		"player":
			return player
		_:
			return opponents

static func set_value(key: String, v: float) -> void:
	match key:
		"master":
			master = v
		"player":
			player = v
		_:
			opponents = v
