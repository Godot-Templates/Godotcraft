class_name DayNightCycle
extends Node

## Minecraft-style day/night cycle.
## Rotates the sun, blends sky/ambient/fog colors between day, night and
## sunrise/sunset palettes. time_of_day: 0.0 = midnight, 0.25 = sunrise,
## 0.5 = noon, 0.75 = sunset.

const SUN_YAW_DEG: float = -30.0

# --- Sky palettes ---
const DAY_SKY_TOP: Color = Color(0.25, 0.52, 0.92)
const DAY_SKY_HORIZON: Color = Color(0.62, 0.80, 0.96)
const DAY_GROUND_BOTTOM: Color = Color(0.22, 0.25, 0.30)
const DAY_GROUND_HORIZON: Color = Color(0.60, 0.74, 0.88)

const NIGHT_SKY_TOP: Color = Color(0.06, 0.05, 0.22)
const NIGHT_SKY_HORIZON: Color = Color(0.32, 0.26, 0.58)
const NIGHT_GROUND_BOTTOM: Color = Color(0.03, 0.03, 0.09)
const NIGHT_GROUND_HORIZON: Color = Color(0.18, 0.16, 0.34)

const SUNSET_HORIZON: Color = Color(0.98, 0.52, 0.26)
const SUNSET_TOP_TINT: Color = Color(0.45, 0.30, 0.50)

# --- Sun light ---
const SUN_COLOR_DAY: Color = Color(1.0, 0.97, 0.9)
const SUN_COLOR_LOW: Color = Color(1.0, 0.62, 0.35)
const MOON_COLOR: Color = Color(0.55, 0.65, 1.0)
const SUN_ENERGY_DAY: float = 1.0
const MOON_ENERGY: float = 0.12

# --- Ambient / fog ---
const AMBIENT_DAY: Color = Color(0.78, 0.83, 0.92)
const AMBIENT_NIGHT: Color = Color(0.35, 0.38, 0.62)
const AMBIENT_ENERGY_DAY: float = 1.4
const AMBIENT_ENERGY_NIGHT: float = 0.75
const FOG_DAY: Color = Color(0.72, 0.82, 0.95)
const FOG_NIGHT: Color = Color(0.42, 0.38, 0.78)

@export var sun_path: NodePath
@export var environment_path: NodePath
## Real-time seconds for one full in-game day.
@export var day_length_seconds: float = 300.0
## 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset.
@export_range(0.0, 1.0) var time_of_day: float = 0.35

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial


func _ready() -> void:
	add_to_group("day_night_cycle")
	if sun_path != NodePath(""):
		_sun = get_node_or_null(sun_path) as DirectionalLight3D
	if environment_path != NodePath(""):
		var world_env: WorldEnvironment = get_node_or_null(environment_path) as WorldEnvironment
		if world_env != null:
			_env = world_env.environment
			if _env != null:
				_sky = _env.sky.sky_material as ProceduralSkyMaterial
	_apply(0.0)


func _process(delta: float) -> void:
	_apply(delta)


func get_time_of_day() -> float:
	return time_of_day


func is_night() -> bool:
	return _sun_height() < -0.05


func _sun_height() -> float:
	# 0 at sunrise/sunset, 1 at noon, -1 at midnight.
	return sin((time_of_day - 0.25) * TAU)


func _apply(delta: float) -> void:
	if day_length_seconds > 0.0:
		time_of_day = fposmod(time_of_day + delta / day_length_seconds, 1.0)

	var height: float = _sun_height()
	# 0 = full night, 1 = full day, smooth twilight band around the horizon.
	var daylight: float = smoothstep(-0.08, 0.18, height)
	# Bell curve peaking when the sun crosses the horizon (sunrise/sunset glow).
	var glow: float = clamp(1.0 - absf(height) / 0.22, 0.0, 1.0)

	if _sun != null:
		var pitch: float = -(time_of_day - 0.25) * 360.0
		_sun.rotation_degrees = Vector3(pitch, SUN_YAW_DEG, 0.0)
		if height >= 0.0:
			# Warm near the horizon, white at noon.
			_sun.light_color = SUN_COLOR_LOW.lerp(SUN_COLOR_DAY, clamp(height / 0.35, 0.0, 1.0))
			_sun.light_energy = lerp(MOON_ENERGY, SUN_ENERGY_DAY, daylight)
		else:
			# Below the horizon the same light acts as cool moonlight.
			_sun.light_color = MOON_COLOR
			_sun.light_energy = MOON_ENERGY

	if _sky != null:
		var top: Color = NIGHT_SKY_TOP.lerp(DAY_SKY_TOP, daylight)
		top = top.lerp(SUNSET_TOP_TINT, glow * 0.5)
		var horizon: Color = NIGHT_SKY_HORIZON.lerp(DAY_SKY_HORIZON, daylight)
		horizon = horizon.lerp(SUNSET_HORIZON, glow * 0.85)
		_sky.sky_top_color = top
		_sky.sky_horizon_color = horizon
		_sky.ground_bottom_color = NIGHT_GROUND_BOTTOM.lerp(DAY_GROUND_BOTTOM, daylight)
		_sky.ground_horizon_color = NIGHT_GROUND_HORIZON.lerp(DAY_GROUND_HORIZON, daylight).lerp(
			SUNSET_HORIZON, glow * 0.6
		)

	if _env != null:
		_env.ambient_light_color = AMBIENT_NIGHT.lerp(AMBIENT_DAY, daylight)
		_env.ambient_light_energy = lerp(AMBIENT_ENERGY_NIGHT, AMBIENT_ENERGY_DAY, daylight)
		_env.fog_light_color = FOG_NIGHT.lerp(FOG_DAY, daylight).lerp(SUNSET_HORIZON, glow * 0.4)
