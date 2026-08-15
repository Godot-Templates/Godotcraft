class_name MainMenu
extends Node3D

## Main menu with a live voxel-world backdrop.
##
## The World node streams terrain around CameraAnchor (which sits in the
## "player" group), while the camera slowly orbits and bobs above it for a
## continuous cinematic pan. Buttons get subtle hover/press scale tweens and
## the title gently floats.

const MAIN_SCENE: String = "res://scenes/main.tscn"
const ORBIT_SPEED: float = 0.05  # radians / second
const ORBIT_RADIUS: float = 30.0
const CAMERA_HEIGHT: float = 20.0
const BOB_AMPLITUDE: float = 2.5
const BOB_SPEED: float = 0.13
const DRIFT_SPEED: float = 0.9  # anchor drifts so new terrain streams in

@onready var _pivot: Node3D = $CameraAnchor/Pivot
@onready var _camera: Camera3D = $CameraAnchor/Pivot/Camera3D
@onready var _anchor: Node3D = $CameraAnchor
@onready var _title: Label = $UI/Center/Panel/VBox/Title
@onready var _play_button: Button = $UI/Center/Panel/VBox/PlayButton
@onready var _quit_button: Button = $UI/Center/Panel/VBox/QuitButton

var _time: float = 0.0
var _title_base_y: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_camera.position = Vector3(0.0, CAMERA_HEIGHT, ORBIT_RADIUS)
	_setup_button(_play_button)
	_setup_button(_quit_button)
	_play_button.pressed.connect(_on_play_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	# Fade the whole UI in on load.
	var ui: Control = $UI/Center
	ui.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(ui, "modulate:a", 1.0, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await get_tree().process_frame
	_title_base_y = _title.position.y


func _process(delta: float) -> void:
	_time += delta
	# Continuous orbit + gentle vertical bob.
	_pivot.rotation.y += ORBIT_SPEED * delta
	_camera.position.y = CAMERA_HEIGHT + sin(_time * BOB_SPEED * TAU) * BOB_AMPLITUDE
	# Slow anchor drift so the world keeps streaming fresh terrain.
	_anchor.position.x += cos(_time * 0.02) * DRIFT_SPEED * delta
	_anchor.position.z += sin(_time * 0.02) * DRIFT_SPEED * delta
	_camera.look_at(_anchor.global_position + Vector3(0.0, 4.0, 0.0))
	# Subtle floating title.
	if _title_base_y != 0.0:
		_title.position.y = _title_base_y + sin(_time * 1.4) * 4.0


func _setup_button(button: Button) -> void:
	button.pivot_offset = button.size / 2.0
	button.resized.connect(func() -> void:
		button.pivot_offset = button.size / 2.0)
	button.mouse_entered.connect(func() -> void:
		_scale_button(button, Vector2(1.08, 1.08)))
	button.mouse_exited.connect(func() -> void:
		_scale_button(button, Vector2.ONE))
	button.button_down.connect(func() -> void:
		_scale_button(button, Vector2(0.94, 0.94), 0.08))
	button.button_up.connect(func() -> void:
		_scale_button(button, Vector2(1.08, 1.08), 0.12))


func _scale_button(button: Button, target: Vector2, duration: float = 0.18) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(button, "scale", target, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_play_pressed() -> void:
	_play_button.disabled = true
	_quit_button.disabled = true
	# Quick fade-out before switching scenes.
	var fade: ColorRect = $UI/Fade
	fade.visible = true
	fade.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(fade, "modulate:a", 1.0, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
