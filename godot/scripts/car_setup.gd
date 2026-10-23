class_name CarSetup
extends RefCounted
## Your car's setup (the AI runs the baseline) and the race simulation options.
## Every value is a step from the baseline; 0 means "as the car comes".

static var downforce := 0        # -4..+4 : wing angle. More = grip in fast corners, less top speed
static var brake_bias := 0       # -4..+4 : 2 % steps of brake force towards the front
static var springs := 0          # -1 soft, 0 medium, +1 hard
static var arb_balance := 0      # -3..+3 : + stiffer front bar (stable, understeer), - stiffer rear (agile)
static var gearing := 0          # -1 short (acceleration), 0, +1 long (top speed)

static var wear_and_fuel := false  # tyres wear, fuel burns, pit stops matter

static func downforce_scale() -> float:
	return 1.0 + 0.09 * downforce

static func drag_scale() -> float:
	return 1.0 + 0.045 * downforce

static func front_brake_share() -> float:
	return 0.64 + 0.02 * brake_bias

static func spring_scale() -> float:
	return [0.82, 1.0, 1.2][springs + 1]

static func arb_scale(front: bool) -> float:
	return 1.0 + (0.12 if front else -0.12) * arb_balance

static func final_drive_scale() -> float:
	return [1.08, 1.0, 0.93][gearing + 1]

static func reset() -> void:
	downforce = 0
	brake_bias = 0
	springs = 0
	arb_balance = 0
	gearing = 0

static func get_val(key: String) -> int:
	match key:
		"downforce": return downforce
		"brake_bias": return brake_bias
		"springs": return springs
		"arb_balance": return arb_balance
		"gearing": return gearing
	return 0

static func set_val(key: String, v: int) -> void:
	match key:
		"downforce": downforce = v
		"brake_bias": brake_bias = v
		"springs": springs = v
		"arb_balance": arb_balance = v
		"gearing": gearing = v
