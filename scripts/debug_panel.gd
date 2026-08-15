class_name DebugPanel
extends CanvasLayer

## F3-style debug overlay (top-left). Shows FPS, player world position,
## facing direction, chunk info, world stats, and engine performance numbers.
## Toggled with the ` (backtick) / ~ (tilde) key. Collapsed by default,
## showing only a hint line; expanding/collapsing is subtly animated.

const UPDATE_INTERVAL: float = 0.15  # seconds between text refreshes
const TOGGLE_HINT: String = "Press ` or ~ to toggle this panel"
const ANIM_DURATION: float = 0.18

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Margin/Label

var _player: CharacterBody3D
var _world: World
var _accum: float = 0.0
var _expanded: bool = false
var _tween: Tween


func _ready() -> void:
	layer = 10
	visible = true
	_label.text = TOGGLE_HINT
	_panel.scale = Vector2.ONE
	_panel.pivot_offset = Vector2.ZERO


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_QUOTELEFT or key.keycode == KEY_ASCIITILDE:
		_set_expanded(not _expanded)
		get_viewport().set_input_as_handled()


func _set_expanded(expanded: bool) -> void:
	_expanded = expanded
	if _expanded:
		_refresh()
	else:
		_label.text = TOGGLE_HINT
	_animate_pop()


func _animate_pop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_panel.pivot_offset = Vector2.ZERO
	_panel.scale = Vector2(1.0, 0.6)
	_panel.modulate.a = 0.35
	_tween = create_tween().set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_panel, "scale", Vector2.ONE, ANIM_DURATION)
	_tween.tween_property(_panel, "modulate:a", 1.0, ANIM_DURATION)


func _process(delta: float) -> void:
	if not _expanded:
		return
	_accum += delta
	if _accum < UPDATE_INTERVAL:
		return
	_accum = 0.0
	_refresh()


func _refresh() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group("world") as World
		if _world == null:
			for child in get_tree().current_scene.get_children():
				if child is World:
					_world = child
					break

	var lines: Array[String] = []
	lines.append("FPS: %d  (%.2f ms)" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
	])

	if _player != null:
		var p: Vector3 = _player.global_position
		lines.append("XYZ: %.2f / %.2f / %.2f" % [p.x, p.y, p.z])
		lines.append("Block: %d / %d / %d" % [
			int(floor(p.x)), int(floor(p.y)), int(floor(p.z)),
		])
		lines.append("Chunk: %d / %d" % [int(floor(p.x)) >> 4, int(floor(p.z)) >> 4])
		lines.append("Facing: %s (%.1f°)" % [_facing_name(), _yaw_degrees()])
		lines.append("Speed: %.2f m/s" % _player.velocity.length())
		lines.append("On floor: %s" % ("yes" if _player.is_on_floor() else "no"))

	if _world != null:
		lines.append("")
		lines.append("Chunks loaded: %d  (queued: %d)" % [
			_world._loaded.size(), _world._job_queue.size(),
		])
		lines.append("Blocks: %d  (colliders: %d)" % [
			_world._block_types.size(), _world._block_colliders.size(),
		])

	lines.append("")
	lines.append("Draw calls: %d" % int(
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	lines.append("Primitives: %d" % int(
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	lines.append("Video mem: %.1f MB" % (
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))
	lines.append("Static mem: %.1f MB" % (
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
	lines.append("Objects: %d  Nodes: %d" % [
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	])

	lines.append("")
	lines.append("Press ` or ~ to toggle this panel")

	_label.text = "\n".join(lines)


func _yaw_degrees() -> float:
	if _player == null:
		return 0.0
	return wrapf(_player.rotation_degrees.y, -180.0, 180.0)


func _facing_name() -> String:
	if _player == null:
		return "?"
	var fwd: Vector3 = -_player.global_transform.basis.z
	if absf(fwd.x) > absf(fwd.z):
		return "east (+X)" if fwd.x > 0.0 else "west (-X)"
	return "south (+Z)" if fwd.z > 0.0 else "north (-Z)"
