extends Node3D

var car: Car
var cam: ChaseCam
var world: TestWorld
var track = null
var hud: Hud
var audio: EngineAudio
var race: RaceManager
var skids: SkidMarks
var selftest := ""
var _t := 0.0
var _log := PackedStringArray()
var _xray := 0
var player_model := "gt"
var menu: GameMenu
var weather: Weather
var replay: ReplaySystem
var ghost: GhostLap
var line_assist: RacingLineAssist
var kind := "race"                       # race / championship / timetrial / practice
static var last_car := ""                # remembered across a layout change (scene reload)
const PROVING_OFFSET := Vector3(1500, 0, 0)

func _ready() -> void:
	SoundSettings.load_saved()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--selftest="):
			selftest = a.substr(11)
		elif a.begins_with("--setup="):
			for kv in a.substr(8).split(","):
				var parts := kv.split(":")
				CarSetup.set_val(parts[0], int(parts[1]))
		elif a == "--reverse":
			RaceTrack.reversed = true
		elif a.begins_with("--car="):
			player_model = a.substr(6)
		elif a.begins_with("--from="):
			brake_from = float(a.substr(7))
		elif a == "--rain":
			Weather.rain = true
		elif a == "--night" or a == "--sunset":
			Weather.time_of_day = a.substr(2)
		elif a == "--arcade":
			CarSpecs.arcade = true
		elif a.begins_with("--clip="):
			clip = a.substr(7)
	if selftest != "":
		# test runs render as fast as they can (no waiting on the display's refresh)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var trailer_track := selftest == "trailer" and not clip in ["drift", "crash"]
	var use_track := trailer_track or selftest in ["", "trackshot", "lap", "race", "raceshot", "ai1", "dentshot", "carsshot", "menushot", "hillshot", "terraincheck", "pittest", "champtest", "tttest", "replayshot", "startshot", "offtrack", "rearshot", "frontshot"]
	var use_race := trailer_track or selftest in ["", "race", "raceshot", "ai1", "dentshot", "menushot", "pittest", "champtest", "tttest", "replayshot", "startshot", "offtrack", "rearshot", "frontshot"]
	skids = SkidMarks.new()
	skids.name = "SkidMarks"
	add_child(skids)
	world = TestWorld.new()
	if use_track:
		world.position = PROVING_OFFSET
	add_child(world)
	if selftest == "":
		var sv := SaveGame.load_settings(last_car == "")
		if not sv.is_empty() and last_car == "":
			player_model = sv["car"]
			GameMenu.saved = {"laps": sv["laps"], "opponents": sv["opponents"]}
	if last_car != "":
		player_model = last_car
	car = Car.new()
	car.name = "Car"
	car.spec_id = player_model
	car.use_setup = true
	add_child(car)
	if use_track:
		var ts = load("res://scripts/track.gd") if ResourceLoader.exists("res://scripts/track.gd") else null
		if ts != null:
			track = ts.new()
			track.name = "Track"
			add_child(track)
			track.car = car
		if track != null:
			var tr: Transform3D = track.get_start_transform()
			car.reset_car(tr.origin - Vector3(0, 0.17, 0), tr.basis.get_euler().y)
		else:
			car.reset_car(PROVING_OFFSET + Vector3(0, 0.15, 0), 0.0)
	else:
		car.reset_car(Vector3(0, 0.15, 0), 0.0)
	if selftest == "crashshot" or selftest == "crash":
		_log.append("start z=%.1f" % 150.0)
	cam = ChaseCam.new()
	cam.target = car
	cam.far = 3000.0
	cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(cam)
	cam.current = true
	if use_race and track != null:
		race = RaceManager.new()
		race.name = "Race"
		if selftest == "ai1":
			race.ai_count = 0
		add_child(race)
		race.setup(track, car, cam)
		if selftest == "trailer" or selftest in ["race", "raceshot", "ai1", "champtest", "tttest", "replayshot", "startshot", "offtrack", "rearshot", "frontshot"]:
			var drv := AIDriver.new()
			drv.name = "Driver"
			drv.race = race
			drv.car = car
			drv.grid_slot = RaceManager.PLAYER_SLOT
			drv.skill = 0.95
			car.add_child(drv)
	weather = Weather.new()
	weather.name = "Weather"
	weather.world = world
	weather.track = track
	weather.cam = cam
	weather.cars_fn = func() -> Array: return race.cars if race != null else [car]
	add_child(weather)
	weather.apply()
	if race != null:
		replay = ReplaySystem.new()
		replay.name = "Replay"
		replay.race = race
		replay.cam = cam
		add_child(replay)
		replay.finished.connect(_on_replay_done)
		ghost = GhostLap.new()
		ghost.name = "Ghost"
		add_child(ghost)
		ghost.setup(car, track)
		line_assist = RacingLineAssist.new()
		line_assist.name = "RacingLine"
		line_assist.race = race
		line_assist.car = car
		add_child(line_assist)
	if selftest == "" or selftest in ["raceshot", "startshot", "menushot", "trailer"]:
		var pfx := PostFX.new()
		pfx.name = "PostFX"
		pfx.car = car
		pfx.cam = cam
		add_child(pfx)
	hud = Hud.new()
	add_child(hud)
	hud.car = car
	hud.cam = cam
	hud.track = track
	hud.race = race
	hud.ghost = ghost
	audio = EngineAudio.new()
	add_child(audio)
	audio.bind(car)
	if selftest == "" or selftest == "menushot":
		cam.process_mode = Node.PROCESS_MODE_ALWAYS     # keeps turning behind the menu
		menu = GameMenu.new()
		menu.main = self
		menu.car_id = car.spec_id
		menu.arcade = CarSpecs.arcade
		add_child(menu)
		if race != null:
			race.car_finished.connect(_on_car_finished)
		if track != null:
			track.lap_completed.connect(_on_lap_record)
		open_main_menu()
	if selftest != "":
		hud.visible = selftest == "raceshot"
		if selftest != "trailer":
			audio.toggle_mute()
		else:
			_trailer_setup()
		if selftest == "crash" or selftest == "crashshot" or clip == "crash":
			world._body(Vector3(100, 0.7, 40), Vector3(12, 1.4, 1.0), world.concrete_mat)
		if not trailer_track and not selftest in ["bumps", "trackshot", "lap", "race", "raceshot", "ai1", "dentshot", "carsshot", "menushot", "hillshot", "terraincheck", "pittest", "champtest", "tttest", "replayshot", "startshot", "offtrack", "rearshot", "frontshot"]:
			car.reset_car(Vector3(100, 0.15, 150), 0.0)
	if selftest == "menushot":
		_menushot()

func _unhandled_key_input(event: InputEvent) -> void:
	var e := event as InputEventKey
	if e == null or not e.pressed or e.echo:
		return
	match e.keycode:
		KEY_R:
			if car.is_flipped():
				car.flip_upright()
			elif track != null and car.global_position.x < 1000.0:
				var tr: Transform3D = track.respawn_transform_near(car.global_position)
				car.reset_car(tr.origin, tr.basis.get_euler().y)
			else:
				car.reset_car(car.global_position + Vector3(0, 1.0, 0), car.global_rotation.y)
		KEY_V:
			cam.cycle()
		KEY_TAB:
			hud.show_debug = not hud.show_debug
		KEY_F1:
			hud.show_help = not hud.show_help
		KEY_F2:
			audio.toggle_mute()
		KEY_F5:
			car.hold = false
			car.reset_car(PROVING_OFFSET + Vector3(0, 0.15, 0), 0.0)
			hud.flash("Proving ground")
		KEY_F6, KEY_F7:
			if race != null:
				race.restart()
				hud.flash("Race restart: wait for the lights")
			elif track != null:
				var tr2: Transform3D = track.get_start_transform()
				car.reset_car(tr2.origin, tr2.basis.get_euler().y)
				hud.flash("Circuit")
		KEY_X:
			_xray = (_xray + 1) % 2
			car.set_xray(_xray)
		KEY_ESCAPE:
			if replay != null and replay.playing:
				return
			if menu != null:
				get_viewport().set_input_as_handled()
				_pause()
				return
			quit_game()
		_:
			pass
	car.handle_part_key(e.keycode)

# ------------------------------------------------------------ menu flow
func open_main_menu() -> void:
	## settings screen: the race waits on the grid, the camera turns around your car
	get_tree().paused = true
	hud.visible = false
	if race != null:
		race.restart()
	cam.mode = 3
	cam.orbit_pitch = 0.18
	cam.orbit_dist = 7.5
	menu.show_main()

func change_layout(rev: bool) -> void:
	## the other direction is a different track: rebuild the world (settings are static)
	RaceTrack.reversed = rev
	last_car = car.spec_id
	get_tree().paused = false
	get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent) -> void:
	# gamepad Start pauses, like Esc
	if event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START:
		if menu != null and not get_tree().paused and not (replay != null and replay.playing):
			get_viewport().set_input_as_handled()
			_pause()

func preview_car(id: String) -> void:
	## show the car picked in the menu straight away
	if id != car.spec_id:
		_swap_player(id)

func start_race(settings: Dictionary) -> void:
	kind = settings.get("kind", "race")
	CarSpecs.arcade = settings["arcade"]
	Weather.time_of_day = settings.get("time", "day")
	Weather.rain = settings.get("rain", false)
	if kind == "continue":
		SaveGame.load_championship()
		kind = "championship"
	elif kind == "championship":
		Championship.start()
	else:
		Championship.stop()
	if Championship.active:
		Weather.time_of_day = Championship.current()["time"]
		Weather.rain = Championship.current()["rain"]
		SaveGame.save_championship()
	if menu != null:
		SaveGame.save_settings(settings["car"], menu.laps, menu.opponents)
	weather.apply()
	last_car = settings["car"]
	if settings["car"] != car.spec_id:
		_swap_player(settings["car"])
	car.apply_setup()
	if race != null:
		race.laps = settings["laps"]
		race.set_field(settings["opponents"])
		race.restart()
		_begin_session()
	_go()
	var what := {"race": "race - wait for the lights", "practice": "practice", "timetrial": "time trial - beat your ghost",
		"championship": Championship.current()["name"] if Championship.active else ""}
	hud.flash(("ARCADE " if CarSpecs.arcade else "REALISTIC ") + str(what.get(kind, "")) + ("  -  wet track, less grip" if Weather.rain else ""))

func _begin_session() -> void:
	## per-start bookkeeping: ghost on in time trial, a fresh replay recording for real races
	if ghost != null:
		ghost.enabled = kind == "timetrial"
		ghost.car = car
		ghost.reset()
	if line_assist != null:
		line_assist.car = car
	if replay != null and race.laps > 0:
		replay.start_recording()

func next_round() -> void:
	## championship: on to the next round (conditions change), or show the final table
	if Championship.is_last_round():
		Championship.next_round()
		SaveGame.save_championship()
		menu.show_pause(true)
		return
	Championship.next_round()
	SaveGame.save_championship()
	Weather.time_of_day = Championship.current()["time"]
	Weather.rain = Championship.current()["rain"]
	weather.apply()
	race.restart()
	_begin_session()
	_go()
	hud.flash(Championship.current()["name"] + ("  -  wet track, less grip" if Weather.rain else ""))

func _on_lap_record(t: float, _n: int) -> void:
	## every completed lap of yours counts towards the record for this car and these conditions
	if SaveGame.record_lap(car.spec_id, t) and race != null:
		race.say("NEW LAP RECORD  %s" % _fmt(t), 4.0)

func watch_replay() -> void:
	menu.hide_menu()
	hud.visible = false
	race.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false
	replay.play()

func _on_replay_done() -> void:
	race.process_mode = Node.PROCESS_MODE_INHERIT
	get_tree().paused = true
	menu.show_pause(true)

func _fmt(t: float) -> String:
	return "%d:%06.3f" % [int(t / 60.0), fmod(t, 60.0)]

func results_text(race_over: bool) -> String:
	## text for the pause / results panel: championship table, time trial record
	var out := ""
	if kind == "timetrial" and ghost != null:
		out += "Best lap: %s" % (_fmt(ghost.best_time) if ghost.best_time > 0.0 else "no lap yet")
	if Championship.active:
		if race_over and Championship.round_index < Championship.ROUNDS.size():
			var t := "after %s" % Championship.current()["name"]
			if Championship.is_last_round():
				t = "FINAL STANDINGS"
			out += t + "\n"
		elif race_over:
			out += "FINAL STANDINGS\n"
		else:
			out += Championship.current()["name"] + "\n"
		var rows := Championship.table()
		for k in rows.size():
			out += "%d.  %-10s %3d pts\n" % [k + 1, rows[k][0], rows[k][1]]
		if race_over and Championship.round_index >= Championship.ROUNDS.size() - 1 and rows.size() > 0:
			out += "\nChampion: %s" % rows[0][0]
	if race != null and race.penalty.get(car, 0.0) > 0.0:
		out += "\nYour time includes %d s of track-limits penalties" % int(race.penalty[car])
	return out.strip_edges()

func best_lap_text(id: String, time: String, wet: bool, arc: bool) -> String:
	var lap := SaveGame.best_lap(id)
	var out := "Lap record (this car, circuit, conditions): %s" % (_fmt(lap) if lap > 0.0 else "none yet")
	var key := "user://ghost_%s_%s%s%s.dat" % [id, time, "_wet" if wet else "", "_arcade" if arc else ""]
	if FileAccess.file_exists(key):
		var f := FileAccess.open(key, FileAccess.READ)
		var d = f.get_var()
		if d is Dictionary:
			out += "\nTime trial ghost: %s" % _fmt(d.get("time", 0.0))
	return out

func restart_race() -> void:
	if race != null:
		race.restart()
	_go()

func resume_game() -> void:
	_go()

func _go() -> void:
	menu.hide_menu()
	hud.visible = true
	if cam.mode == 3:
		cam.mode = 0
	cam._initialised = false
	get_tree().paused = false

func _pause() -> void:
	get_tree().paused = true
	menu.show_pause()

func _on_car_finished(c: Car, _place: int, _time: float) -> void:
	## your race is over: give the results a moment on screen, then offer race again / menu
	if c != car:
		return
	if Championship.active:
		var order: Array = []
		for o in race.standings():
			order.append(race.name_of(o) if not race.dnf.has(o) else "")
		var names: Array = []
		for k in order.size():
			if order[k] != "":
				names.append(order[k])
		for o in race.dnf.keys():
			names.append(race.name_of(o))            # retired: listed, but outside the points
		Championship.record(names.slice(0, race.cars.size() - race.dnf.size()))
		SaveGame.save_championship()
		for o in race.dnf.keys():
			if not Championship.points.has(race.name_of(o)):
				Championship.points[race.name_of(o)] = 0
	await get_tree().create_timer(5.0).timeout
	if not get_tree().paused:
		get_tree().paused = true
		menu.show_pause(true)

func _swap_player(id: String) -> void:
	## replace your car with another model (on the grid when racing, else where you are)
	var old := car
	var xf := old.global_transform
	car = Car.new()
	car.name = "Car_" + id
	car.spec_id = id
	car.use_setup = true
	car.abs_enabled = old.abs_enabled
	car.tc_enabled = old.tc_enabled
	car.assist_enabled = old.assist_enabled
	add_child(car)
	car.reset_car(xf.origin + Vector3(0, 0.3, 0), xf.basis.get_euler().y)
	cam.target = car
	hud.car = car
	var pfx2 := get_node_or_null("PostFX") as PostFX
	if pfx2 != null:
		pfx2.car = car
	audio.bind(car)
	if track != null:
		track.car = car
	if race != null:
		race.replace_player(car)
		race.restart()
	old.queue_free()
	if weather != null:
		weather.refresh_cars()
	if ghost != null:
		ghost.car = car
		ghost.reset()
	if line_assist != null:
		line_assist.car = car

func _process(_dt: float) -> void:
	if audio != null and cam != null:
		audio.interior = cam.mode == 1 or cam.mode == 2

# ------------------------------------------------------------ self tests
func _physics_process(dt: float) -> void:
	if selftest == "":
		return
	_t += dt
	match selftest:
		"settle": _run_settle()
		"accel": _run_accel()
		"brake": _run_brake()
		"corner": _run_corner()
		"drift": _run_drift()
		"bumps": _run_bumps()
		"shot": _run_shot()
		"crash": _run_crash()
		"trackshot": _run_trackshot()
		"lap": _run_lap()
		"crashshot": _run_crashshot()
		"race": _run_race()
		"ai1": _run_ai1()
		"raceshot": _run_raceshot()
		"audio": _run_audio()
		"driftshot": _run_driftshot()
		"dentshot": _run_dentshot()
		"carsshot": _run_carsshot()
		"menushot": pass
		"hillshot": _run_hillshot()
		"terraincheck": _run_terraincheck()
		"pittest": _run_pittest()
		"champtest": _run_champtest()
		"tttest": _run_tttest()
		"replayshot": _run_replayshot()
		"startshot": _run_startshot()
		"offtrack": _run_offtrack()
		"rearshot": _run_rearshot()
		"frontshot": _run_frontshot()                         # driven by _menushot() timers
		"trailer": _run_trailer()
		"fliptest": _run_fliptest()
		"contacttest": _run_contacttest()
		_: finish("unknown test")

func finish(msg := "") -> void:
	_log.append(msg)
	var f := FileAccess.open("res://selftest_%s.txt" % selftest, FileAccess.WRITE)
	f.store_string("\n".join(_log) + "\n")
	f.close()
	quit_game()

func quit_game() -> void:
	## shut down quietly: stop every sound stream and the physics first, then quit a frame
	## later (quitting while audio generators were still being fed could crash on exit)
	set_process(false)
	set_physics_process(false)
	for p in find_children("*", "AudioStreamPlayer", true, false) + find_children("*", "AudioStreamPlayer3D", true, false):
		p.process_mode = Node.PROCESS_MODE_DISABLED
		p.stop()
	if audio != null:
		audio.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = true
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()

func _w(tag: String) -> Car.Wheel:
	return car.get_wheel(tag)

func _tick(per_s: int) -> bool:
	return int(_t * per_s) != int((_t - 1.0 / 120.0) * per_s)

func _run_settle() -> void:
	if _tick(10):
		_log.append("t=%.1f y=%.3f vy=%.3f comp FL=%.3f FR=%.3f RL=%.3f RR=%.3f fz FL=%.0f RL=%.0f" % [
			_t, car.global_position.y, car.linear_velocity.y,
			car.compression("FL"), car.compression("FR"), car.compression("RL"), car.compression("RR"),
			_w("FL").fz, _w("RL").fz])
	if _t > 4.0:
		finish("sag expected ~0.0 compression at rest")

var _t100 := -1.0
func _run_accel() -> void:
	car.ai_input = {"throttle": 1.0, "brake": 0.0, "steer": 0.0, "handbrake": 0.0}
	if _t100 < 0.0 and car.speed_kmh >= 100.0:
		_t100 = _t
	if _tick(2):
		_log.append("t=%.1f v=%.1f km/h gear=%d rpm=%.0f z=%.1f slipRL=%.2f tc=%s" % [_t, car.speed_kmh, car.gear, car.engine_rpm, car.global_position.z, _w("RL").slip_ratio, str(car.tc_active)])
	if _t > 20.0:
		finish("0-100 km/h: %.2f s, top speed after 20 s: %.1f km/h" % [_t100, car.speed_kmh])

var _brake_start_z := 0.0
var _peak_decel := 0.0
var brake_from := 100.0
var _phase := 0
func _run_brake() -> void:
	if _phase == 0:
		car.ai_input = {"throttle": 1.0, "brake": 0.0, "steer": 0.0, "handbrake": 0.0}
		if car.speed_kmh >= brake_from:
			_phase = 1
			_brake_start_z = car.global_position.z
	elif _phase == 1:
		car.ai_input = {"throttle": 0.0, "brake": 1.0, "steer": 0.0, "handbrake": 0.0}
		_peak_decel = maxf(_peak_decel, car.last_accel_local.z)
		if car.speed_kmh < 1.0:
			finish("%d->0 km/h braking distance: %.1f m (abs=%s) peak decel %.2f g" % [int(brake_from), absf(car.global_position.z - _brake_start_z), str(car.abs_enabled), _peak_decel / 9.81])
	if _t > 40.0:
		finish("timeout")

var _cruise_i := 0.0
func _cruise(target_kmh: float) -> float:
	var err := target_kmh - car.speed_kmh
	_cruise_i = clampf(_cruise_i + err * 0.002, 0.0, 1.0)
	return clampf(err * 0.05 + _cruise_i, 0.0, 1.0)

func _run_corner() -> void:
	var steer := clampf((_t - 8.0) * 0.1, 0.0, 1.0) if _t > 8.0 else 0.0
	car.ai_input = {"throttle": _cruise(90.0), "brake": 0.0, "steer": steer, "handbrake": 0.0}
	if _tick(2) and _t > 8.0:
		_log.append("t=%.1f steer=%.2f v=%.1f lat_g=%.2f yawrate=%.2f slipF=%.1fdeg slipR=%.1fdeg roll=%.1fdeg" % [
			_t, steer, car.speed_kmh, absf(car.last_accel_local.x) / 9.81, car.angular_velocity.y,
			rad_to_deg(_w("FL").slip_angle), rad_to_deg(_w("RL").slip_angle), rad_to_deg(car.global_rotation.z)])
	if _t > 22.0:
		finish("corner test done")

func _run_drift() -> void:
	# 90 km/h, then turn in hard and floor it with traction control off (power oversteer)
	car.tc_enabled = false
	car.abs_enabled = true
	if _t < 6.0:
		car.ai_input = {"throttle": _cruise(90.0), "brake": 0.0, "steer": 0.0, "handbrake": 0.0}
	else:
		var st := 0.0
		if _t < 7.0:
			st = 0.8
		elif _t < 7.6:
			st = 0.25
		else:
			st = 0.25 - clampf(rad_to_deg(car.drift_angle) * 0.02, -0.6, 0.6)   # a simple counter-steer driver
		car.ai_input = {"throttle": 1.0 if _t > 6.6 else 0.3, "brake": 0.0, "steer": st, "handbrake": 0.0}
	if _tick(4) and _t > 5.5:
		_log.append("t=%.2f v=%.1f drift=%.1fdeg yawrate=%.2f slipRL=%.1fdeg rpm=%.0f gear=%d lat_g=%.2f" % [
			_t, car.speed_kmh, rad_to_deg(car.drift_angle), car.angular_velocity.y, rad_to_deg(_w("RL").slip_angle), car.engine_rpm, car.gear, absf(car.last_accel_local.x) / 9.81])
	if _t > 16.0:
		finish("drift test done")

func _run_bumps() -> void:
	car.ai_input = {"throttle": _cruise(40.0), "brake": 0.0, "steer": 0.0, "handbrake": 0.0}
	var m := 0.0
	for w in car.wheels:
		m = maxf(m, absf(car.compression(w.tag)))
	if _tick(5):
		_log.append("t=%.2f z=%.1f v=%.1f maxcomp=%.3f y=%.3f" % [_t, car.global_position.z, car.speed_kmh, m, car.global_position.y])
	if car.global_position.z < -140.0 or _t > 40.0:
		finish("bumps test done")

func _run_crash() -> void:
	car.ai_input = {"throttle": _cruise(100.0), "brake": 0.0, "steer": 0.0, "handbrake": 0.0}
	if _tick(4) and _t > 4.0:
		_log.append("t=%.2f z=%.2f v=%.1f engine=%.2f" % [_t, car.global_position.z, car.speed_kmh, car.engine_health])
	if car.global_position.z < 42.5 and _phase == 0:
		_phase = 1
		_log.append("IMPACT at t=%.2f speed=%.1f km/h" % [_t, car.speed_kmh])
	if _t > 16.0:
		_log.append(car.parts.summary())
		finish("crash test done, car z=%.2f" % car.global_position.z)

func _run_shot() -> void:
	var frame := int(_t * 120.0)
	if frame == 300:
		_snap("chase")
		cam.mode = 3
		cam.orbit_yaw = 0.9
		cam.orbit_pitch = 0.25
		cam.orbit_dist = 7.0
	elif frame == 340:
		_snap("front34")
		cam.orbit_yaw = 3.14 + 0.7
	elif frame == 380:
		_snap("rear34")
		cam.orbit_yaw = 1.57
		cam.orbit_pitch = 0.05
		cam.orbit_dist = 8.0
	elif frame == 420:
		_snap("side")
		car.set_xray(1)
		cam.orbit_yaw = 0.8
		cam.orbit_pitch = 0.6
		cam.orbit_dist = 6.5
	elif frame == 460:
		_snap("xray")
		car.set_xray(0)
		cam.mode = 2
	elif frame == 500:
		_snap("cockpit")
		finish("shots saved")

func _snap(nm: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % nm)

var _impact_t := -1.0
func _run_crashshot() -> void:
	car.ai_input = {"throttle": _cruise(100.0), "brake": 0.0, "steer": 0.0, "handbrake": 0.0}
	if car.global_position.z < 40.3 + car.nose_len and _impact_t < 0.0:
		_impact_t = _t
		cam.mode = 3
	if _impact_t > 0.0:
		var dt_ := _t - _impact_t
		if dt_ > 0.5 and dt_ < 0.52:
			cam.orbit_yaw = PI + 0.5
			cam.orbit_pitch = 0.3
			cam.orbit_dist = 6.0
		if dt_ > 2.0 and dt_ < 2.02:
			_snap("dmg_front")
			cam.orbit_yaw = PI - 0.9
			cam.orbit_pitch = 0.2
		if dt_ > 2.3 and dt_ < 2.32:
			_snap("dmg_front2")
			cam.orbit_yaw = 1.2
			cam.orbit_pitch = 0.5
			cam.orbit_dist = 8.0
		if dt_ > 2.6:
			_snap("dmg_side")
			finish("crash shots saved: " + car.parts.summary())
	if _tick(1):
		_log.append("t=%.1f z=%.1f v=%.1f" % [_t, car.global_position.z, car.speed_kmh])
	if _t > 20.0:
		finish("no impact")

func _run_trackshot() -> void:
	var frame := int(_t * 120.0)
	if frame == 240:
		_snap("track_chase")
		cam.mode = 3
		cam.orbit_yaw = 0.2
		cam.orbit_pitch = 0.15
		cam.orbit_dist = 9.0
	elif frame == 280:
		_snap("track_grid")
		cam.orbit_yaw = 2.2
		cam.orbit_pitch = 0.5
		cam.orbit_dist = 40.0
	elif frame == 320:
		_snap("track_far")
		cam.mode = 4
	elif frame == 360:
		_snap("track_top")
		finish("track shots saved")

# ---------------- automatic driver: follows the centre line, brakes for corners
var _cl := PackedVector3Array()
var _vt := PackedFloat32Array()
var _ci := 0
func _prep_driver() -> void:
	_cl = track.get_centerline()
	var n := _cl.size()
	var curv_v := PackedFloat32Array()
	curv_v.resize(n)
	for i in n:
		var a: Vector3 = _cl[(i - 6 + n) % n]
		var b: Vector3 = _cl[i]
		var c: Vector3 = _cl[(i + 6) % n]
		var ab := a.distance_to(b)
		var bc := b.distance_to(c)
		var ca := c.distance_to(a)
		var area2 := absf((b - a).cross(c - a).y)
		var r := 1e6 if area2 < 1e-3 else (ab * bc * ca) / (2.0 * area2)
		curv_v[i] = minf(sqrt(11.0 * r), 88.0)
	_vt = curv_v.duplicate()
	for pass_i in 2:
		for k in range(n * 2 - 1, -1, -1):
			var i2 := k % n
			var j := (i2 + 1) % n
			var d := _cl[i2].distance_to(_cl[j])
			_vt[i2] = minf(_vt[i2], sqrt(_vt[j] * _vt[j] + 2.0 * 13.0 * d))

func _run_lap() -> void:
	if _cl.is_empty():
		_prep_driver()
		_ci = 0
		best_d = 1e9
	var n := _cl.size()
	var p := car.global_position
	var best := 1e9
	var bi := _ci
	for k in range(-5, 40):
		var idx := (_ci + k + n) % n
		var d := p.distance_to(_cl[idx])
		if d < best:
			best = d
			bi = idx
	_ci = bi
	var v := car.linear_velocity.length()
	var look := int(clampf(10.0 + v * 0.45, 12.0, 60.0) / 2.0)
	var tp: Vector3 = car.global_transform.affine_inverse() * _cl[(_ci + look) % n]
	var alpha := atan2(tp.x, -tp.z)
	var ld := maxf(tp.length(), 4.0)
	var delta := -atan(2.0 * Car.WHEELBASE * sin(alpha) / ld)
	var lock := Car.steer_lock(absf(car.v_fwd))
	var st := clampf(delta / lock, -1.0, 1.0)
	var vt: float = _vt[_ci] * 0.97
	var thr := clampf((vt - v) * 0.35, 0.0, 1.0)
	var brk := clampf((v - vt) * 0.2, 0.0, 1.0)
	car.assist_enabled = false
	car.ai_input = {"throttle": thr, "brake": brk, "steer": st, "handbrake": 0.0}
	if _tick(1):
		_log.append("t=%.0f i=%d v=%.0f vt=%.0f off=%.1f lap=%d now=%.1f best=%.2f gear=%d" % [_t, _ci, v * 3.6, vt * 3.6, best, track.lap_number, track.current_lap_time, track.best_lap_time, car.gear])
	if track.lap_number >= 3 or _t > 260.0:
		_log.append(car.parts.summary())
		finish("lap test done: last=%.2f best=%.2f laps=%d" % [track.last_lap_time, track.best_lap_time, track.lap_number])

var best_d := 0.0

# ---------------- full race with every car (including yours) driven by the AI
var _impact_hooked := false
func _run_race() -> void:
	if not _impact_hooked:
		_impact_hooked = true
		for rc in race.cars:
			var cc: Car = rc
			cc.contact_impulse.connect(func(lp: Vector3, j: float, nrm: Vector3) -> void:
				if j > 2500.0:
					var near := 999.0
					var who := ""
					for o in race.cars:
						if o != cc and o.global_position.distance_to(cc.global_position) < near:
							near = o.global_position.distance_to(cc.global_position)
							who = race.name_of(o)
					_log.append("  HIT t=%.1f %s j=%.0f at local(%.1f,%.1f,%.1f) idx=%d lat=%.1f v=%.0f nearest=%s %.1fm" % [_t, race.name_of(cc), j, lp.x, lp.y, lp.z, race.index_of(cc), race.lateral_of(cc), cc.speed_kmh, who, near]))
	if _tick(1) and int(_t) % 5 == 0:
		var line := "t=%.0f phase=%d " % [_t, race.phase]
		for c in race.standings():
			line += "%s(L%d %.0fkm/h hp%.2f %.0fC lat%.1f) " % [race.name_of(c), race.lap_of(c), c.speed_kmh, c.engine_health, c.engine_temp, race.lateral_of(c)]
		_log.append(line)
	if race.finish_order.size() == race.cars.size() or _t > 420.0:
		for k in race.finish_order.size():
			var c: Car = race.finish_order[k]
			_log.append("P%d %s %.2f s  damage: %s" % [k + 1, race.name_of(c), race.finish_time[c], c.parts.summary().replace("\n", "; ")])
		finish("race done: %d of %d finished" % [race.finish_order.size(), race.cars.size()])

func _run_raceshot() -> void:
	var frame := int(_t * 120.0)
	if frame == 360:
		_snap("race_grid")
	elif frame == 120 * 11:
		_snap("race_start")
	elif frame == 120 * 24:
		_snap("race_chase")
		cam.mode = 3
		cam.orbit_yaw = 2.6
		cam.orbit_pitch = 0.22
		cam.orbit_dist = 11.0
	elif frame == 120 * 24 + 40:
		_snap("race_orbit")
		cam.mode = 2
	elif frame == 120 * 24 + 80:
		_snap("race_cockpit")
		cam.mode = 0
	elif frame == 120 * 40:
		_snap("race_later")
		finish("race shots saved")

# ---------------- offline audio render: rev on the spot, launch, shifts, lift, slide, brake
var _wav := PackedByteArray()
func _run_audio() -> void:
	audio.recording = true
	var thr := 0.0
	var brk := 0.0
	var st := 0.0
	car.tc_enabled = false
	if _t < 3.5:
		car.hold = true
		thr = 0.0 if _t < 1.0 else (1.0 if fmod(_t, 1.0) < 0.45 else 0.0)
	elif _t < 11.0:
		car.hold = false
		thr = 1.0
	elif _t < 13.0:
		thr = 0.0
	elif _t < 18.0:
		thr = 0.75
		st = 0.9 if _t < 16.0 else 0.0
	else:
		brk = 1.0
	car.ai_input = {"throttle": thr, "brake": brk, "steer": st, "handbrake": 0.0}
	var frames := int(EngineAudio.RATE / 120.0 + (1.0 if fmod(_t * 120.0, 4.0) < 1.0 else 0.0))
	var buf := audio.render(frames, 1.0 / 120.0)
	for f in buf:
		var v := clampi(int(f.x * 32000.0), -32768, 32767)
		_wav.append(v & 0xff)
		_wav.append((v >> 8) & 0xff)
	if _tick(4) and _t > 3.5:
		_log.append("t=%.2f gear=%d rpm=%.0f thr=%.2f blip=%.2f pops=%d" % [_t, car.gear, car.engine_rpm, car.throttle, car.blip_t, car.pops])
	if _t > 20.0:
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = int(EngineAudio.RATE)
		w.stereo = false
		w.data = _wav
		w.save_to_wav("res://shots/engine_sample.wav")
		finish("audio saved")

func _run_ai1() -> void:
	if _tick(2):
		var i := race.index_of(car)
		_log.append("t=%.1f i=%d v=%.0f plan=%.0f lat=%.1f line=%.1f drift=%.0f hp=%.2f temp=%.0f gear=%d lap=%d dist_ok" % [_t, i, car.speed_kmh, race.line_speed[i] * 3.6, race.lateral_of(car), race.line_lat[i], rad_to_deg(car.drift_angle), car.engine_health, car.engine_temp, car.gear, race.lap_of(car)])
	if race.finish_order.size() > 0 or _t > 300.0:
		_log.append(car.parts.summary())
		finish("ai1 done finished=%d t=%.1f" % [race.finish_order.size(), race.finish_time.get(car, -1.0)])

func _run_driftshot() -> void:
	_run_drift()
	var frame := int(_t * 120.0)
	if frame == int(10.5 * 120):
		_snap("drift_chase")
		cam.mode = 3
		cam.orbit_yaw = 2.2
		cam.orbit_pitch = 0.3
		cam.orbit_dist = 10.0
	elif frame == int(10.5 * 120) + 30:
		_snap("drift_orbit")
		cam.orbit_yaw = 0.3
		cam.orbit_pitch = 0.9
		cam.orbit_dist = 22.0
	elif frame == int(10.5 * 120) + 60:
		_snap("drift_marks")
		finish("drift shots saved")

func _run_dentshot() -> void:
	var frame := int(_t * 120.0)
	var ai: Car = race.cars[1]
	if frame == 10:
		cam.target = ai
		cam.mode = 3
		cam.orbit_yaw = 1.2
		cam.orbit_pitch = 0.3
		cam.orbit_dist = 7.0
	elif frame == 120:
		_snap("dent_before")
	elif frame == 129:
		for nm in ["Door_FR", "Fender_R", "Body_Sides"]:
			var mi: MeshInstance3D = ai.parts._node(nm)
			if mi == null:
				continue
			for si in mi.mesh.get_surface_count():
				var uv: PackedVector2Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_TEX_UV]
				var mn := Vector2(INF, INF)
				var mx := -mn
				for u in uv:
					mn = mn.min(u)
					mx = mx.max(u)
				_log.append("%s s%d fmt=%d compress=%s uv %s..%s mat=%s" % [nm, si, mi.mesh.surface_get_format(si), str((mi.mesh.surface_get_format(si) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0), mn, mx, mi.mesh.surface_get_material(si).resource_name if mi.mesh.surface_get_material(si) else "-"])
	elif frame == 130:
		ai.parts._apply_hit(Vector3(0.95, 0.7, 0.3), 6000.0, ai.global_transform.basis.x)
		car.parts._apply_hit(Vector3(-0.95, 0.7, 0.3), 6000.0, -car.global_transform.basis.x)
	elif frame == 200:
		for nm in ["Door_FR", "Fender_R", "Body_Sides"]:
			var mi: MeshInstance3D = ai.parts._node(nm)
			if mi == null:
				continue
			for si in mi.mesh.get_surface_count():
				var uv: PackedVector2Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_TEX_UV]
				var mn := Vector2(INF, INF)
				var mx := -mn
				for u in uv:
					mn = mn.min(u)
					mx = mx.max(u)
				_log.append("AFTER %s s%d fmt=%d uv %s..%s override=%s" % [nm, si, mi.mesh.surface_get_format(si), mn, mx, mi.get_surface_override_material(si)])
		_snap("dent_after")
		cam.target = car
	elif frame == 260:
		_snap("dent_after_player")
		finish("dent shots")

var _show: Array[Car] = []
func _run_carsshot() -> void:
	var frame := int(_t * 120.0)
	if frame == 1:
		hud.visible = false
		var cols := [[Color(0.75, 0.05, 0.06), Color(0.95, 0.85, 0.1), Color(0.95, 0.95, 0.95)],
			[Color(0.92, 0.92, 0.94), Color(0.05, 0.35, 0.8), Color(0.08, 0.08, 0.1)],
			[Color(0.05, 0.38, 0.18), Color(0.95, 0.75, 0.1), Color(0.95, 0.95, 0.9)]]
		var ids := ["fastback", "longhood", "midship"]
		for k in 3:
			var c := Car.new()
			c.spec_id = ids[k]
			add_child(c)
			c.set_livery(cols[k][0], cols[k][1], cols[k][2])
			_show.append(c)
		var base: Transform3D = track.get_grid_transform(0)
		var right := base.basis.x
		var all: Array[Car] = [car]
		all.append_array(_show)
		for k in 4:
			var p := base.origin + right * (k * 3.6 - 5.4) - Vector3(0, 0.17, 0)
			all[k].reset_car(p, base.basis.get_euler().y)
	elif frame == 360:
		cam.target = _show[0]
		cam.mode = 3
		cam.orbit_yaw = PI + 0.55
		cam.orbit_pitch = 0.18
		cam.orbit_dist = 15.0
	elif frame == 400:
		_snap("cars_front")
		cam.orbit_yaw = 0.6
	elif frame == 440:
		_snap("cars_rear")
		cam.orbit_yaw = PI * 0.5
		cam.orbit_pitch = 0.05
		cam.orbit_dist = 17.0
	elif frame == 480:
		_snap("cars_side")
		finish("cars shots")

func _menushot() -> void:
	## drives the menus like a player would and saves what each screen looks like
	var w := func(t: float) -> void:
		await get_tree().create_timer(t, true).timeout
	await w.call(1.5)
	_snap("menu_main")
	menu._step_car(1)
	menu._set_mode(true)
	menu._step_laps(-1)
	await w.call(0.8)
	_snap("menu_choices")
	menu._show_setup(true)
	menu._step_setup("downforce", 2)
	await w.call(0.5)
	_snap("menu_setup")
	menu._show_setup(false)
	menu._show_sound(true)
	menu._step_sound("opponents", -2)
	await w.call(0.4)
	_snap("menu_sound")
	_log.append("sound: master %.1f player %.1f opponents %.1f, bus Opponents %.1f dB, Player bus of engine: %s" % [SoundSettings.master, SoundSettings.player, SoundSettings.opponents, AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Opponents")), audio.player.bus])
	menu._step_sound("opponents", 2)
	menu._show_sound(false)
	_log.append("menu: car=%s arcade=%s laps=%d opponents=%d" % [menu.car_id, str(menu.arcade), menu.laps, menu.opponents])
	start_race(menu._settings("race"))
	await w.call(4.0)
	_snap("menu_racing")
	_log.append("racing: paused=%s car=%s arcade=%s laps=%d field=%d phase=%d" % [str(get_tree().paused), car.spec_id, str(CarSpecs.arcade), race.laps, race.cars.size(), race.phase])
	_pause()
	await w.call(0.5)
	_snap("menu_pause")
	_log.append("paused: %s" % str(get_tree().paused))
	restart_race()
	await w.call(1.0)
	_log.append("restarted: paused=%s phase=%d" % [str(get_tree().paused), race.phase])
	open_main_menu()
	await w.call(0.5)
	start_race({"arcade": false, "car": "midship", "laps": 0, "opponents": 0})
	await w.call(1.0)
	_log.append("practice: car=%s laps=%d field=%d" % [car.spec_id, race.laps, race.cars.size()])
	finish("menu shots")

func _run_hillshot() -> void:
	## views of the elevation: placed at points round the lap, looking along the road
	var frame := int(_t * 120.0)
	var cl: PackedVector3Array = track.get_centerline()
	var shots := [[560, "hill_sweeper"], [690, "hill_crest"], [930, "hill_downhill"], [1360, "hill_backstraight"]]
	for k in shots.size():
		if frame == 60 + 90 * k:
			var i: int = shots[k][0]
			var p: Vector3 = cl[i]
			var ahead: Vector3 = cl[(i + 25) % cl.size()]
			car.reset_car(p + Vector3(0, 0.4, 0), atan2(-(ahead - p).x, -(ahead - p).z))
			cam.mode = 0
			cam._initialised = false
		elif frame == 60 + 90 * k + 80:
			_snap(shots[k][1])
	if frame > 60 + 90 * shots.size():
		finish("hill shots")

func _run_terraincheck() -> void:
	## how far the ground rises above the road surface beside the track (should stay <= 0)
	var cl: PackedVector3Array = track.get_centerline()
	var rv: PackedVector3Array = track.get_right_vectors()
	var worst := {}
	for lat in [8.5, 10.0, 12.0, 16.0, 22.0, 30.0]:
		var mx := -99.0
		var at := 0
		for i in cl.size():
			for side in [-1.0, 1.0]:
				var p: Vector3 = cl[i] + rv[i] * lat * side
				var dh: float = track.terrain_height(p.x, p.z) - cl[i].y
				if dh > mx:
					mx = dh
					at = i
		_log.append("lat %.1f: worst ground above road %.2f m at idx %d" % [lat, mx, at])
	var low := 99.0
	var under := -99.0
	for i in cl.size():
		low = minf(low, cl[i].y)
		under = maxf(under, track.terrain_height(cl[i].x, cl[i].z) - cl[i].y)
	_log.append("lowest road point y=%.3f (ground plane at -0.4); worst ground above road centre %.2f m" % [low, under])
	finish("terrain check")

# ---------------- pit stop: drive down the pit lane, stop in the box, get serviced
var _pit_phase := 0
func _run_pittest() -> void:
	if _pit_phase == 0:
		CarSetup.wear_and_fuel = true
		race.laps = 3
		race.set_field(0)
		race.restart()
		_pit_phase = 1
	if race.phase < RaceManager.Phase.GREEN:
		return
	if _pit_phase == 1:
		for w in car.wheels:
			w.wear = 0.7
		car.fuel = 2.0
		# into the lane, heading for the box
		car.reset_car(Vector3(RaceTrack.PIT_X0 + 30.0, 0.3, RaceTrack.PIT_BOX.z), -PI * 0.5 if not RaceTrack.reversed else PI * 0.5)
		_pit_phase = 2
		_log.append("in lane: fuel %.1f wear %.2f" % [car.fuel, car.wheels[0].wear])
	elif _pit_phase == 2:
		var to_box := RaceTrack.PIT_BOX.x - car.global_position.x
		var v := car.v_fwd
		var want := clampf(absf(to_box) * 0.35, 0.0, 14.0)
		car.ai_input = {"throttle": clampf((want - v) * 0.4, 0.0, 1.0), "brake": clampf((v - want) * 0.5, 0.0, 1.0) if absf(to_box) > 0.3 else 1.0,
			"steer": clampf((car.global_position.z - RaceTrack.PIT_BOX.z) * 0.3, -1.0, 1.0), "handbrake": 0.0}
		if _tick(2):
			_log.append("t=%.1f x=%.1f z=%.1f v=%.1f cap=%.1f in_box=%s pit=%.1f" % [_t, car.global_position.x, car.global_position.z, v * 3.6, car.speed_cap * 3.6, str(track.in_pit_box(car.global_position)), race.pit_time_left])
		if race.pit_time_left > 0.0:
			_pit_phase = 3
			_log.append("SERVICE STARTED, %.1f s" % race.pit_time_left)
		if _t > 90.0:
			finish("never stopped in the box")
	elif _pit_phase == 3:
		car.ai_input = {"throttle": 0.0, "brake": 1.0, "steer": 0.0, "handbrake": 0.0}
		if race.pit_time_left <= 0.0:
			finish("pit stop done: fuel %.1f kg, wear %.2f, hold=%s, notice='%s'" % [car.fuel, car.wheels[0].wear, str(car.hold), race.notice])

# ---------------- championship: your car (AI driven) through all four rounds
var _champ_started := false
var _champ_round_seen := -1
func _run_champtest() -> void:
	if not _champ_started:
		_champ_started = true
		process_mode = Node.PROCESS_MODE_ALWAYS          # keep testing while the results menu pauses the game
		menu = GameMenu.new()
		menu.main = self
		add_child(menu)
		menu.visible = false
		race.car_finished.connect(_on_car_finished)
		start_race({"kind": "championship", "arcade": true, "car": car.spec_id, "laps": 1, "opponents": 5, "time": "day", "rain": false})
		get_tree().paused = false
	if get_tree().paused and menu.visible:
		# results panel is up: log, then next round
		if _champ_round_seen != Championship.round_index:
			_champ_round_seen = Championship.round_index
			_log.append("after round %d (%s, rain=%s): %s" % [Championship.round_index + 1, Weather.time_of_day, str(Weather.rain), str(Championship.table())])
			if Championship.round_index >= Championship.ROUNDS.size() - 1:
				next_round()
				_log.append(results_text(true).replace("
", " | "))
				finish("championship done")
				return
			next_round()
	if _t > 1500.0:
		finish("timeout")

# ---------------- time trial: three laps, the best becomes the ghost
func _run_tttest() -> void:
	if _t < 0.02:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ghost._key()))
		kind = "timetrial"
		race.laps = 0
		race.set_field(0)
		race.restart()
		_begin_session()
	if _tick(1) and int(_t) % 10 == 0:
		_log.append("t=%.0f lap=%d now=%.1f best=%.2f ghost_samples=%d delta=%s" % [_t, track.lap_number, track.current_lap_time, ghost.best_time, ghost.best.size() / GhostLap.STRIDE, ("%+.2f" % ghost.delta) if ghost.has_delta else "-"])
	if track.lap_number >= 4 or _t > 420.0:
		finish("time trial: best %.2f, saved=%s" % [ghost.best_time, str(FileAccess.file_exists(ghost._key()))])

# ---------------- replay: race a bit, then watch it from the TV cameras
func _run_replayshot() -> void:
	var frame := int(_t * 120.0)
	if frame == 2:
		race.laps = 1
		race.restart()
		_begin_session()
	if frame == 120 * 40:
		hud.visible = false
		replay.play()
		replay._t = 30.0 * 24.0
	elif frame == 120 * 40 + 60:
		_snap("replay_tv1")
		replay._t = 30.0 * 28.0
	elif frame == 120 * 40 + 120:
		_snap("replay_tv2")
		replay._focus = 2
		replay._t = 30.0 * 20.0
	elif frame == 120 * 40 + 180:
		_snap("replay_tv3")
		finish("replay frames=%d" % replay._frames)

func _run_startshot() -> void:
	## the opening of the lap, every 2.5 s from just before the lights go out
	var frame := int(_t * 120.0)
	if frame == 1:
		hud.visible = true
	if frame >= 120 * 5 and frame % 300 == 0 and frame <= 120 * 40:
		_snap("start_%02d" % (frame / 120))
		_log.append("t=%d x=%.0f z=%.0f y=%.2f idx=%d" % [frame / 120, car.global_position.x, car.global_position.z, car.global_position.y, race.index_of(car)])
	if frame > 120 * 40:
		finish("start shots")

# ---------------- off the road and back on: angles, speeds, both sides; nothing may launch the car
var _ot_case := -1
var _ot_t := 0.0
var _ot_y0 := 0.0
var _ot_max := 0.0
var _ot_spin := 0.0
var _ot_lat_max := 0.0
var _ot_lat0 := 0.0
var _ot_tpk := 0.0
const OT_CASES := [[10.0, 15.0], [25.0, 15.0], [45.0, 15.0], [10.0, 25.0], [25.0, 25.0], [45.0, 25.0], [10.0, 35.0], [25.0, 35.0]]
func _run_offtrack() -> void:
	var cl: PackedVector3Array = track.get_centerline()
	var rv: PackedVector3Array = track.get_right_vectors()
	_ot_t += 1.0 / 120.0
	if _ot_case < 0 or _ot_t > 4.0:
		if _ot_case >= 0:
			_log.append("angle %2d deg %3d km/h side %+d: max height above road %.2f m, max spin %.1f rad/s  lat at peak %.1f (start %.1f, end %.1f) t_peak %.2f%s" % [
				int(OT_CASES[_ot_case % OT_CASES.size()][0]), int(OT_CASES[_ot_case % OT_CASES.size()][1] * 3.6),
				1 if _ot_case < OT_CASES.size() else -1, _ot_max, _ot_spin, _ot_lat_max, _ot_lat0, race.lateral_of(car), _ot_tpk, "   <-- LAUNCH" if _ot_max > 1.0 else ""])
		_ot_case += 1
		if _ot_case >= OT_CASES.size() * 2:
			finish("offtrack done")
			return
		var c: Array = OT_CASES[_ot_case % OT_CASES.size()]
		var side := 1.0 if _ot_case < OT_CASES.size() else -1.0
		var i := 1250 if not RaceTrack.reversed else cl.size() - 1250
		var fwd := (cl[i + 2] - cl[i - 2]).normalized()
		var p: Vector3 = cl[i - 40] + rv[i - 40] * side * 13.0
		p.y = track.terrain_height(p.x, p.z) + 0.6
		var dir := fwd.rotated(Vector3.UP, side * deg_to_rad(c[0]))
		car.reset_car(p, atan2(-dir.x, -dir.z))
		car.linear_velocity = dir * c[1]
		for w in car.wheels:
			w.omega = c[1] / Car.WHEEL_R
		car.parts.repair()
		car.reset_crush()
		_ot_t = 0.0
		_ot_max = 0.0
		_ot_spin = 0.0
		_ot_lat0 = side * 13.0
	var i2 := race.index_of(car) if race != null else 0
	var road_y := cl[i2].y
	if _ot_t > 0.3:
		if car.global_position.y - road_y > _ot_max:
			_ot_max = car.global_position.y - road_y
			_ot_lat_max = race.lateral_of(car)
			_ot_tpk = _ot_t
		_ot_spin = maxf(_ot_spin, car.angular_velocity.length())
	car.ai_input = {"throttle": 0.4, "brake": 0.0, "steer": 0.0, "handbrake": 0.0}

func _run_rearshot() -> void:
	## close-ups of the rear of every car (diffuser, exhaust, wing, lights)
	var frame := int(_t * 120.0)
	var ids := CarSpecs.ORDER
	var k := frame / 90
	if frame % 90 == 1 and k < ids.size():
		if ids[k] != car.spec_id:
			_swap_player(ids[k])
		hud.visible = false
		cam.mode = 3
		var bz := car.global_transform.basis.z
		cam.orbit_yaw = atan2(bz.x, bz.z) + 0.55
		cam.orbit_pitch = 0.12
		cam.orbit_dist = 5.0
	elif frame % 90 == 60 and k < ids.size():
		_snap("rear_" + ids[k])
		var bz2 := car.global_transform.basis.z
		cam.orbit_yaw = atan2(bz2.x, bz2.z) + 0.12
		cam.orbit_pitch = -0.02
		cam.orbit_dist = 3.6
	elif frame % 90 == 85 and k < ids.size():
		_snap("rear_low_" + ids[k])
	if k >= ids.size():
		finish("rear shots")

# ---------------- trailer: one scene per run, recorded with --write-movie (see tools/make_trailer.sh)
var clip := ""
var _cap: Label
var _cap_sub: Label
var _cap_t := -1.0
const CLIPS := {
	# clip: [start of the part that is kept, end, caption, sub caption]
	"start": [3.0, 15.0, "LIGHTS OUT", "Six cars, five red lights, one launch"],
	"pack": [22.0, 31.0, "WHEEL TO WHEEL", "AI rivals with their own personalities and slipstream"],
	"rain": [20.0, 28.0, "RAIN", "Less grip, spray and a wet, mirrored track"],
	"night": [24.0, 33.0, "NIGHT RACING", "Floodlights, headlights, exhaust flames, glowing brakes"],
	"cockpit": [14.0, 21.0, "FROM THE DRIVER'S SEAT", "Chase, bonnet and cockpit cameras"],
	"cars": [0.5, 12.5, "FOUR CARS", "Front V8, flat-6, big V8, twin-turbo V6"],
	"drift": [5.5, 12.0, "PHYSICS", "Tyre model, weight transfer, real slides"],
	"crash": [0.0, 99.0, "DAMAGE", "Dents, broken parts, leaks and fires"],
	"replay": [40.0, 48.0, "REPLAYS", "TV cameras with depth of field"],
	# short action trailer: no captions in the game (titles are added when cutting)
	"q_start": [0.0, 11.0, "", ""],
	"q_low": [0.0, 24.0, "", ""],
	"q_flyby": [0.0, 26.0, "", ""],
	"q_side": [0.0, 24.0, "", ""],
	"q_cockpit": [0.0, 21.0, "", ""],
	"q_rain": [0.0, 25.0, "", ""],
	"q_night": [0.0, 32.0, "", ""],
	"q_wreck": [0.0, 99.0, "", ""],
	"q_drift": [0.0, 12.0, "", ""],
	"q_replay": [0.0, 47.0, "", ""],
	"q_cars": [0.0, 12.2, "", ""],
}
var _fly_pos := Vector3.ZERO
var _pile_max := 0.0
var _wreck_t := -1.0
var _wreck_p0 := Vector3.ZERO
const CAR_NAMES := {"gt": "Cutlass 442 - front V8", "fastback": "Kiri Turbo - turbo four",
	"longhood": "Phoenix 455 - big V8", "midship": "Saba V12 - mid-engined V12"}

func _trailer_setup() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var box := VBoxContainer.new()
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 70.0
	box.offset_top = -250.0
	box.offset_bottom = -60.0
	box.offset_right = 1500.0
	layer.add_child(box)
	_cap = Label.new()
	_cap.add_theme_font_size_override("font_size", 84)
	_cap.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_cap.add_theme_constant_override("shadow_offset_x", 3)
	_cap.add_theme_constant_override("shadow_offset_y", 3)
	box.add_child(_cap)
	_cap_sub = Label.new()
	_cap_sub.add_theme_font_size_override("font_size", 42)
	_cap_sub.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	_cap_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_cap_sub.add_theme_constant_override("shadow_offset_x", 2)
	_cap_sub.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(_cap_sub)
	_cap.modulate.a = 0.0
	_cap_sub.modulate.a = 0.0
	hud.visible = clip == "start" or clip == "q_start"
	if clip == "cockpit":
		hud.visible = false
	if clip.begins_with("q_"):
		hud.label.visible = false
		hud.dmg_label.visible = false

func _caption(text: String, sub: String) -> void:
	_cap.text = text
	_cap_sub.text = sub
	_cap_t = 0.0

func _orbit_car(c: Car, off_yaw: float, pitch: float, dist: float) -> void:
	## camera orbit fixed relative to the car's heading (0 = straight behind)
	var bz := c.global_transform.basis.z
	cam.target = c
	cam.mode = 3
	cam.orbit_yaw = atan2(bz.x, bz.z) + off_yaw
	cam.orbit_pitch = pitch
	cam.orbit_dist = dist

func _run_trailer() -> void:
	var c: Array = CLIPS[clip]
	var t0: float = c[0]
	var t1: float = c[1]
	var u := _t - t0                           # time into the kept part
	if _cap_t >= 0.0:
		_cap_t += 1.0 / 120.0
		var a := clampf(_cap_t / 0.4, 0.0, 1.0) * clampf((3.6 - _cap_t) / 0.5, 0.0, 1.0)
		_cap.modulate.a = a
		_cap_sub.modulate.a = a
	var fr := int(round(_t * 120.0))
	if fr == int(round((t0 + 0.6) * 120.0)) and clip != "cars" and clip != "crash" and not clip.begins_with("q_"):
		_caption(c[2], c[3])
	if clip.begins_with("q_") and race != null and fr > 240:
		for c2: Car in race.cars:
			_pile_max = maxf(_pile_max, c2.global_position.y - race.center[race.index_of(c2)].y)
		if fr % 600 == 0:
			_log.append("t=%d highest car above the road so far: %.2f m" % [fr / 120, _pile_max])
	match clip:
		"q_start":
			cam.mode = 0
		"q_low":
			if _t > 11.0:
				_orbit_car(car, PI - 0.55 + sin(_t * 0.4) * 0.15, 0.03, 5.2)
		"q_side":
			if _t > 11.0:
				_orbit_car(car, PI * 0.5 + 0.25, 0.06, 4.6)
		"q_cockpit":
			if _t > 11.0:
				cam.mode = 2
		"q_rain":
			if _t > 11.0:
				_orbit_car(car, 0.28, 0.05, 6.0)
		"q_night":
			if _t > 11.0:
				_orbit_car(car, 0.42, 0.07, 4.6)
		"q_flyby":
			# a fixed long lens beside the track, about 90 m ahead; the pack rushes past it
			if fr == int(17.0 * 120.0):
				var i0 := race.index_of(car)
				var i1 := (i0 + int(90.0 / race.ds)) % race.n
				var side := 1.0 if race.lateral_of(car) < 0.0 else -1.0
				_fly_pos = race.center[i1] + race.right[i1] * side * 8.5 + Vector3(0, 0.9, 0)
				cam.mode = 6
				cam.fov = 30.0
			if fr >= int(17.0 * 120.0):
				cam.global_position = _fly_pos
				cam.look_at(car.global_position + Vector3(0, 0.6, 0), Vector3.UP)
		"q_cars":
			var kq := fr / 180
			var ids_q := CarSpecs.ORDER
			if kq < ids_q.size() * 2:
				var idq: String = ids_q[kq % ids_q.size()]
				if fr % 180 == 1:
					if idq != car.spec_id:
						_swap_player(idq)
					var dq: Array = RaceManager.DRIVERS[[4, 1, 0, 5][kq % 4]]
					car.set_livery(dq[1], dq[2], dq[3], dq[4], dq[5])
					car.set_race_number(dq[6])
					hud.visible = false
				var fq := float(fr % 180) / 120.0
				var base_yaw: float = [PI - 0.7, 0.6, PI + 0.9, -0.5][kq % 4]
				_orbit_car(car, base_yaw + fq * 0.6, 0.04 + 0.1 * float(kq % 2), 4.6 + 0.6 * float(kq % 3))
		"q_drift":
			_run_drift()
			if _t > 6.0:
				_orbit_car(car, 1.7 - (_t - 6.0) * 0.3, 0.06, 6.5)
			return
		"q_replay":
			if fr == 2:
				race.laps = 1
				race.restart()
				_begin_session()
			if fr == int(38.0 * 120.0):
				hud.visible = false
				replay.play()
				replay._t = 30.0 * 13.0
		"q_wreck":
			_run_wreck(fr)
			return
		"start":
			cam.mode = 0
		"pack":
			if u >= 0.0:
				_orbit_car(car, 2.6 - u * 0.12, 0.10 + u * 0.01, 7.5)
		"rain":
			if u >= 0.0 and u < 4.5:
				_orbit_car(car, 0.35 + u * 0.05, 0.08, 8.0)
			elif u >= 4.5:
				cam.target = car
				cam.mode = 0
		"night":
			if u >= 0.0 and u < 5.0:
				_orbit_car(car, 0.55 - u * 0.08, 0.12, 6.5)
			elif u >= 5.0:
				cam.target = car
				cam.mode = 0
		"cockpit":
			if u >= 0.0 and u < 4.5:
				cam.mode = 2
			elif u >= 4.5:
				cam.mode = 1
		"cars":
			var k := fr / 360
			var f := float(fr % 360) / 120.0
			var ids := CarSpecs.ORDER
			if k < ids.size():
				if fr % 360 == 1:
					if ids[k] != car.spec_id:
						_swap_player(ids[k])
					var d: Array = RaceManager.DRIVERS[[4, 1, 0, 5][k]]
					car.set_livery(d[1], d[2], d[3], d[4], d[5])
					car.set_race_number(d[6])
					hud.visible = false
				if fr % 360 == 60:
					_caption("FOUR CARS" if k == 0 else "", CAR_NAMES[ids[k]])
				_orbit_car(car, PI + (-1.25 + f * 0.45) * (1.0 if k % 2 == 0 else -1.0), 0.08 + f * 0.02, 5.4)
		"drift":
			_run_drift()
			if u >= 0.0:
				_orbit_car(car, 1.9 - u * 0.25, 0.25, 9.0)
			return
		"crash":
			car.ai_input = {"throttle": _cruise(100.0), "brake": 0.0, "steer": 0.0, "handbrake": 0.0}
			if fr == 1:
				_orbit_car(car, 0.9, 0.15, 9.0)
				_caption(c[2], c[3])
			elif car.global_position.z < 40.3 + car.nose_len and _impact_t < 0.0:
				_impact_t = _t
			if _impact_t < 0.0:
				_orbit_car(car, 0.9 + _t * 0.08, 0.15, 9.0)
			else:
				var d := _t - _impact_t
				cam.mode = 3
				cam.orbit_yaw = PI + 0.5 - d * 0.35
				cam.orbit_pitch = 0.25
				cam.orbit_dist = 6.5 + d
				if d > 3.5:
					_log.append("impact at %.2f s" % _impact_t)
					finish("trailer clip crash")
			if _t > 20.0:
				finish("no impact")
			return
		"replay":
			var frame := int(_t * 120.0)
			if frame == 2:
				race.laps = 1
				race.restart()
				_begin_session()
			if frame == int(t0 * 120.0) - 1:
				hud.visible = false
				replay.play()
				replay._t = 30.0 * 12.0
	if fr == 200:
		_log.append("caption rect %s" % str(_cap.get_global_rect()))
	if _t > t1:
		if clip.begins_with("q_"):
			_log.append("highest car above the road: %.2f m" % _pile_max)
		finish("trailer clip %s" % clip)

var _ct_other: Car
var _ct_case := -1
var _ct_t := 0.0
var _ct_max := [0.0, 0.0]
var _ct_spin := [0.0, 0.0]
var _ct_worst := ""
const CT_CASES := ["side swipe 110 km/h", "rear end 130 vs 40 km/h", "T-bone 90 km/h", "side swipe 160 km/h", "nose to door 60 km/h",
	"over a loose bumper 100 km/h", "over a loose bumper 160 km/h", "T-bone 150 km/h", "nose to door 120 km/h", "T-bone 200 km/h"]
var _ct_debris: RigidBody3D
var _ct_jmax := 0.0
func _run_contacttest() -> void:
	## two cars hit each other in different ways; neither may be thrown into the air
	Car.debug_contacts = true
	var dt := 1.0 / 120.0
	_ct_t += dt
	if _ct_other == null:
		_ct_other = Car.new()
		_ct_other.name = "Other"
		_ct_other.spec_id = "midship"
		add_child(_ct_other)
	if _ct_case < 0 or _ct_t > 4.0:
		if _ct_case >= 0:
			_log.append("%-30s you: max height %.2f m spin %.1f   other: max height %.2f m spin %.1f   biggest hit %.0f N s%s" % [CT_CASES[_ct_case], _ct_max[0], _ct_spin[0], _ct_max[1], _ct_spin[1], _ct_jmax, "   <-- LAUNCH" if maxf(_ct_max[0], _ct_max[1]) > 1.2 else ""])
			if _ct_worst != "":
				_log.append("    worst moment: " + _ct_worst)
			_log.append("    parts off: you %s / other %s" % [str(car.parts.gone.keys()), str(_ct_other.parts.gone.keys())])
		_ct_case += 1
		if _ct_case >= CT_CASES.size():
			finish("contact test done")
			return
		for c: Car in [car, _ct_other]:
			c.parts.repair()
			c.reset_crush()
			c.mass = c.mass_kg
		var base := Vector3(100, 0.5, 300)
		_ct_t = 0.0
		_ct_max = [0.0, 0.0]
		_ct_spin = [0.0, 0.0]
		_ct_worst = ""
		_ct_jmax = 0.0
		if _ct_debris != null:
			_ct_debris.queue_free()
			_ct_debris = null
		match _ct_case:
			0, 3:
				var v := 30.5 if _ct_case == 0 else 44.0
				car.reset_car(base, 0.0)
				_ct_other.reset_car(base + Vector3(2.6, 0, 0), 0.0)
				car.linear_velocity = Vector3(0, 0, -v)
				_ct_other.linear_velocity = Vector3(0, 0, -v)
			1:
				car.reset_car(base, 0.0)
				_ct_other.reset_car(base + Vector3(0, 0, -25), 0.0)
				car.linear_velocity = Vector3(0, 0, -36.0)
				_ct_other.linear_velocity = Vector3(0, 0, -11.0)
			2:
				car.reset_car(base, 0.0)
				_ct_other.reset_car(base + Vector3(0, 0, -30), PI * 0.5)
				car.linear_velocity = Vector3(0, 0, -25.0)
			4:
				car.reset_car(base, 0.0)
				_ct_other.reset_car(base + Vector3(-1.2, 0, -14), PI * 0.5)
				car.linear_velocity = Vector3(0, 0, -16.7)
			7, 9:
				car.reset_car(base, 0.0)
				_ct_other.reset_car(base + Vector3(0, 0, -30), PI * 0.5)
				car.linear_velocity = Vector3(0, 0, -41.7 if _ct_case == 7 else -55.6)
			8:
				car.reset_car(base, 0.0)
				_ct_other.reset_car(base + Vector3(-1.2, 0, -20), PI * 0.5)
				car.linear_velocity = Vector3(0, 0, -33.3)
			5, 6:
				# a broken-off bumper lying across the road, as the damage model drops it
				car.reset_car(base, 0.0)
				_ct_other.reset_car(base + Vector3(30, 0, 0), 0.0)
				car.linear_velocity = Vector3(0, 0, -(27.8 if _ct_case == 5 else 44.4))
				_ct_debris = RigidBody3D.new()
				_ct_debris.name = "Loose_Bumper_F"
				_ct_debris.mass = 7.0
				_ct_debris.collision_layer = 4
				_ct_debris.collision_mask = 1 | 2 | 4
				var cs := CollisionShape3D.new()
				var bx := BoxShape3D.new()
				bx.size = Vector3(1.7, 0.32, 0.35)
				cs.shape = bx
				_ct_debris.add_child(cs)
				add_child(_ct_debris)
				_ct_debris.global_position = base + Vector3(0.0, -0.3, -30.0)
		for c: Car in [car, _ct_other]:
			for w in c.wheels:
				w.omega = -c.linear_velocity.z / Car.WHEEL_R if c.linear_velocity.length() > 0.1 else 0.0
	var steer := -0.25 if (_ct_case == 0 or _ct_case == 3) and _ct_t > 0.4 and _ct_t < 1.6 else 0.0
	car.ai_input = {"throttle": 0.5 if _ct_t < 1.5 else 0.0, "brake": 0.0 if _ct_t < 1.5 else 0.5, "steer": steer, "handbrake": 0.0}
	_ct_other.ai_input = {"throttle": 0.3 if _ct_case != 2 and _ct_case != 4 else 0.0, "brake": 0.0, "steer": 0.0, "handbrake": 0.0}
	for c: Car in [car, _ct_other]:
		for line: String in c.dbg_contacts:
			var j := float(line.split(" j")[1].split(" ")[0])
			_ct_jmax = maxf(_ct_jmax, j)
	var k := 0
	for c: Car in [car, _ct_other]:
		var h := c.global_position.y - 0.0
		if h > _ct_max[k]:
			_ct_max[k] = h
			if h > 0.6 and _ct_worst == "":
				_ct_worst = "t=%.2f %s h=%.2f vy=%.1f av=%s contacts: %s" % [_ct_t, "you" if k == 0 else "other", h, c.linear_velocity.y, str(c.angular_velocity.snapped(Vector3(0.1, 0.1, 0.1))), " | ".join(c.dbg_contacts)]
		_ct_spin[k] = maxf(_ct_spin[k], c.angular_velocity.length())
		k += 1

func _run_fliptest() -> void:
	## roll the car onto its roof: the turn-over button must appear and put it back on its wheels
	var frame := int(_t * 120.0)
	if frame == 2:
		hud.visible = true
		car.global_transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.97), car.global_position + Vector3(0, 1.5, 0))
	elif frame == 120 * 3:
		_log.append("upside down: flipped=%s button=%s up.y=%.2f" % [str(car.is_flipped()), str(hud.flip_btn.visible), car.global_transform.basis.y.y])
		_snap("flip_button")
		hud.flip_btn.pressed.emit()
	elif frame == 120 * 5:
		_log.append("after button: flipped=%s button=%s up.y=%.2f height %.2f" % [str(car.is_flipped()), str(hud.flip_btn.visible), car.global_transform.basis.y.y, car.global_position.y])
		_snap("flip_after")
		finish("flip test done")

func _run_wreck(fr: int) -> void:
	## flat out into the barrier on the circuit, seen from a trackside camera, in slow motion
	var cl: PackedVector3Array = track.get_centerline()
	var rv: PackedVector3Array = track.get_right_vectors()
	var i := 1250
	if fr == 1:
		var drv := car.get_node_or_null("Driver")
		if drv != null:
			drv.queue_free()
		var fwd := (cl[i + 2] - cl[i - 2]).normalized()
		var p0: Vector3 = cl[i - 15] + rv[i - 15] * 4.0
		p0.y = track.terrain_height(p0.x, p0.z) + 0.5
		var dir := fwd.rotated(Vector3.UP, deg_to_rad(24.0))
		car.reset_car(p0, atan2(-dir.x, -dir.z))
		_wreck_p0 = p0
		car.linear_velocity = dir * 44.0
		for w in car.wheels:
			w.omega = 44.0 / Car.WHEEL_R
		var hit := p0 + dir * 40.0
		_fly_pos = hit + fwd * 13.0 + rv[i] * 4.0 + Vector3(0, 1.1, 0)
		cam.mode = 6
		cam.fov = 42.0
		hud.visible = false
	if fr > 1:
		cam.global_position = _fly_pos
		cam.look_at(car.global_position + Vector3(0, 0.5, 0), Vector3.UP)
	car.hold = false
	car.ai_input = {"throttle": 0.8 if _wreck_t < 0.0 else 0.0, "brake": 0.0 if _wreck_t < 0.0 else 0.6, "steer": 0.0, "handbrake": 0.0}
	if _wreck_t < 0.0 and fr > 10 and car.global_position.distance_to(_wreck_p0) > 32.0:
		_wreck_t = _t
		Engine.time_scale = 0.3
	if _wreck_t > 0.0 and _t - _wreck_t > 1.7:
		Engine.time_scale = 1.0
	if _wreck_t > 0.0 and _t - _wreck_t > 3.2:
		_log.append("wreck at %.2f, damage: %s" % [_wreck_t, car.parts.summary()])
		finish("trailer clip q_wreck")
	if _t > 12.0:
		finish("no wreck")

func _run_frontshot() -> void:
	## the front of every car (3/4 and low), then the cockpit view while driving
	var frame := int(_t * 120.0)
	var ids := CarSpecs.ORDER
	var k := frame / 120
	if k < ids.size():
		var f := frame % 120
		if f == 1:
			if ids[k] != car.spec_id:
				_swap_player(ids[k])
			hud.visible = false
			cam.mode = 3
			var fz := -car.global_transform.basis.z
			cam.orbit_yaw = atan2(fz.x, fz.z) - 0.6
			cam.orbit_pitch = 0.25
			cam.orbit_dist = 5.0
		elif f == 50:
			_snap("front_" + ids[k])
			var fz2 := -car.global_transform.basis.z
			cam.orbit_yaw = atan2(fz2.x, fz2.z) + 0.1
			cam.orbit_pitch = 0.06
			cam.orbit_dist = 3.8
		elif f == 85:
			_snap("front_low_" + ids[k])
			cam.mode = 2
		elif f == 115:
			_snap("cockpit_" + ids[k])
			var sw := car.model.find_child("SteeringWheel", true, false) as Node3D
			if sw != null:
				_log.append("%s wheel at %s (car local) visible %s eye %s" % [ids[k], str(car.to_local(sw.global_position)), str(sw.is_visible_in_tree()), str(car.cockpit_eye)])
	else:
		finish("front shots")
