class_name SceneTransitionManager
extends CanvasLayer

## Persistent scene-change overlay.
##
## Because this node is an autoload, its black backdrop survives scene changes.
## This prevents the renderer's clear color from flashing while the gameplay
## scene performs its initial world generation. A short loading hold followed by
## a smooth fade reveals the fully initialized scene.

const FADE_TO_BLACK_DURATION: float = 0.35
const LOADING_HOLD_DURATION: float = 0.2
const REVEAL_DURATION: float = 0.7
const DOT_INTERVAL: float = 0.35

var _backdrop: ColorRect
var _loading_label: Label
var _loading_group: VBoxContainer
var _is_transitioning: bool = false
var _dot_timer: float = 0.0
var _dot_count: int = 1


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	visible = false


func _process(delta: float) -> void:
	if not _is_transitioning:
		return
	_dot_timer += delta
	if _dot_timer >= DOT_INTERVAL:
		_dot_timer = 0.0
		_dot_count = _dot_count % 3 + 1
		_loading_label.text = "Loading" + ".".repeat(_dot_count)
	var pulse: float = 0.92 + sin(Time.get_ticks_msec() * 0.004) * 0.08
	_loading_label.modulate.a = pulse


func transition_to(scene_path: String) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_dot_timer = 0.0
	_dot_count = 1
	_loading_label.text = "Loading."
	visible = true
	_backdrop.modulate.a = 0.0
	_loading_group.modulate.a = 0.0

	var cover_tween: Tween = create_tween().set_parallel(true)
	cover_tween.tween_property(
		_backdrop, "modulate:a", 1.0, FADE_TO_BLACK_DURATION
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	cover_tween.tween_property(
		_loading_group, "modulate:a", 1.0, FADE_TO_BLACK_DURATION * 0.75
	).set_delay(FADE_TO_BLACK_DURATION * 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await cover_tween.finished
	# Ensure one completely black frame is presented before scene initialization
	# can block the main thread.
	await get_tree().process_frame

	var error: Error = get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Unable to change scene to %s (error %s)" % [scene_path, error])
		_reset_overlay()
		return

	# Let the new scene finish _ready() and render behind the persistent overlay.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(LOADING_HOLD_DURATION).timeout

	var loading_tween: Tween = create_tween()
	loading_tween.tween_property(_loading_group, "modulate:a", 0.0, 0.15)
	await loading_tween.finished

	var reveal_tween: Tween = create_tween()
	reveal_tween.tween_property(
		_backdrop, "modulate:a", 0.0, REVEAL_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await reveal_tween.finished
	_reset_overlay()


func _build_overlay() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color.BLACK
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.name = "LoadingCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_loading_group = VBoxContainer.new()
	_loading_group.name = "LoadingGroup"
	_loading_group.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading_group.add_theme_constant_override("separation", 10)
	center.add_child(_loading_group)

	_loading_label = Label.new()
	_loading_label.name = "LoadingLabel"
	_loading_label.text = "Loading."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 24)
	_loading_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96, 1.0))
	_loading_group.add_child(_loading_label)

	var hint: Label = Label.new()
	hint.name = "Hint"
	hint.text = "Building your world"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.62, 1.0))
	_loading_group.add_child(hint)


func _reset_overlay() -> void:
	_is_transitioning = false
	visible = false
	_backdrop.modulate.a = 1.0
	_loading_group.modulate.a = 1.0
