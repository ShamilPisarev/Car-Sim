class_name Hud
extends CanvasLayer

var car: Car
var cam: ChaseCam
var track = null                  # RaceTrack (duck-typed so the project still runs without it)
var race: RaceManager = null
var ghost: GhostLap = null
var show_debug := false
var show_help := false
var label: Label
var dmg_label: Label
var panel: Control
var _flash := ""
var _flash_t := 0.0

func _ready() -> void:
	label = _make_label(Vector2(16, 12), 15)
	dmg_label = _make_label(Vector2(16, 150), 14)
	panel = HudDraw.new()
	add_child(panel)
	(panel as HudDraw).hud = self

func _make_label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
	return l

func flash(msg: String) -> void:
	_flash = msg
	_flash_t = 3.0

func _fmt_time(t: float) -> String:
	if t <= 0.0:
		return "--:--.---"
	var m := int(t / 60.0)
	return "%d:%06.3f" % [m, t - m * 60.0]

func _process(dt: float) -> void:
	if car == null:
		return
	_flash_t = maxf(_flash_t - dt, 0.0)
	var t := "%s  -  %s     Esc menu\n" % ["ARCADE" if CarSpecs.arcade else "REALISTIC", car.spec["title"]]
	if Championship.active and Championship.round_index < Championship.ROUNDS.size():
		t += "CHAMPIONSHIP  %s\n" % Championship.current()["name"]
	if race != null:
		if ghost != null and ghost.enabled:
			var gap := ""
			if ghost.has_delta:
				gap = "   GAP %+.2f" % ghost.delta
			t += "TIME TRIAL     LAP %d     BEST %s%s\n" % [race.lap_of(car), _fmt_time(ghost.best_time), gap]
		elif race.laps == 0:
			t += "PRACTICE     LAP %d\n" % race.lap_of(car)
		else:
			t += "POSITION %d / %d     LAP %d / %d     %s\n" % [race.position_of(car), race.cars.size(), race.lap_of(car), race.laps, race.gap_text(car)]
	if track != null:
		t += "LAP %d   now %s   last %s   best %s\n" % [track.lap_number, _fmt_time(track.current_lap_time), _fmt_time(track.last_lap_time), _fmt_time(track.best_lap_time)]
	if CarSetup.wear_and_fuel:
		var worn := 0.0
		for w in car.wheels:
			worn = maxf(worn, w.wear)
		t += "FUEL %.1f kg (%.1f laps)%s   TYRES %d %% worn%s\n" % [car.fuel, car.fuel / RaceManager.FUEL_PER_LAP,
			"  EMPTY!" if car.out_of_fuel else "", int(worn * 100.0), "  - pit soon" if worn > 0.6 else ""]
	if race != null and race.pit_time_left > 0.0:
		t += "PIT CREW WORKING  %.1f s\n" % race.pit_time_left
	elif car.speed_cap > 0.0:
		t += "PIT LANE - limiter 60 km/h   (stop in the yellow box for tyres, fuel, repairs)\n"
	t += "ABS %s   TC %s%s   DRIFT ASSIST %s   gearbox %s   camera: %s\n" % [
		"on" if car.abs_enabled else "off", "on" if car.tc_enabled else "off", " (cutting)" if car.tc_active else "",
		"on" if car.assist_enabled else "off", "manual" if car.manual else "auto", ChaseCam.MODE_NAMES[cam.mode]]
	t += "engine %d C   coolant %d%%   drift angle %d deg   g: %.1f lat  %.1f long\n" % [
		int(car.engine_temp), int(car.coolant * 100.0), int(absf(rad_to_deg(car.drift_angle))),
		car.last_accel_local.x / 9.81, -car.last_accel_local.z / 9.81]
	if show_help:
		t += "W/S gas, brake, reverse   A/D steer   Space handbrake   Q/E shift (Y = auto)   R back on track   V camera\n"
		t += "N traction ctrl   B ABS   M drift assist   1 2 doors  H hood  T trunk  F windows  G repair   X x-ray   Tab debug   F1 help   F2 mute\n"
		t += "F5 proving ground (bumps, ramps, crash wall)   F6 restart race"
	else:
		t += "F1 controls"
	label.text = t
	# only what matters: parts badly hit, wheels, engine and cooling problems
	var lines := PackedStringArray()
	if car.parts:
		for l in car.parts.summary().split("\n"):
			var words := l.replace("%", "").split(" ")
			var pct := words[words.size() - 1] if words.size() > 0 else ""
			if l.begins_with("wheel") or l.begins_with("engine") or l.begins_with("coolant") or l.contains("GONE") \
					or l.contains("FIRE") or (pct.is_valid_int() and int(pct) >= 25 and not l.begins_with("crush")):
				lines.append(l)
	dmg_label.text = ("DAMAGE\n" + "\n".join(lines)) if not lines.is_empty() else ""
	dmg_label.position.y = label.position.y + label.get_minimum_size().y + 8.0
	panel.queue_redraw()

class HudDraw extends Control:
	var hud: Hud
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var car := hud.car
		if car == null:
			return
		var font := ThemeDB.fallback_font
		# --- speed, gear, rev bar (bottom centre)
		var cx := size.x * 0.5
		var by := size.y - 40.0
		draw_string(font, Vector2(cx - 150, by - 36), "%d" % int(car.speed_kmh), HORIZONTAL_ALIGNMENT_RIGHT, 120, 56, Color.WHITE)
		draw_string(font, Vector2(cx - 22, by - 44), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.8))
		var gtxt := "R" if car.reverse_mode else str(car.gear)
		draw_string(font, Vector2(cx + 60, by - 30), gtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(1.0, 0.8, 0.2))
		var bar_w := 520.0
		var rmax := car.limiter_rpm + 400.0
		var frac := clampf(car.engine_rpm / rmax, 0.0, 1.0)
		draw_rect(Rect2(cx - bar_w * 0.5, by, bar_w, 14), Color(0, 0, 0, 0.6))
		var col := Color(0.3, 0.9, 0.4).lerp(Color(1.0, 0.15, 0.1), clampf((car.engine_rpm - (car.limiter_rpm - 2100.0)) / 2000.0, 0.0, 1.0))
		draw_rect(Rect2(cx - bar_w * 0.5, by, bar_w * frac, 14), col)
		draw_rect(Rect2(cx - bar_w * 0.5 + bar_w * (car.limiter_rpm - 800.0) / rmax, by, bar_w * 1200.0 / rmax, 14), Color(1, 0.1, 0.1, 0.35))
		draw_string(font, Vector2(cx - bar_w * 0.5, by + 32), "%d rpm   throttle %d%%   brake %d%%" % [int(car.engine_rpm), int(car.throttle * 100.0), int(car.brake * 100.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		if hud._flash_t > 0.0:
			draw_string(font, Vector2(cx - 300, size.y * 0.3), hud._flash, HORIZONTAL_ALIGNMENT_CENTER, 600, 32, Color(1, 0.9, 0.3))
		if hud.race != null:
			_draw_race(font, cx)
			_draw_flags(font, cx)
		if not hud.show_debug:
			return
		var origin := Vector2(size.x - 340, 20)
		draw_string(font, origin, "Suspension travel / load / grip / slip angle", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		var i := 0
		for w in car.wheels:
			var y := origin.y + 14 + i * 38
			var x := origin.x
			draw_string(font, Vector2(x, y + 12), w.tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
			var frac_d := clampf(w.d / Car.TRAVEL, 0.0, 1.0)
			draw_rect(Rect2(x + 30, y, 120, 10), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(x + 30, y, 120 * (1.0 - frac_d), 10), Color(0.95, 0.65, 0.1))
			draw_rect(Rect2(x + 30, y + 14, 120, 10), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(x + 30, y + 14, 120 * clampf(w.fz / 9000.0, 0.0, 1.0), 10), Color(0.3, 0.7, 1.0))
			var gcol := Color(0.3, 0.9, 0.3).lerp(Color(1.0, 0.2, 0.1), clampf(w.grip_use, 0.0, 1.0))
			draw_rect(Rect2(x + 160, y, 80, 10), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(x + 160, y, 80 * clampf(w.grip_use, 0.0, 1.0), 10), gcol)
			var txt := "%+.0f deg" % rad_to_deg(w.slip_angle)
			if w.abs_active:
				txt += " ABS"
			if w.detached:
				txt = "GONE"
			draw_string(font, Vector2(x + 250, y + 10), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
			i += 1

	func _draw_race(font: Font, cx: float) -> void:
		var race := hud.race
		# start lights: five red lamps, all out = go
		if race.phase == RaceManager.Phase.LIGHTS or race.phase == RaceManager.Phase.GRID or (race.phase == RaceManager.Phase.GREEN and race.phase_t < 1.5):
			var y := size.y * 0.16
			draw_rect(Rect2(cx - 150, y - 34, 300, 68), Color(0.03, 0.03, 0.04, 0.85))
			for k in 5:
				var on := k < race.lights_on
				var col := Color(1.0, 0.08, 0.05) if on else Color(0.18, 0.05, 0.05)
				if race.phase == RaceManager.Phase.GREEN:
					col = Color(0.15, 0.9, 0.25)
				draw_circle(Vector2(cx - 112 + 56 * k, y), 22.0, col)
			if race.phase == RaceManager.Phase.GREEN:
				draw_string(font, Vector2(cx - 150, y + 80), "GO!", HORIZONTAL_ALIGNMENT_CENTER, 300, 48, Color(0.3, 1.0, 0.4))
			else:
				draw_string(font, Vector2(cx - 200, y + 70), "hold the throttle to rev, go when the lights go out", HORIZONTAL_ALIGNMENT_CENTER, 400, 15, Color(1, 1, 1, 0.8))
		# live order, top right under the debug bars
		var st := race.standings()
		var x0 := size.x - 310.0
		var y0 := 190.0 if hud.show_debug else 20.0
		draw_rect(Rect2(x0 - 8, y0 - 4, 302, 22 * st.size() + 10), Color(0, 0, 0, 0.45))
		for k in st.size():
			var c: Car = st[k]
			var me := c == hud.car
			var col := Color(1.0, 0.85, 0.2) if me else Color.WHITE
			var extra := ""
			if race.finish_time.has(c):
				extra = "%.2f" % race.finish_time[c]
			elif race.dnf.has(c):
				extra = "DNF"
				col = Color(0.6, 0.6, 0.6)
			draw_string(font, Vector2(x0, y0 + 16 + 22 * k), "%d  %s" % [k + 1, race.name_of(c)], HORIZONTAL_ALIGNMENT_LEFT, 120, 16, col)
			draw_string(font, Vector2(x0 + 118, y0 + 16 + 22 * k), race.model_of(c), HORIZONTAL_ALIGNMENT_LEFT, 100, 13, Color(col.r, col.g, col.b, 0.6))
			draw_string(font, Vector2(x0 + 210, y0 + 16 + 22 * k), extra, HORIZONTAL_ALIGNMENT_RIGHT, 76, 15, col)
		# mini map, bottom left
		var mm_size := 190.0
		var origin := Vector2(18, size.y - mm_size - 18)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in race.center:
			mn = mn.min(Vector2(p.x, p.z))
			mx = mx.max(Vector2(p.x, p.z))
		var sc := mm_size / maxf(mx.x - mn.x, mx.y - mn.y)
		var pts := PackedVector2Array()
		for k in range(0, race.n, 6):
			pts.append(origin + (Vector2(race.center[k].x, race.center[k].z) - mn) * sc)
		pts.append(pts[0])
		draw_rect(Rect2(origin - Vector2(8, 8), Vector2(mm_size + 16, (mx.y - mn.y) * sc + 16)), Color(0, 0, 0, 0.4))
		draw_polyline(pts, Color(1, 1, 1, 0.75), 3.0, true)
		for c in race.cars:
			if race.dnf.has(c):
				continue
			var q := origin + (Vector2(c.global_position.x, c.global_position.z) - mn) * sc
			draw_circle(q, 6.0 if c == hud.car else 4.5, Color(1.0, 0.85, 0.2) if c == hud.car else Color(1.0, 0.25, 0.2))
		# results
		if race.finish_time.has(hud.car):
			var w := 420.0
			var h := 60.0 + 30.0 * race.finish_order.size()
			var r := Rect2(cx - w * 0.5, size.y * 0.25, w, h)
			draw_rect(r, Color(0, 0, 0, 0.75))
			draw_string(font, r.position + Vector2(0, 38), "RESULTS", HORIZONTAL_ALIGNMENT_CENTER, w, 24, Color(1, 0.85, 0.2))
			var lead: float = race.finish_time[race.finish_order[0]]
			for k in race.finish_order.size():
				var c2: Car = race.finish_order[k]
				var tm: float = race.finish_time[c2]
				var gap := "%d:%06.3f" % [int(tm / 60.0), fmod(tm, 60.0)] if k == 0 else "+%.3f" % (tm - lead)
				var col2 := Color(1.0, 0.85, 0.2) if c2 == hud.car else Color.WHITE
				draw_string(font, r.position + Vector2(30, 72 + 30 * k), "%d.  %s" % [k + 1, race.name_of(c2)], HORIZONTAL_ALIGNMENT_LEFT, 250, 20, col2)
				draw_string(font, r.position + Vector2(220, 72 + 30 * k), gap, HORIZONTAL_ALIGNMENT_RIGHT, 170, 20, col2)

	func _draw_flags(font: Font, cx: float) -> void:
		## flag banner and race-control messages, top centre
		var race := hud.race
		var y := size.y * 0.27
		if race.flag != "" and race.phase == RaceManager.Phase.GREEN:
			var col := Color(1.0, 0.85, 0.1) if race.flag == "yellow" else Color(0.15, 0.4, 1.0)
			var txt := "YELLOW FLAG - incident ahead, slow down" if race.flag == "yellow" else "BLUE FLAG - let the leader through"
			draw_rect(Rect2(cx - 230, y - 26, 460, 38), Color(col, 0.85))
			draw_string(font, Vector2(cx - 230, y), txt, HORIZONTAL_ALIGNMENT_CENTER, 460, 20, Color(0.05, 0.05, 0.05) if race.flag == "yellow" else Color.WHITE)
			y += 46
		if race.notice_t > 0.0:
			draw_rect(Rect2(cx - 230, y - 26, 460, 38), Color(0.75, 0.08, 0.06, 0.85))
			draw_string(font, Vector2(cx - 230, y), race.notice, HORIZONTAL_ALIGNMENT_CENTER, 460, 20, Color.WHITE)
		if race.finish_time.has(hud.car) and race.phase == RaceManager.Phase.DONE:
			# chequered flag
			var fx := cx - 60.0
			var fy := size.y * 0.16 - 30.0
			for r in 4:
				for c in 8:
					draw_rect(Rect2(fx + c * 15, fy + r * 15, 15, 15), Color.WHITE if (r + c) % 2 == 0 else Color.BLACK)
