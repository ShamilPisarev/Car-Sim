class_name GameMenu
extends CanvasLayer
## Main menu (mode, car, laps, opponents, start / practice / quit) and the pause menu
## (resume, restart, settings, quit). Runs while the game is paused. Works with mouse,
## keyboard (arrows + Enter) and gamepad (d-pad + A).

const ACCENT := Color(1.0, 0.82, 0.2)
const LAP_CHOICES := [1, 2, 3, 5, 10]
const MODE_TEXT := {
	"realistic": "Real grip and full damage. A hard hit can hole the radiator, break the suspension or tear a wheel off.",
	"arcade": "Forgiving: a tenth of the damage, no engine failures, stability control, +15 % grip and brakes, +8 % power.",
}

var main: Node                   # main.gd (duck-typed: start_race, resume_game, restart_race, cam)
var arcade := false
var car_id := "gt"
var laps := 3
var opponents := 5
static var saved := {}           # laps / opponents survive a layout change (scene reload)
var time_of_day := "day"
var rain := false
var finished := false            # the pause menu is showing race results

var _root: Control
var _main_panel: Control
var _pause_panel: Control
var _mode_btns: Array[Button] = []
var _mode_desc: Label
var _car_name: Label
var _car_desc: Label
var _laps_lbl: Label
var _opp_lbl: Label
var _time_lbl: Label
var _rain_lbl: Label
var _line_lbl: Label
var _track_lbl: Label
var _wear_lbl: Label
var _best_lbl: Label
var _info: Label
var _replay_btn: Button
var _next_btn: Button
var _start_btn: Button
var _pause_title: Label
var _resume_btn: Button
var _restart_btn: Button

func _ready() -> void:
	laps = saved.get("laps", laps)
	opponents = saved.get("opponents", opponents)
	time_of_day = Weather.time_of_day
	rain = Weather.rain
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_main_panel = _build_main()
	_pause_panel = _build_pause()
	_refresh()

# ------------------------------------------------------------------ public
func show_main() -> void:
	visible = true
	_setup_panel.visible = false
	_main_panel.visible = true
	_pause_panel.visible = false
	_refresh()
	_start_btn.grab_focus()

func show_pause(race_over := false) -> void:
	finished = race_over
	visible = true
	_main_panel.visible = false
	_setup_panel.visible = false
	_pause_panel.visible = true
	_pause_title.text = "RACE FINISHED" if race_over else "PAUSED"
	_resume_btn.visible = not race_over
	_restart_btn.text = "Race again" if race_over else "Restart race"
	_info.text = main.results_text(race_over) if main != null and main.has_method("results_text") else ""
	_info.visible = _info.text != ""
	var champ_next: bool = race_over and Championship.active and Championship.round_index < Championship.ROUNDS.size()
	_next_btn.visible = champ_next
	_next_btn.text = "Final standings" if Championship.is_last_round() else "Next round"
	_restart_btn.visible = not (Championship.active and race_over)
	_replay_btn.visible = race_over and main != null and main.replay != null and main.replay.has_replay()
	if champ_next:
		_next_btn.grab_focus()
	elif race_over:
		_restart_btn.grab_focus()
	else:
		_resume_btn.grab_focus()

func hide_menu() -> void:
	visible = false

func is_main_open() -> bool:
	return visible and _main_panel.visible

# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var esc: bool = event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE
	var pad_back: bool = event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index in [JOY_BUTTON_B, JOY_BUTTON_START]
	if (esc or pad_back) and _pause_panel.visible and not finished:
		get_viewport().set_input_as_handled()
		main.resume_game()

func _process(dt: float) -> void:
	# slow turntable shot of your car behind the main menu
	if visible and _main_panel.visible and main != null and main.cam != null:
		main.cam.orbit_yaw += dt * 0.18

# ------------------------------------------------------------------ building
func _panel(width: float) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.055, 0.07, 0.92)
	sb.set_corner_radius_all(12)
	sb.border_color = Color(ACCENT, 0.5)
	sb.border_width_top = 3
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	pc.add_theme_stylebox_override("panel", sb)
	center.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	return vb

func _label(text: String, size: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _style(col: Color, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(7)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(2)
	return s

func _button(text: String, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 20 if primary else 17)
	var base := Color(0.16, 0.17, 0.2)
	b.add_theme_stylebox_override("normal", _style(ACCENT.darkened(0.15) if primary else base))
	b.add_theme_stylebox_override("hover", _style(ACCENT if primary else base.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _style(ACCENT.lightened(0.2) if primary else ACCENT.darkened(0.3)))
	b.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Color.WHITE if primary else ACCENT))
	var txt := Color(0.08, 0.08, 0.1) if primary else Color(0.92, 0.92, 0.95)
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(k, txt)
	return b

func _stepper(title: String, on_prev: Callable, on_next: Callable) -> Label:
	## "Title      <   value   >" row; returns the value label
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var t := _label(title, 17, Color(0.75, 0.76, 0.8))
	t.custom_minimum_size = Vector2(130, 0)
	row.add_child(t)
	var prev := _button("<")
	prev.custom_minimum_size = Vector2(44, 0)
	prev.pressed.connect(on_prev)
	row.add_child(prev)
	var v := _label("", 20)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var nxt := _button(">")
	nxt.custom_minimum_size = Vector2(44, 0)
	nxt.pressed.connect(on_next)
	row.add_child(nxt)
	_last_row = row
	return v

var _last_row: HBoxContainer

func _build_main() -> Control:
	var outer := _panel(940)
	var title := HBoxContainer.new()
	title.add_child(_label("CAR SIM", 46, ACCENT))
	var sub := _label("   GT racing - 3.6 km hill circuit", 16, Color(0.7, 0.72, 0.76))
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	title.add_child(sub)
	outer.add_child(title)
	outer.add_child(HSeparator.new())
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	outer.add_child(cols)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.custom_minimum_size = Vector2(520, 0)
	cols.add_child(vb)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	# ---- left: settings
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 10)
	var mt := _label("Mode", 17, Color(0.75, 0.76, 0.8))
	mt.custom_minimum_size = Vector2(130, 0)
	mrow.add_child(mt)
	for m in ["realistic", "arcade"]:
		var b := _button(m.capitalize())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_mode.bind(m == "arcade"))
		mrow.add_child(b)
		_mode_btns.append(b)
	vb.add_child(mrow)
	_mode_desc = _label("", 13, Color(0.7, 0.72, 0.76))
	_mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_desc.custom_minimum_size = Vector2(0, 36)
	vb.add_child(_mode_desc)
	_track_lbl = _stepper("Circuit", _toggle_layout, _toggle_layout)
	vb.add_child(_last_row)
	_car_name = _stepper("Car", _step_car.bind(-1), _step_car.bind(1))
	vb.add_child(_last_row)
	_car_desc = _label("", 13, Color(0.7, 0.72, 0.76))
	_car_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_car_desc)
	_laps_lbl = _stepper("Laps", _step_laps.bind(-1), _step_laps.bind(1))
	vb.add_child(_last_row)
	_opp_lbl = _stepper("Opponents", _step_opp.bind(-1), _step_opp.bind(1))
	vb.add_child(_last_row)
	_time_lbl = _stepper("Time", _step_time.bind(-1), _step_time.bind(1))
	vb.add_child(_last_row)
	_rain_lbl = _stepper("Weather", _toggle_rain, _toggle_rain)
	vb.add_child(_last_row)
	_line_lbl = _stepper("Driving line", _step_line.bind(-1), _step_line.bind(1))
	vb.add_child(_last_row)
	_wear_lbl = _stepper("Tyres & fuel", _toggle_wear, _toggle_wear)
	vb.add_child(_last_row)
	var setup := _button("Car setup  (wing, brakes, springs, gears)")
	setup.pressed.connect(_show_setup.bind(true))
	vb.add_child(setup)
	# ---- right: what to play
	_start_btn = _button("RACE", true)
	_start_btn.pressed.connect(_start.bind("race"))
	right.add_child(_start_btn)
	right.add_child(_hint("one race against the field"))
	var champ := _button("CHAMPIONSHIP", true)
	champ.pressed.connect(_start.bind("championship"))
	right.add_child(champ)
	right.add_child(_hint("4 rounds: afternoon, sunset, rain, night - points for the top six"))
	var tt := _button("TIME TRIAL", true)
	tt.pressed.connect(_start.bind("timetrial"))
	right.add_child(tt)
	right.add_child(_hint("alone against the ghost of your best lap"))
	var prac := _button("Practice")
	prac.pressed.connect(_start.bind("practice"))
	right.add_child(prac)
	var quit := _button("Quit")
	quit.pressed.connect(func() -> void: main.quit_game())
	right.add_child(quit)
	_best_lbl = _label("", 13, Color(0.7, 0.72, 0.76))
	_best_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_best_lbl)
	var help := _label("W/S gas, brake   A/D steer   Space handbrake   Q/E shift   V camera   R back on track   Esc or Start: menu",
		12, Color(0.55, 0.57, 0.62))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(help)
	_setup_panel = _build_setup()
	return outer.get_parent().get_parent()

func _start(kind: String) -> void:
	main.start_race(_settings(kind))

func _hint(t: String) -> Label:
	var l := _label(t, 12, Color(0.6, 0.62, 0.66))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# ------------------------------------------------------------------ car setup
var _setup_panel: Control
var _setup_lbls := {}
var _setup_done_btn: Button
const SETUP_ROWS := [
	["downforce", "Rear wing", -4, 4, "more: grip in fast corners, less top speed"],
	["brake_bias", "Brake balance", -4, 4, "front: stable under braking; rear: turns in, can lock the rears"],
	["springs", "Springs", -1, 1, "soft: kerbs and bumps; hard: sharper response"],
	["arb_balance", "Anti-roll balance", -3, 3, "front: stable, understeer; rear: agile, oversteer"],
	["gearing", "Gearing", -1, 1, "short: acceleration; long: top speed"],
]

func _build_setup() -> Control:
	var vb := _panel(620)
	vb.add_child(_label("CAR SETUP", 32, ACCENT))
	vb.add_child(_hint("Changes from the baseline. Applies to your car; the AI keeps the standard setup."))
	vb.add_child(HSeparator.new())
	for r in SETUP_ROWS:
		_setup_lbls[r[0]] = _stepper(r[1], _step_setup.bind(r[0], -1), _step_setup.bind(r[0], 1))
		vb.add_child(_last_row)
		vb.add_child(_hint(r[4]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var reset := _button("Reset to baseline")
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(_reset_setup)
	row.add_child(reset)
	var back := _button("Done", true)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_show_setup.bind(false))
	row.add_child(back)
	vb.add_child(row)
	_setup_done_btn = back
	var c := vb.get_parent().get_parent() as Control
	c.visible = false
	_refresh_setup()
	return c

func _reset_setup() -> void:
	CarSetup.reset()
	_refresh_setup()

func _show_setup(on: bool) -> void:
	_setup_panel.visible = on
	_main_panel.visible = not on
	if on:
		_setup_done_btn.grab_focus()
	else:
		_start_btn.grab_focus()

func _step_setup(key: String, d: int) -> void:
	for r in SETUP_ROWS:
		if r[0] == key:
			CarSetup.set_val(key, clampi(CarSetup.get_val(key) + d, r[2], r[3]))
	_refresh_setup()

func _refresh_setup() -> void:
	for r in SETUP_ROWS:
		var v: int = CarSetup.get_val(r[0])
		var txt := ("+%d" % v) if v > 0 else str(v)
		match r[0]:
			"brake_bias":
				txt = "%d %% front" % int(round(CarSetup.front_brake_share() * 100.0))
			"springs":
				txt = ["Soft", "Medium", "Hard"][v + 1]
			"gearing":
				txt = ["Short", "Medium", "Long"][v + 1]
			"arb_balance":
				txt = "baseline" if v == 0 else (("%d front" % v) if v > 0 else ("%d rear" % -v))
		_setup_lbls[r[0]].text = txt

func _build_pause() -> Control:
	var vb := _panel(380)
	_pause_title = _label("PAUSED", 34, ACCENT)
	_pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_pause_title)
	vb.add_child(HSeparator.new())
	_info = _label("", 15, Color(0.85, 0.86, 0.9))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_info)
	_next_btn = _button("Next round", true)
	_next_btn.pressed.connect(func() -> void: main.next_round())
	vb.add_child(_next_btn)
	_resume_btn = _button("Resume", true)
	_resume_btn.pressed.connect(func() -> void: main.resume_game())
	vb.add_child(_resume_btn)
	_replay_btn = _button("Watch replay")
	_replay_btn.pressed.connect(func() -> void: main.watch_replay())
	vb.add_child(_replay_btn)
	_restart_btn = _button("Restart race")
	_restart_btn.pressed.connect(func() -> void: main.restart_race())
	vb.add_child(_restart_btn)
	var settings := _button("Main menu  (mode, car, laps)")
	settings.pressed.connect(func() -> void: main.open_main_menu())
	vb.add_child(settings)
	var quit := _button("Quit game")
	quit.pressed.connect(func() -> void: main.quit_game())
	vb.add_child(quit)
	return vb.get_parent().get_parent()

# ------------------------------------------------------------------ state
func _step_time(d: int) -> void:
	time_of_day = Weather.TIMES[posmod(Weather.TIMES.find(time_of_day) + d, Weather.TIMES.size())]
	_refresh()

func _toggle_layout() -> void:
	saved = {"laps": laps, "opponents": opponents}
	main.change_layout(not RaceTrack.reversed)

func _step_line(d: int) -> void:
	RacingLineAssist.mode = posmod(RacingLineAssist.mode + d, 3)
	_refresh()

func _toggle_wear() -> void:
	CarSetup.wear_and_fuel = not CarSetup.wear_and_fuel
	_refresh()

func _toggle_rain() -> void:
	rain = not rain
	_refresh()

func _set_mode(on: bool) -> void:
	arcade = on
	_refresh()

func _step_opp(d: int) -> void:
	opponents = clampi(opponents + d, 0, RaceManager.AI_COUNT)
	_refresh()

func _step_car(d: int) -> void:
	var i := CarSpecs.ORDER.find(car_id)
	car_id = CarSpecs.ORDER[posmod(i + d, CarSpecs.ORDER.size())]
	_refresh()
	if main != null:
		main.preview_car(car_id)

func _step_laps(d: int) -> void:
	var i := LAP_CHOICES.find(laps)
	laps = LAP_CHOICES[clampi(i + d, 0, LAP_CHOICES.size() - 1)]
	_refresh()

func _settings(kind: String) -> Dictionary:
	var solo := kind == "practice" or kind == "timetrial"
	return {"kind": kind, "arcade": arcade, "car": car_id, "laps": 0 if solo else laps, "opponents": 0 if solo else opponents,
		"time": time_of_day, "rain": rain}

func _refresh() -> void:
	if _mode_btns.is_empty():
		return
	for k in 2:
		var on := (k == 1) == arcade
		var b := _mode_btns[k]
		b.add_theme_stylebox_override("normal", _style(ACCENT.darkened(0.15) if on else Color(0.16, 0.17, 0.2)))
		var txt := Color(0.08, 0.08, 0.1) if on else Color(0.92, 0.92, 0.95)
		for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
			b.add_theme_color_override(c, txt)
	_mode_desc.text = MODE_TEXT["arcade" if arcade else "realistic"]
	var sp := CarSpecs.get_spec(car_id)
	_car_name.text = sp["title"]
	_car_desc.text = sp["desc"]
	_laps_lbl.text = str(laps)
	_opp_lbl.text = str(opponents)
	_time_lbl.text = time_of_day.capitalize()
	_rain_lbl.text = "Rain" if rain else "Dry"
	_line_lbl.text = ["Off", "Braking zones", "Full line"][RacingLineAssist.mode]
	_track_lbl.text = "Valley GP - reverse" if RaceTrack.reversed else "Valley GP"
	_wear_lbl.text = "Wear + fuel + pit stops" if CarSetup.wear_and_fuel else "Off"
	if main != null and main.has_method("best_lap_text"):
		_best_lbl.text = main.best_lap_text(car_id, time_of_day, rain, arcade)
