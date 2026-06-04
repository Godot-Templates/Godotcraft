class_name Player
extends CharacterBody3D

## First-person voxel-world player controller.
## WASD = move, hold Ctrl = sprint, Space = jump, mouse = look, Esc = release mouse.

const WALK_SPEED: float = 4.5
const SPRINT_SPEED: float = 7.5
const JUMP_VELOCITY: float = 8.0
const GROUND_ACCEL: float = 12.0
const AIR_ACCEL: float = 3.0
const MOUSE_SENSITIVITY: float = 0.0025
const PITCH_LIMIT: float = deg_to_rad(89.0)

const FP_CAMERA_OFFSET: Vector3 = Vector3.ZERO
const TP_CAMERA_OFFSET: Vector3 = Vector3(0.0, 0.4, 3.5)

const MAX_REACH: float = 4.0

const STEP_FREQUENCY: float = 1.4
const SWING_AMP: float = deg_to_rad(35.0)
const ARM_SWING_RATIO: float = 0.8

const CROUCH_SPEED: float = 1.8
const SPRINT_DOUBLE_TAP_WINDOW: float = 0.3
const STAND_PIVOT_Y: float = 1.6
const CROUCH_PIVOT_Y: float = 1.1
const CROUCH_LERP_RATE: float = 12.0

const BLOCK_MINE_TIME: Dictionary = {
    "dirt": 3.0,
    "grass": 3.0,
    "cobble": 7.0,
    "wood": 4.5,
    "leaves": 0.5,
    "sand": 1.5,
}

const FP_ARM_BOB_FREQ: float = 6.5
const FP_ARM_BOB_AMP_DOWN: float = 0.08
const FP_ARM_BOB_AMP_FORWARD: float = 0.05
const FP_ARM_BOB_RECOVER_RATE: float = 10.0

const CRACK_STAGE_PATHS: Array = [
    "res://assets/generated/crack_stage_0_frame_0.png",
    "res://assets/generated/crack_stage_1_frame_0.png",
    "res://assets/generated/crack_stage_2_frame_0.png",
    "res://assets/generated/crack_stage_3_frame_0.png",
]

@export var block_highlight_path: NodePath
@export var world_path: NodePath
@export var dirt_texture: Texture2D
@export var grass_top_texture: Texture2D
@export var cobble_texture: Texture2D
@export var wood_texture: Texture2D
@export var leaves_texture: Texture2D
@export var sand_texture: Texture2D

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var fp_arm: Node3D = $CameraPivot/Camera3D/FPArm
@onready var held_block: MeshInstance3D = $CameraPivot/Camera3D/FPArm/HeldBlock
@onready var character: Node3D = $Character
@onready var left_shoulder: Node3D = $Character/LeftShoulder
@onready var right_shoulder: Node3D = $Character/RightShoulder
@onready var left_hip: Node3D = $Character/LeftHip
@onready var right_hip: Node3D = $Character/RightHip

var _yaw: float = 0.0
var _pitch: float = 0.0
var _first_person: bool = true
var _walk_phase: float = 0.0
var _block_highlight: Node3D
var _crack_overlay: MeshInstance3D

var _w_was_pressed: bool = false
var _w_last_release_time: float = -10.0
var _sprint_active: bool = false
var _crouching: bool = false

var _world: Node
var _hud: Node
var _mining_target_pos: Vector3i = Vector3i(2147483647, 2147483647, 2147483647)
var _mining_progress: float = 0.0
var _mining_type: String = ""

var _arm_bob_phase: float = 0.0
var _fp_arm_rest: Vector3 = Vector3.ZERO

var _crack_stages: Array[Texture2D] = []
var _current_crack_stage: int = -1


func _ready() -> void:
    add_to_group("player")
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    if block_highlight_path != NodePath(""):
        _block_highlight = get_node_or_null(block_highlight_path)
        if _block_highlight != null:
            _crack_overlay = _block_highlight.get_node_or_null("CrackOverlay")
    if world_path != NodePath(""):
        _world = get_node_or_null(world_path)
    if _world != null and _world.has_method("get_spawn_height"):
        var h: int = _world.get_spawn_height()
        global_position = Vector3(0.0, float(h) + 2.0, 0.0)
    var huds: Array = get_tree().get_nodes_in_group("hud")
    if not huds.is_empty():
        _hud = huds[0]
        if _hud.has_signal("selection_changed"):
            _hud.selection_changed.connect(_on_selection_changed)
    camera_pivot.rotation.x = _pitch
    _apply_perspective()
    _on_selection_changed(0, "")  # ensure held-block starts hidden
    if fp_arm != null:
        _fp_arm_rest = fp_arm.position
    for path in CRACK_STAGE_PATHS:
        if ResourceLoader.exists(path):
            var tex: Texture2D = load(path)
            if tex != null:
                _crack_stages.append(tex)


func _toggle_perspective() -> void:
    _first_person = not _first_person
    _apply_perspective()


func _apply_perspective() -> void:
    camera.position = FP_CAMERA_OFFSET if _first_person else TP_CAMERA_OFFSET
    fp_arm.visible = _first_person
    # Keep the character mesh in the scene either way so its shadow is always cast.
    # In FP we just stop rendering it to the camera by using SHADOWS_ONLY.
    var mode: int = (
        GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
        if _first_person
        else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    )
    _apply_shadow_mode(character, mode)


func _apply_shadow_mode(node: Node, mode: int) -> void:
    for child in node.get_children():
        if child is MeshInstance3D:
            child.cast_shadow = mode
        _apply_shadow_mode(child, mode)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        var motion: InputEventMouseMotion = event
        _yaw -= motion.relative.x * MOUSE_SENSITIVITY
        _pitch -= motion.relative.y * MOUSE_SENSITIVITY
        _pitch = clamp(_pitch, -PITCH_LIMIT, PITCH_LIMIT)
        rotation.y = _yaw
        camera_pivot.rotation.x = _pitch
    elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
        _toggle_perspective()
    elif event is InputEventMouseButton and event.pressed:
        if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        elif event.button_index == MOUSE_BUTTON_RIGHT:
            _try_place_block()


func _physics_process(delta: float) -> void:
    # Always apply gravity, even when input is locked (inventory open, mouse free).
    if not is_on_floor():
        velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) * delta

    var input_locked: bool = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
    if input_locked:
        # Damp horizontal motion to a stop while frozen (inventory/menu).
        velocity.x = move_toward(velocity.x, 0.0, GROUND_ACCEL * delta)
        velocity.z = move_toward(velocity.z, 0.0, GROUND_ACCEL * delta)
        move_and_slide()
        _update_walk_animation(delta)
        _update_block_highlight()
        _stop_mining()
        _update_arm_bob(delta)
        return

    # --- Double-tap W → sprint (replaces Ctrl) ---
    var w_now: bool = Input.is_physical_key_pressed(KEY_W)
    var now: float = Time.get_ticks_msec() / 1000.0
    if w_now and not _w_was_pressed:
        # Fresh W press — if it came soon after the last release, latch sprint.
        if now - _w_last_release_time < SPRINT_DOUBLE_TAP_WINDOW:
            _sprint_active = true
    if not w_now:
        if _w_was_pressed:
            _w_last_release_time = now
        _sprint_active = false
    _w_was_pressed = w_now

    # --- Shift → crouch (slow, no-fall-off-edge, no jump) ---
    _crouching = Input.is_physical_key_pressed(KEY_SHIFT)
    if _crouching:
        _sprint_active = false

    # Lower camera pivot when crouching, lerp back up when standing.
    var pivot_target_y: float = CROUCH_PIVOT_Y if _crouching else STAND_PIVOT_Y
    camera_pivot.position.y = lerp(
        camera_pivot.position.y,
        pivot_target_y,
        clamp(CROUCH_LERP_RATE * delta, 0.0, 1.0)
    )

    # Jump (disabled while crouching for true sneak).
    if not _crouching and Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor():
        velocity.y = JUMP_VELOCITY

    # Movement input.
    var ix: float = 0.0
    var iz: float = 0.0
    if Input.is_physical_key_pressed(KEY_D):
        ix += 1.0
    if Input.is_physical_key_pressed(KEY_A):
        ix -= 1.0
    if Input.is_physical_key_pressed(KEY_S):
        iz += 1.0
    if w_now:
        iz -= 1.0
    var wish_dir: Vector3 = (transform.basis * Vector3(ix, 0.0, iz)).normalized()

    var target_speed: float = WALK_SPEED
    if _crouching:
        target_speed = CROUCH_SPEED
    elif _sprint_active and w_now:
        target_speed = SPRINT_SPEED

    var accel: float = GROUND_ACCEL if is_on_floor() else AIR_ACCEL
    var target_velocity_xz: Vector3 = wish_dir * target_speed
    velocity.x = lerp(velocity.x, target_velocity_xz.x, clamp(accel * delta, 0.0, 1.0))
    velocity.z = lerp(velocity.z, target_velocity_xz.z, clamp(accel * delta, 0.0, 1.0))

    # Edge protection: while crouched & grounded, don't let WASD walk you off a cliff.
    # Test each axis independently so you can still walk parallel to the edge.
    if _crouching and is_on_floor():
        var lookahead: float = max(delta * 2.0, 0.05)
        if absf(velocity.x) > 0.01:
            var pos_x: Vector3 = global_position + Vector3(velocity.x * lookahead, 0.0, 0.0)
            if not _has_floor_at(pos_x):
                velocity.x = 0.0
        if absf(velocity.z) > 0.01:
            var pos_z: Vector3 = global_position + Vector3(0.0, 0.0, velocity.z * lookahead)
            if not _has_floor_at(pos_z):
                velocity.z = 0.0

    move_and_slide()

    _update_walk_animation(delta)
    _update_block_highlight()
    _update_mining(delta)
    _update_arm_bob(delta)


func _update_arm_bob(delta: float) -> void:
    if fp_arm == null:
        return
    if _mining_progress > 0.0:
        _arm_bob_phase += delta * FP_ARM_BOB_FREQ
        # abs(sin) dips downward twice per sin cycle — feels like a rhythmic strike.
        var swing: float = absf(sin(_arm_bob_phase))
        var dip: float = swing * FP_ARM_BOB_AMP_DOWN
        var forward: float = swing * FP_ARM_BOB_AMP_FORWARD
        fp_arm.position = _fp_arm_rest + Vector3(0.0, -dip, -forward)
    else:
        _arm_bob_phase = 0.0
        fp_arm.position = fp_arm.position.lerp(
            _fp_arm_rest, clamp(FP_ARM_BOB_RECOVER_RATE * delta, 0.0, 1.0)
        )


func _has_floor_at(pos: Vector3) -> bool:
    var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
    var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
        pos + Vector3(0.0, 0.4, 0.0),
        pos + Vector3(0.0, -0.3, 0.0),
        0xFFFFFFFF,
        [get_rid()]
    )
    var hit: Dictionary = space.intersect_ray(ray)
    return not hit.is_empty()


func _update_walk_animation(delta: float) -> void:
    var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
    if horizontal_speed > 0.2:
        _walk_phase += delta * horizontal_speed * STEP_FREQUENCY
    else:
        # Smoothly settle limbs back to rest pose.
        _walk_phase = lerp(_walk_phase, 0.0, clamp(delta * 8.0, 0.0, 1.0))
    var t: float = sin(_walk_phase)
    var speed_ratio: float = clamp(horizontal_speed / WALK_SPEED, 0.0, 1.5)
    var swing: float = t * SWING_AMP * speed_ratio
    left_hip.rotation.x = swing
    right_hip.rotation.x = -swing
    # Arms counter-swing relative to same-side leg (natural gait).
    left_shoulder.rotation.x = -swing * ARM_SWING_RATIO
    right_shoulder.rotation.x = swing * ARM_SWING_RATIO


func _update_block_highlight() -> void:
    if _block_highlight == null:
        return
    var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
    var origin: Vector3 = camera.global_position
    var dir: Vector3 = -camera.global_transform.basis.z
    var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
        origin, origin + dir * MAX_REACH, 0xFFFFFFFF, [get_rid()]
    )
    var hit: Dictionary = space.intersect_ray(params)
    if hit.is_empty():
        _block_highlight.visible = false
        return
    # The hit is on a block face; step from the face into the block along -normal
    # and snap to the nearest integer grid cell (blocks are 1m cubes centered on integers).
    var block_center: Vector3 = (hit.position - hit.normal * 0.5).round()
    _block_highlight.global_position = block_center
    _block_highlight.visible = true


func _camera_ray_hit() -> Dictionary:
    var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
    var origin: Vector3 = camera.global_position
    var dir: Vector3 = -camera.global_transform.basis.z
    var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
        origin, origin + dir * MAX_REACH, 0xFFFFFFFF, [get_rid()]
    )
    return space.intersect_ray(params)


func _update_mining(delta: float) -> void:
    if _world == null:
        return
    var mining_held: bool = (
        Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
        and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
    )
    if not mining_held:
        _stop_mining()
        return

    var hit: Dictionary = _camera_ray_hit()
    if hit.is_empty():
        _stop_mining()
        return
    var block_pos: Vector3i = Vector3i((hit.position - hit.normal * 0.5).round())
    var type: String = _world.get_block_type(block_pos)
    if type == "":
        _stop_mining()
        return

    if block_pos != _mining_target_pos:
        _mining_target_pos = block_pos
        _mining_progress = 0.0
        _mining_type = type
    _mining_progress += delta
    var required: float = BLOCK_MINE_TIME.get(type, 5.0)

    if _mining_progress >= required:
        var removed: String = _world.remove_block(block_pos)
        if removed != "":
            _spawn_item_drop(Vector3(block_pos), removed)
        _stop_mining()
        return

    _set_crack_alpha(_mining_progress / required)


func _stop_mining() -> void:
    _mining_target_pos = Vector3i(2147483647, 2147483647, 2147483647)
    _mining_progress = 0.0
    _mining_type = ""
    _set_crack_alpha(0.0)


func _set_crack_alpha(progress: float) -> void:
    if _crack_overlay == null:
        return
    # Don't pop in immediately on the first frame; gives the player a beat of feedback.
    var visible_now: bool = progress > 0.05
    _crack_overlay.visible = visible_now
    if not visible_now:
        _current_crack_stage = -1
        return
    var mesh: Mesh = _crack_overlay.mesh
    if mesh == null:
        return
    var mat: Material = mesh.material if mesh is PrimitiveMesh else mesh.surface_get_material(0)
    if mat is ShaderMaterial:
        var sm: ShaderMaterial = mat
        # Pick the right stage texture for this progress quarter and only swap on change.
        if not _crack_stages.is_empty():
            var stage_count: int = _crack_stages.size()
            var stage: int = clamp(int(progress * stage_count), 0, stage_count - 1)
            if stage != _current_crack_stage:
                _current_crack_stage = stage
                sm.set_shader_parameter("cracks_tex", _crack_stages[stage])
        # Show whichever stage texture is active at full strength.
        sm.set_shader_parameter("progress", 1.0)


func _try_place_block() -> void:
    if _world == null or _hud == null:
        return
    var type: String = _hud.get_selected_type()
    if type == "":
        return
    var hit: Dictionary = _camera_ray_hit()
    if hit.is_empty():
        return
    # Block we hit:
    var hit_block: Vector3 = (hit.position - hit.normal * 0.5).round()
    # New block goes one step out in the hit face's normal direction.
    var new_pos: Vector3i = Vector3i((hit_block + hit.normal).round())
    if _world.has_block(new_pos):
        return
    if _block_intersects_player(new_pos):
        return
    _world.add_block(new_pos, type)
    _hud.consume_selected(1)


func _block_intersects_player(block_pos: Vector3i) -> bool:
    # Treat the player as an AABB roughly matching the capsule.
    var bp: Vector3 = Vector3(block_pos)
    var bp_min: Vector3 = bp - Vector3(0.5, 0.5, 0.5)
    var bp_max: Vector3 = bp + Vector3(0.5, 0.5, 0.5)
    var pp_min: Vector3 = global_position + Vector3(-0.4, 0.0, -0.4)
    var pp_max: Vector3 = global_position + Vector3(0.4, 1.85, 0.4)
    if bp_max.x <= pp_min.x or bp_min.x >= pp_max.x:
        return false
    if bp_max.y <= pp_min.y or bp_min.y >= pp_max.y:
        return false
    if bp_max.z <= pp_min.z or bp_min.z >= pp_max.z:
        return false
    return true


func _spawn_item_drop(world_pos: Vector3, type: String) -> void:
    var drop: ItemDrop = ItemDrop.new()
    drop.block_type = type
    drop.block_texture = _texture_for(type)
    get_parent().add_child(drop)
    drop.global_position = world_pos


func _on_selection_changed(_slot: int, type: String) -> void:
    if held_block == null:
        return
    if type == "":
        held_block.visible = false
        held_block.set_surface_override_material(0, null)
        return
    var tex: Texture2D = _texture_for(type)
    if tex == null:
        held_block.visible = false
        return
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    mat.albedo_texture = tex
    mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    held_block.set_surface_override_material(0, mat)
    held_block.visible = true


func _texture_for(type: String) -> Texture2D:
    match type:
        "dirt":
            return dirt_texture
        "grass":
            return grass_top_texture
        "cobble":
            return cobble_texture
        "wood":
            return wood_texture
        "leaves":
            return leaves_texture
        "sand":
            return sand_texture
    return null
