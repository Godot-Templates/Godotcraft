class_name Player
extends CharacterBody3D

## First-person voxel-world player controller.
## WASD = move, hold Ctrl = sprint, Space = jump, mouse = look, Esc = release mouse.

const WALK_SPEED: float = 4.5
const SPRINT_SPEED: float = 7.5
const JUMP_VELOCITY: float = 7.75
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
const CROUCH_POSE_LERP_RATE: float = 14.0
const CROUCH_BODY_DROP: float = 0.28
const CROUCH_TORSO_LEAN_DEG: float = 8.0
const CROUCH_HEAD_FORWARD: float = 0.08
const CROUCH_HIP_FORWARD: float = 0.12
const CROUCH_HIP_DROP: float = 0.14
const CROUCH_KNEE_BEND_DEG: float = 28.0
const CROUCH_ARM_FORWARD_DEG: float = 12.0

const BLOCK_MINE_TIME: Dictionary = {
    "dirt": 3.0,
    "grass": 3.0,
    "cobble": 2.5,
    "wood": 4.5,
    "leaves": 0.5,
    "sand": 1.5,
}

const FP_ARM_BOB_FREQ: float = 8.0
const FP_ARM_BOB_AMP_UP: float = 0.04
const FP_ARM_BOB_AMP_FORWARD: float = 0.03
# Positive pitch rotates the arm's forward tip UP, so each strike is a vertical
# sweep around the wrist pivot — the rotation alone naturally swings the hand
# up + slightly forward, the way Minecraft's swing arcs.
const FP_ARM_BOB_PITCH_DEG: float = 42.0
const FP_ARM_BOB_RECOVER_RATE: float = 14.0

# A quick jab when the player left-clicks but isn't mining a block.
# Mostly rotation — the hand sweeps UP in a short arc, not outward.
const PUNCH_DURATION: float = 0.18
const PUNCH_FORWARD: float = 0.04
const PUNCH_UP: float = 0.06
const PUNCH_PITCH_DEG: float = 60.0
# How far the third-person right shoulder swings forward on a punch/mining strike.
const TP_PUNCH_SHOULDER_DEG: float = 85.0
const TP_MINING_SHOULDER_DEG: float = 55.0

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
@onready var head: MeshInstance3D = $Character/Head
@onready var hair: MeshInstance3D = $Character/Hair
@onready var face: MeshInstance3D = $Character/Face
@onready var torso: MeshInstance3D = $Character/Torso
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
var _crouch_pose_blend: float = 0.0

var _world: Node
var _hud: Node
var _multiplayer_mgr: Node
var _mining_target_pos: Vector3i = Vector3i(2147483647, 2147483647, 2147483647)
var _mining_progress: float = 0.0
var _mining_type: String = ""

var _arm_bob_phase: float = 0.0
var _fp_arm_rest: Vector3 = Vector3.ZERO
var _fp_arm_rest_rot: Vector3 = Vector3.ZERO
var _punch_time: float = 0.0

var _crack_stages: Array[Texture2D] = []
var _current_crack_stage: int = -1

var _character_rest_position: Vector3 = Vector3.ZERO
var _head_rest_position: Vector3 = Vector3.ZERO
var _hair_rest_position: Vector3 = Vector3.ZERO
var _face_rest_position: Vector3 = Vector3.ZERO
var _torso_rest_rotation: Vector3 = Vector3.ZERO
var _head_rest_rotation: Vector3 = Vector3.ZERO
var _hair_rest_rotation: Vector3 = Vector3.ZERO
var _face_rest_rotation: Vector3 = Vector3.ZERO
var _left_hip_rest_position: Vector3 = Vector3.ZERO
var _right_hip_rest_position: Vector3 = Vector3.ZERO


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
    var managers: Array = get_tree().get_nodes_in_group("multiplayer_manager")
    if not managers.is_empty():
        _multiplayer_mgr = managers[0]
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
        _fp_arm_rest_rot = fp_arm.rotation
    _cache_character_rest_pose()
    for path in CRACK_STAGE_PATHS:
        if ResourceLoader.exists(path):
            var tex: Texture2D = load(path)
            if tex != null:
                _crack_stages.append(tex)


func _cache_character_rest_pose() -> void:
    _character_rest_position = character.position
    _head_rest_position = head.position
    _hair_rest_position = hair.position
    _face_rest_position = face.position
    _torso_rest_rotation = torso.rotation
    _head_rest_rotation = head.rotation
    _hair_rest_rotation = hair.rotation
    _face_rest_rotation = face.rotation
    _left_hip_rest_position = left_hip.position
    _right_hip_rest_position = right_hip.position


func _toggle_perspective() -> void:
    _first_person = not _first_person
    _apply_perspective()


func _open_settings_menu() -> void:
    var menus: Array = get_tree().get_nodes_in_group("settings_menu")
    if menus.is_empty():
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        return
    var menu: Node = menus[0]
    if menu.has_method("is_open") and menu.is_open():
        return
    if menu.has_method("open"):
        menu.open()


func _is_settings_menu_open() -> bool:
    var menus: Array = get_tree().get_nodes_in_group("settings_menu")
    if menus.is_empty():
        return false
    var menu: Node = menus[0]
    if menu.has_method("is_open"):
        return menu.is_open()
    return false


func is_crouching() -> bool:
    return _crouching


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
        _open_settings_menu()
    elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
        _toggle_perspective()
    elif event is InputEventMouseButton and event.pressed:
        var inv_open: bool = _hud != null and _hud.has_method("is_inventory_open") and _hud.is_inventory_open()
        var settings_open: bool = _is_settings_menu_open()
        if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
            # Don't re-capture while the inventory or settings menu owns the
            # mouse — those overlays need their own clicks.
            if not inv_open and not settings_open:
                Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        elif event.button_index == MOUSE_BUTTON_RIGHT:
            _try_place_block()
        elif event.button_index == MOUSE_BUTTON_LEFT:
            # Every left-click throws a punch; mining bob overrides it while held on a block.
            _punch_time = PUNCH_DURATION


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
    # Always count down the punch timer so it expires even when overridden by mining.
    if _punch_time > 0.0:
        _punch_time = max(0.0, _punch_time - delta)

    if _mining_progress > 0.0:
        _arm_bob_phase += delta * FP_ARM_BOB_FREQ
        # abs(sin) peaks twice per sin cycle — each peak is a rhythmic strike that
        # rises forward+up rather than dipping below rest.
        var swing: float = absf(sin(_arm_bob_phase))
        var rise: float = swing * FP_ARM_BOB_AMP_UP
        var forward: float = swing * FP_ARM_BOB_AMP_FORWARD
        fp_arm.position = _fp_arm_rest + Vector3(0.0, rise, -forward)
        # Positive X rotation rotates the forward tip UP, so the hand stays
        # aimed straight ahead rather than pointing at the floor.
        fp_arm.rotation = _fp_arm_rest_rot + Vector3(
            swing * deg_to_rad(FP_ARM_BOB_PITCH_DEG), 0.0, 0.0
        )
    elif _punch_time > 0.0:
        # 0 → 1 → 0 arc across the punch duration.
        var t: float = 1.0 - (_punch_time / PUNCH_DURATION)
        var arc: float = sin(t * PI)
        fp_arm.position = _fp_arm_rest + Vector3(0.0, arc * PUNCH_UP, -arc * PUNCH_FORWARD)
        fp_arm.rotation = _fp_arm_rest_rot + Vector3(
            arc * deg_to_rad(PUNCH_PITCH_DEG), 0.0, 0.0
        )
        _arm_bob_phase = 0.0
    else:
        _arm_bob_phase = 0.0
        var blend: float = clamp(FP_ARM_BOB_RECOVER_RATE * delta, 0.0, 1.0)
        fp_arm.position = fp_arm.position.lerp(_fp_arm_rest, blend)
        fp_arm.rotation = fp_arm.rotation.lerp(_fp_arm_rest_rot, blend)


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

    _apply_crouch_pose(delta, swing)

    # In third-person, also play the punch / mining swing on the real right arm
    # so the click is visible in R mode.
    if not _first_person:
        if _mining_progress > 0.0:
            var ms: float = absf(sin(_arm_bob_phase))
            right_shoulder.rotation.x += ms * deg_to_rad(TP_MINING_SHOULDER_DEG)
        elif _punch_time > 0.0:
            var pt: float = 1.0 - (_punch_time / PUNCH_DURATION)
            var parc: float = sin(pt * PI)
            right_shoulder.rotation.x += parc * deg_to_rad(TP_PUNCH_SHOULDER_DEG)


func _apply_crouch_pose(delta: float, walk_swing: float) -> void:
    var target_blend: float = 1.0 if _crouching else 0.0
    _crouch_pose_blend = lerp(
        _crouch_pose_blend,
        target_blend,
        clamp(CROUCH_POSE_LERP_RATE * delta, 0.0, 1.0)
    )
    var b: float = _crouch_pose_blend
    var lean: float = deg_to_rad(CROUCH_TORSO_LEAN_DEG) * b
    var knee_bend: float = deg_to_rad(CROUCH_KNEE_BEND_DEG) * b
    var arm_forward: float = deg_to_rad(CROUCH_ARM_FORWARD_DEG) * b

    character.position = _character_rest_position + Vector3(0.0, -CROUCH_BODY_DROP * b, 0.0)
    torso.rotation = _torso_rest_rotation + Vector3(lean, 0.0, 0.0)
    head.position = _head_rest_position + Vector3(0.0, -CROUCH_BODY_DROP * 0.35 * b, -CROUCH_HEAD_FORWARD * b)
    hair.position = _hair_rest_position + Vector3(0.0, -CROUCH_BODY_DROP * 0.35 * b, -CROUCH_HEAD_FORWARD * b)
    face.position = _face_rest_position + Vector3(0.0, -CROUCH_BODY_DROP * 0.35 * b, -CROUCH_HEAD_FORWARD * b)
    head.rotation = _head_rest_rotation + Vector3(lean * 0.5, 0.0, 0.0)
    hair.rotation = _hair_rest_rotation + Vector3(lean * 0.5, 0.0, 0.0)
    face.rotation = _face_rest_rotation + Vector3(lean * 0.5, 0.0, 0.0)

    left_hip.position = _left_hip_rest_position + Vector3(0.0, -CROUCH_HIP_DROP * b, -CROUCH_HIP_FORWARD * b)
    right_hip.position = _right_hip_rest_position + Vector3(0.0, -CROUCH_HIP_DROP * b, -CROUCH_HIP_FORWARD * b)
    left_hip.rotation.x = walk_swing - knee_bend
    right_hip.rotation.x = -walk_swing - knee_bend
    left_shoulder.rotation.x -= arm_forward
    right_shoulder.rotation.x -= arm_forward


func _update_block_highlight() -> void:
    if _block_highlight == null:
        return
    var hit: Dictionary = _camera_ray_hit()
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
    # Reach is measured from the player's eye (camera pivot), not from the camera
    # itself. In third-person the camera is offset behind the player, so extend
    # the ray by that offset and then reject hits that are farther than MAX_REACH
    # from the player. This keeps the crosshair aiming correctly in R mode while
    # the player's "arm length" stays consistent.
    var eye_pos: Vector3 = camera_pivot.global_position
    var cam_offset: float = origin.distance_to(eye_pos)
    var ray_length: float = MAX_REACH + cam_offset
    var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
        origin, origin + dir * ray_length, 0xFFFFFFFF, [get_rid()]
    )
    var hit: Dictionary = space.intersect_ray(params)
    if hit.is_empty():
        return hit
    if hit.position.distance_to(eye_pos) > MAX_REACH:
        return {}
    return hit


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
            _sync_block_removed(block_pos)
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
    if _world.add_block(new_pos, type):
        _sync_block_added(new_pos, type)
        _hud.consume_selected(1)


func _sync_block_added(pos: Vector3i, type: String) -> void:
    if _multiplayer_mgr == null:
        return
    if _multiplayer_mgr.has_method("sync_block_added"):
        _multiplayer_mgr.sync_block_added(pos, type)


func _sync_block_removed(pos: Vector3i) -> void:
    if _multiplayer_mgr == null:
        return
    if _multiplayer_mgr.has_method("sync_block_removed"):
        _multiplayer_mgr.sync_block_removed(pos)


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
