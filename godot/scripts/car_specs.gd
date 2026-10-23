class_name CarSpecs
extends RefCounted
## The car line-up (bodies come from blender/variants.py) and the game mode.
## All four share the chassis and gearbox; they differ in body, weight balance, engine
## character and sound, roughly like a balanced GT3 grid: similar pace, different feel.
## Godot axes: forward = -z, so a positive COM z is towards the rear axle.

static var arcade := false       # arcade mode: tough cars, more grip and power, no mechanical failures

const ORDER := ["gt", "fastback", "longhood", "midship"]

const SPECS := {
	"gt": {
		"title": "Cutlass 442", "exhaust": Vector2(0.45, 0.27), "desc": "front V8 muscle sedan, balanced",
		"glb": "res://assets/cutlass.glb", "nose": 2.35, "tail": 2.52, "roof": 1.373, "cab": [-0.76, 0.89],
		"eye": Vector3(0.02, 0.20, 0.50),
		"mass": 1250.0, "com_z": 0.05, "inertia": Vector3(2300.0, 2100.0, 520.0), "engine_rear": false,
		"limiter": 8600.0, "idle": 1100.0, "turbo": false,
		"torque": [[0.0, 0.0], [1000.0, 230.0], [2000.0, 360.0], [3000.0, 450.0], [4000.0, 520.0],
			[5000.0, 575.0], [6000.0, 610.0], [7000.0, 625.0], [7600.0, 620.0], [8200.0, 570.0],
			[8800.0, 460.0], [9300.0, 300.0]],
		# sound: firings per cycle, relative strength of each, exhaust resonances (Hz), brightness
		"pulses": [1.0, 0.80, 1.10, 0.88, 0.96, 1.14, 0.84, 1.05], "res": [135.0, 410.0, 1250.0], "bright": 1.0,
	},
	"fastback": {
		"title": "Kiri Turbo", "exhaust": Vector2(0.40, 0.25), "desc": "light turbo four, revs to 9,400 rpm",
		"glb": "res://assets/kiri.glb", "nose": 2.31, "tail": 2.51, "roof": 1.496, "cab": [-0.94, 0.99],
		"eye": Vector3(0.02, 0.27, 0.48),
		"mass": 1200.0, "com_z": 0.0, "inertia": Vector3(2250.0, 2150.0, 500.0), "engine_rear": false,
		"limiter": 9400.0, "idle": 1300.0, "turbo": true,
		"torque": [[0.0, 0.0], [1000.0, 200.0], [2000.0, 300.0], [3000.0, 380.0], [4000.0, 440.0],
			[5000.0, 490.0], [6000.0, 530.0], [7000.0, 555.0], [7800.0, 565.0], [8600.0, 545.0],
			[9300.0, 480.0], [9900.0, 320.0]],
		"pulses": [1.0, 0.92, 1.06, 0.95], "res": [210.0, 680.0, 2100.0], "bright": 1.3,
	},
	"longhood": {
		"title": "Phoenix 455", "exhaust": Vector2(0.40, 0.25), "desc": "big 7.5 V8 muscle car, torque everywhere",
		"glb": "res://assets/phoenix.glb", "nose": 2.28, "tail": 2.62, "roof": 1.349, "cab": [-0.57, 1.16],
		"eye": Vector3(0.02, 0.27, 0.48),
		"mass": 1270.0, "com_z": 0.02, "inertia": Vector3(2400.0, 2250.0, 540.0), "engine_rear": false,
		"limiter": 7600.0, "idle": 950.0, "turbo": false,
		"torque": [[0.0, 0.0], [1000.0, 330.0], [2000.0, 520.0], [3000.0, 640.0], [4000.0, 725.0],
			[5000.0, 750.0], [6000.0, 748.0], [6800.0, 728.0], [7300.0, 672.0], [7800.0, 505.0],
			[8300.0, 300.0]],
		"pulses": [1.0, 0.70, 1.16, 0.80, 0.92, 1.22, 0.76, 1.08], "res": [105.0, 320.0, 980.0], "bright": 0.85,
	},
	"midship": {
		"title": "Saba V12", "exhaust": Vector2(0.15, 0.28), "desc": "mid-engined V12 supercar, agile",
		"glb": "res://assets/saba.glb", "nose": 2.36, "tail": 2.16, "roof": 1.317, "cab": [-1.32, 0.72], "eye": Vector3(0.02, 0.30, 0.50),
		"mass": 1250.0, "com_z": 0.21, "inertia": Vector3(2150.0, 1900.0, 500.0), "engine_rear": true,
		"limiter": 8600.0, "idle": 1150.0, "turbo": false,
		"torque": [[0.0, 0.0], [1000.0, 260.0], [2000.0, 420.0], [3000.0, 640.0], [4000.0, 700.0],
			[5000.0, 710.0], [6000.0, 700.0], [7000.0, 650.0], [7600.0, 590.0], [8200.0, 480.0],
			[8800.0, 300.0]],
		"pulses": [1.0, 0.96, 1.03, 0.98, 1.02, 0.97, 1.01, 0.95, 1.04, 0.97, 1.0, 0.98], "res": [180.0, 560.0, 1700.0], "bright": 1.1,
	},
}

static func get_spec(id: String) -> Dictionary:
	return SPECS.get(id, SPECS["gt"])

static func next_id(id: String) -> String:
	return ORDER[(ORDER.find(id) + 1) % ORDER.size()]

# ---- mode factors (1.0 in realistic mode)
static func grip_factor() -> float:
	return 1.15 if arcade else 1.0

static func power_factor() -> float:
	return 1.08 if arcade else 1.0

static func damage_factor() -> float:
	return 0.1 if arcade else 1.0
