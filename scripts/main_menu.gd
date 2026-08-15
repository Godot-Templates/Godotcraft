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
const TITLE_SWAY_DEGREES: float = 1.5
const TITLE_PULSE_AMOUNT: float = 0.025
const TITLE_ANIMATION_SPEED: float = 1.2
const VIEW_MAIN: String = "main"
const VIEW_HOST: String = "host"
const VIEW_JOIN: String = "join"
const RUNTIME_SEED_SETTING: String = "game/runtime_world_seed"
const RUNTIME_MODE_SETTING: String = "game/runtime_mode"
const MODE_SURVIVAL: String = "survival"
const MODE_CREATIVE: String = "creative"

@onready var _pivot: Node3D = $CameraAnchor/Pivot
@onready var _camera: Camera3D = $CameraAnchor/Pivot/Camera3D
@onready var _anchor: Node3D = $CameraAnchor
@onready var _title: Label = $UI/Center/Panel/VBox/Title
@onready var _main_buttons: VBoxContainer = $UI/Center/Panel/VBox/MainButtons
@onready var _seed_input: LineEdit = $UI/Center/Panel/VBox/MainButtons/SeedInput
@onready var _mode_button: Button = $UI/Center/Panel/VBox/MainButtons/ModeButton
@onready var _play_button: Button = $UI/Center/Panel/VBox/MainButtons/PlayButton
@onready var _host_button: Button = $UI/Center/Panel/VBox/MainButtons/HostButton
@onready var _join_button: Button = $UI/Center/Panel/VBox/MainButtons/JoinButton
@onready var _quit_button: Button = $UI/Center/Panel/VBox/MainButtons/QuitButton
@onready var _host_view: VBoxContainer = $UI/Center/Panel/VBox/HostView
@onready var _host_status: Label = $UI/Center/Panel/VBox/HostView/StatusLabel
@onready var _room_code_label: Label = $UI/Center/Panel/VBox/HostView/RoomCodeLabel
@onready var _host_start_button: Button = $UI/Center/Panel/VBox/HostView/StartButton
@onready var _host_cancel_button: Button = $UI/Center/Panel/VBox/HostView/CancelButton
@onready var _join_view: VBoxContainer = $UI/Center/Panel/VBox/JoinView
@onready var _code_input: LineEdit = $UI/Center/Panel/VBox/JoinView/CodeInput
@onready var _join_status: Label = $UI/Center/Panel/VBox/JoinView/StatusLabel
@onready var _connect_button: Button = $UI/Center/Panel/VBox/JoinView/ConnectButton
@onready var _join_cancel_button: Button = $UI/Center/Panel/VBox/JoinView/CancelButton

var _time: float = 0.0
var _multiplayer_manager: MultiplayerManager
var _pending_multiplayer_action: String = ""
var _selected_world_seed: int = 1337
var _selected_game_mode: String = MODE_SURVIVAL


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_camera.position = Vector3(0.0, CAMERA_HEIGHT, ORBIT_RADIUS)
	_multiplayer_manager = get_node("/root/MpManager") as MultiplayerManager
	_setup_title_animation()
	for button: Button in [
		_mode_button,
		_play_button,
		_host_button,
		_join_button,
		_quit_button,
		_host_start_button,
		_host_cancel_button,
		_connect_button,
		_join_cancel_button,
	]:
		_setup_button(button)
	_mode_button.pressed.connect(_on_mode_pressed)
	_play_button.pressed.connect(_on_play_pressed)
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_show_join)
	_quit_button.pressed.connect(_on_quit_pressed)
	_host_start_button.pressed.connect(_start_game)
	_host_cancel_button.pressed.connect(_on_multiplayer_cancelled)
	_connect_button.pressed.connect(_on_join_pressed)
	_join_cancel_button.pressed.connect(_on_multiplayer_cancelled)
	_code_input.text_submitted.connect(_on_code_submitted)
	_multiplayer_manager.room_created.connect(_on_room_created)
	_multiplayer_manager.room_joined.connect(_on_room_joined)
	_multiplayer_manager.connection_failed.connect(_on_connection_failed)
	_show_view(VIEW_MAIN)
	# Fade the whole UI in on load.
	var ui: Control = $UI/Center
	ui.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(ui, "modulate:a", 1.0, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_time += delta
	# Continuous orbit + gentle vertical bob.
	_pivot.rotation.y += ORBIT_SPEED * delta
	_camera.position.y = CAMERA_HEIGHT + sin(_time * BOB_SPEED * TAU) * BOB_AMPLITUDE
	# Slow anchor drift so the world keeps streaming fresh terrain.
	_anchor.position.x += cos(_time * 0.02) * DRIFT_SPEED * delta
	_anchor.position.z += sin(_time * 0.02) * DRIFT_SPEED * delta
	_camera.look_at(_anchor.global_position + Vector3(0.0, 4.0, 0.0))
	# A restrained sway and pulse keeps the title alive without hurting readability.
	var title_wave: float = sin(_time * TITLE_ANIMATION_SPEED)
	_title.rotation = deg_to_rad(title_wave * TITLE_SWAY_DEGREES)
	var title_scale: float = 1.0 + title_wave * TITLE_PULSE_AMOUNT
	_title.scale = Vector2(title_scale, title_scale)


func _setup_title_animation() -> void:
	_title.pivot_offset = _title.size / 2.0
	_title.resized.connect(func() -> void:
		_title.pivot_offset = _title.size / 2.0)


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


func _show_view(view: String) -> void:
	_main_buttons.visible = view == VIEW_MAIN
	_host_view.visible = view == VIEW_HOST
	_join_view.visible = view == VIEW_JOIN


func _on_mode_pressed() -> void:
	_selected_game_mode = (
		MODE_CREATIVE if _selected_game_mode == MODE_SURVIVAL else MODE_SURVIVAL
	)
	_mode_button.text = "Game Mode: %s" % (
		"Creative" if _selected_game_mode == MODE_CREATIVE else "Survival"
	)


func _on_play_pressed() -> void:
	if _multiplayer_manager.is_active():
		_multiplayer_manager.leave_room()
	_pending_multiplayer_action = ""
	_selected_world_seed = _seed_from_text(_seed_input.text)
	_start_game()


func _on_host_pressed() -> void:
	if _multiplayer_manager.is_active():
		_multiplayer_manager.leave_room()
	_pending_multiplayer_action = "host"
	_show_view(VIEW_HOST)
	_host_status.text = "Creating room..."
	_room_code_label.text = "----"
	_host_start_button.disabled = true
	var code: String = _multiplayer_manager.create_room()
	if code.is_empty():
		_pending_multiplayer_action = ""
		_host_status.text = "Unable to create a room. Please try again."
		return
	_room_code_label.text = code
	_host_status.text = "Connecting to room..."


func _on_show_join() -> void:
	if _multiplayer_manager.is_active():
		_multiplayer_manager.leave_room()
	_pending_multiplayer_action = ""
	_code_input.clear()
	_join_status.text = "Enter the 4-digit room code"
	_connect_button.disabled = false
	_show_view(VIEW_JOIN)
	_code_input.grab_focus.call_deferred()


func _on_join_pressed() -> void:
	_on_code_submitted(_code_input.text)


func _on_code_submitted(text: String) -> void:
	var code: String = text.strip_edges()
	if code.length() != 4 or not code.is_valid_int():
		_join_status.text = "Enter exactly 4 digits."
		return
	_pending_multiplayer_action = "join"
	_connect_button.disabled = true
	_join_status.text = "Connecting to room %s..." % code
	var started: bool = _multiplayer_manager.join_room(code)
	if not started:
		_pending_multiplayer_action = ""
		_connect_button.disabled = false
		_join_status.text = "Unable to join that room. Please try again."


func _on_room_created(code: String) -> void:
	if _pending_multiplayer_action != "host":
		return
	# Every peer can derive this without an extra network message.
	_selected_world_seed = _seed_from_text("room:" + code)
	_room_code_label.text = code
	_host_status.text = "Room ready"
	_host_start_button.disabled = false


func _on_room_joined(code: String) -> void:
	if _pending_multiplayer_action != "join":
		return
	_selected_world_seed = _seed_from_text("room:" + code)
	_pending_multiplayer_action = ""
	_join_status.text = "Joined room %s" % code
	_start_game()


func _on_connection_failed(_details: String) -> void:
	if _pending_multiplayer_action == "host":
		_host_status.text = "Connection failed. Cancel and try again."
		_room_code_label.text = "----"
		_host_start_button.disabled = true
	elif _pending_multiplayer_action == "join":
		_join_status.text = "Connection failed. Check the code and try again."
		_connect_button.disabled = false
	_pending_multiplayer_action = ""


func _on_multiplayer_cancelled() -> void:
	if _multiplayer_manager.is_active():
		_multiplayer_manager.leave_room()
	_pending_multiplayer_action = ""
	_show_view(VIEW_MAIN)


func _start_game() -> void:
	ProjectSettings.set_setting(RUNTIME_SEED_SETTING, _selected_world_seed)
	ProjectSettings.set_setting(RUNTIME_MODE_SETTING, _selected_game_mode)
	for button: Button in [
		_mode_button,
		_play_button,
		_host_button,
		_join_button,
		_quit_button,
		_host_start_button,
		_host_cancel_button,
		_connect_button,
		_join_cancel_button,
	]:
		button.disabled = true
	var transition: SceneTransitionManager = get_node("/root/SceneTransition") as SceneTransitionManager
	transition.transition_to(MAIN_SCENE)


## Numeric seeds are used directly; words are stable hashed seeds. Leaving the
## field blank creates a fresh seed and the debug panel shows it for later reuse.
func _seed_from_text(text: String) -> int:
	var cleaned: String = text.strip_edges()
	if cleaned.is_empty():
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()
		return rng.randi_range(1, 2147483646)
	if cleaned.is_valid_int():
		return clampi(int(cleaned), -2147483647, 2147483646)
	return cleaned.hash()


func _on_quit_pressed() -> void:
	get_tree().quit()
