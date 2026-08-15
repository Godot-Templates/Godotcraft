class_name Weather
extends Node3D

## Simple rain toggler. Cycles between clear and rainy periods on a timer and
## spawns a falling-rain particle effect around the player while it rains.
## Other systems (e.g. chickens) read `is_raining` or listen to `rain_changed`.

signal rain_changed(raining: bool)

const CLEAR_MIN_SEC: float = 20.0
const CLEAR_MAX_SEC: float = 45.0
const RAIN_MIN_SEC: float = 15.0
const RAIN_MAX_SEC: float = 30.0
const RAIN_HEIGHT: float = 12.0
const RAIN_RADIUS: float = 16.0

var is_raining: bool = false

var _time_left: float = 0.0
var _player: Node3D
var _rain_particles: GPUParticles3D


func _ready() -> void:
    add_to_group("weather")
    _player = get_tree().get_first_node_in_group("player")
    _build_rain_particles()
    _time_left = randf_range(CLEAR_MIN_SEC, CLEAR_MAX_SEC)


func _process(delta: float) -> void:
    if _player == null:
        _player = get_tree().get_first_node_in_group("player")

    _time_left -= delta
    if _time_left <= 0.0:
        _toggle_rain()

    if is_raining and _player != null and _rain_particles != null:
        _rain_particles.global_position = _player.global_position + Vector3(0.0, RAIN_HEIGHT, 0.0)


func _toggle_rain() -> void:
    is_raining = not is_raining
    _time_left = randf_range(RAIN_MIN_SEC, RAIN_MAX_SEC) if is_raining else randf_range(CLEAR_MIN_SEC, CLEAR_MAX_SEC)
    if _rain_particles != null:
        _rain_particles.emitting = is_raining
        _rain_particles.visible = is_raining
    rain_changed.emit(is_raining)


func _build_rain_particles() -> void:
    var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    mat.emission_box_extents = Vector3(RAIN_RADIUS, 0.5, RAIN_RADIUS)
    mat.direction = Vector3(0.0, -1.0, 0.0)
    mat.spread = 2.0
    mat.gravity = Vector3(0.0, -20.0, 0.0)
    mat.initial_velocity_min = 1.0
    mat.initial_velocity_max = 2.0
    mat.color = Color(0.6, 0.7, 0.95, 0.55)

    var draw_mat: StandardMaterial3D = StandardMaterial3D.new()
    draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    draw_mat.albedo_color = Color(0.6, 0.7, 0.95, 0.55)
    draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    draw_mat.disable_receive_shadows = true

    var mesh: QuadMesh = QuadMesh.new()
    mesh.size = Vector2(0.03, 0.35)
    mesh.material = draw_mat

    _rain_particles = GPUParticles3D.new()
    _rain_particles.name = "RainParticles"
    _rain_particles.amount = 400
    _rain_particles.lifetime = 1.2
    _rain_particles.emitting = false
    _rain_particles.visible = false
    _rain_particles.process_material = mat
    _rain_particles.draw_pass_1 = mesh
    _rain_particles.visibility_aabb = AABB(Vector3(-RAIN_RADIUS, -RAIN_HEIGHT - 2.0, -RAIN_RADIUS), Vector3(RAIN_RADIUS * 2.0, RAIN_HEIGHT + 4.0, RAIN_RADIUS * 2.0))
    add_child(_rain_particles)
