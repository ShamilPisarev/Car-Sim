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
		"title": "GT Coupe", "exhaust": Vector2(0.24, 0.27), "desc": "front-mid V8, balanced",
		"glb": "res://assets/sedan.glb", "nose": 2.35, "tail": 2.33, "roof": 1.215, "cab": [-0.68, 1.47],
		"mass": 1250.0, "com_z": 0.05, "inertia": Vector3(2300.0, 2100.0, 520.0), "engine_rear": false,
		"limiter": 8600.0, "idle": 1100.0, "turbo": false,
		"torque": [[0.0, 0.0], [1000.0, 230.0], [2000.0, 360.0], [3000.0, 450.0], [4000.0, 520.0],
			[5000.0, 575.0], [6000.0, 610.0], [7000.0, 625.0], [7600.0, 620.0], [8200.0, 570.0],
			[8800.0, 460.0], [9300.0, 300.0]],
		# sound: firings per cycle, relative strength of each, exhaust resonances (Hz), brightness
		"pulses": [1.0, 0.80, 1.10, 0.88, 0.96, 1.14, 0.84, 1.05], "res": [135.0, 410.0, 1250.0], "bright": 1.0,
	},
	"fastback": {
		"title": "Fastback", "exhaust": Vector2(0.10, 0.28), "desc": "rear-engined flat-6, screams to 9,400 rpm",
		"glb": "res://assets/fastback.glb", "nose": 2.33, "tail": 2.31, "roof": 1.235, "cab": [-0.72, 1.74],
		"mass": 1250.0, "com_z": 0.27, "inertia": Vector3(2350.0, 2250.0, 520.0), "engine_rear": true,
		"limiter": 9400.0, "idle": 1300.0, "turbo": false,
		"torque": [[0.0, 0.0], [1000.0, 200.0], [2000.0, 300.0], [3000.0, 380.0], [4000.0, 440.0],
			[5000.0, 490.0], [6000.0, 530.0], [7000.0, 555.0], [7800.0, 565.0], [8600.0, 545.0],
			[9300.0, 480.0], [9900.0, 320.0]],
		"pulses": [1.0, 0.95, 1.03, 0.97, 1.01, 0.96], "res": [190.0, 620.0, 1900.0], "bright": 1.25,
	},
	"longhood": {
		"title": "Long-hood", "exhaust": Vector2(0.34, 0.25), "desc": "big 6.2 V8, torque everywhere",
		"glb": "res://assets/longhood.glb", "nose": 2.40, "tail": 2.32, "roof": 1.20, "cab": [-0.38, 1.62],
		"mass": 1270.0, "com_z": 0.02, "inertia": Vector3(2400.0, 2250.0, 540.0), "engine_rear": false,
		"limiter": 7600.0, "idle": 950.0, "turbo": false,
		"torque": [[0.0, 0.0], [1000.0, 330.0], [2000.0, 520.0], [3000.0, 640.0], [4000.0, 725.0],
			[5000.0, 750.0], [6000.0, 748.0], [6800.0, 728.0], [7300.0, 672.0], [7800.0, 505.0],
			[8300.0, 300.0]],
		"pulses": [1.0, 0.70, 1.16, 0.80, 0.92, 1.22, 0.76, 1.08], "res": [105.0, 320.0, 980.0], "bright": 0.85,
	},
	"midship": {
		"title": "Midship", "exhaust": Vector2(0.15, 0.28), "desc": "mid-engined twin-turbo V6, agile",
		"glb": "res://assets/midship.glb", "nose": 2.32, "tail": 2.33, "roof": 1.075, "cab": [-0.90, 1.17],
		"mass": 1250.0, "com_z": 0.21, "inertia": Vector3(2150.0, 1900.0, 500.0), "engine_rear": true,
		"limiter": 8200.0, "idle": 1150.0, "turbo": true,
		"torque": [[0.0, 0.0], [1000.0, 260.0], [2000.0, 420.0], [3000.0, 640.0], [4000.0, 700.0],
			[5000.0, 710.0], [6000.0, 700.0], [7000.0, 650.0], [7600.0, 590.0], [8200.0, 480.0],
			[8800.0, 300.0]],
		"pulses": [1.0, 0.93, 1.05, 0.95, 1.02, 0.94], "res": [160.0, 500.0, 1500.0], "bright": 0.8,
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
