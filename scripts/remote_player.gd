class_name RemotePlayer
extends Node3D

## A networked player avatar. One instance per peer, spawned by the host via
## MultiplayerSpawner.
##
## - Authority is derived from the node name in _enter_tree (deterministic across
##   peers, no networked handoff needed).
## - On the owning peer the avatar is hidden and sends compact motion packets.
## - On remote peers packets are interpolated locally and the character mesh
##   animates from the smoothed speed, so relay jitter does not look like 1 FPS.

const CHARACTER_SCENE: PackedScene = preload("res://scenes/character.tscn")
const SEND_RATE: float = 1.0 / 20.0
const TELEPORT_DISTANCE: float = 6.0
const POSITION_LERP_RATE: float = 14.0
const ROTATION_LERP_RATE: float = 16.0
const WALK_SPEED: float = 4.5
const STEP_FREQUENCY: float = 1.4
const SWING_AMP: float = deg_to_rad(35.0)
const ARM_SWING_RATIO: float = 0.8
const CROUCH_POSE_LERP_RATE: float = 14.0
const CROUCH_BODY_DROP: float = 0.28
const CROUCH_TORSO_LEAN_DEG: float = 8.0
const CROUCH_HEAD_FORWARD: float = 0.08
const CROUCH_HIP_FORWARD: float = 0.12
const CROUCH_HIP_DROP: float = 0.14
const CROUCH_KNEE_BEND_DEG: float = 28.0
const CROUCH_ARM_FORWARD_DEG: float = 12.0

var _local_player: Node3D
var _character: Node3D
var _head: Node3D
var _hair: Node3D
var _face: Node3D
var _torso: Node3D
var _left_shoulder: Node3D
var _right_shoulder: Node3D
var _left_hip: Node3D
var _right_hip: Node3D
var _target_position: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _target_speed: float = 0.0
var _target_crouching: bool = false
var _send_accum: float = 0.0
var _walk_phase: float = 0.0
var _last_sent_position: Vector3 = Vector3.ZERO
var _crouch_pose_blend: float = 0.0

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


func _enter_tree() -> void:
    # Name format: "player_<peer_id>". Set authority before network callbacks
    # arrive so the broadcaster is deterministic on every peer.
    var owner_id: int = int(str(name).trim_prefix("player_"))
    set_multiplayer_authority(owner_id)


func _ready() -> void:
    _character = CHARACTER_SCENE.instantiate()
    add_child(_character)
    _head = _character.get_node_or_null("Head")
    _hair = _character.get_node_or_null("Hair")
    _face = _character.get_node_or_null("Face")
    _torso = _character.get_node_or_null("Torso")
    _left_shoulder = _character.get_node_or_null("LeftShoulder")
    _right_shoulder = _character.get_node_or_null("RightShoulder")
    _left_hip = _character.get_node_or_null("LeftHip")
    _right_hip = _character.get_node_or_null("RightHip")
    _cache_character_rest_pose()
    _target_position = global_position
    _target_yaw = rotation.y

    if is_multiplayer_authority():
        var players: Array = get_tree().get_nodes_in_group("player")
        if not players.is_empty():
            _local_player = players[0]
            _last_sent_position = _local_player.global_position
        if _character != null:
            _character.visible = false


func _process(delta: float) -> void:
    if is_multiplayer_authority():
        _mirror_and_send_local_state(delta)
    else:
        _smooth_remote_state(delta)
    _update_walk_animation(delta)


func _mirror_and_send_local_state(delta: float) -> void:
    if _local_player == null:
        var players: Array = get_tree().get_nodes_in_group("player")
        if not players.is_empty():
            _local_player = players[0]
        if _local_player == null:
            return
    global_position = _local_player.global_position
    rotation.y = _local_player.rotation.y
    _target_speed = global_position.distance_to(_last_sent_position) / max(delta, 0.001)
    _target_crouching = (
        _local_player.has_method("is_crouching")
        and bool(_local_player.call("is_crouching"))
    )
    _last_sent_position = global_position

    _send_accum += delta
    if _send_accum < SEND_RATE:
        return
    _send_accum = 0.0
    _rpc_motion_state.rpc(global_position, rotation.y, _target_speed, _target_crouching)


func _smooth_remote_state(delta: float) -> void:
    if global_position.distance_to(_target_position) > TELEPORT_DISTANCE:
        global_position = _target_position
    else:
        var pos_blend: float = clamp(POSITION_LERP_RATE * delta, 0.0, 1.0)
        global_position = global_position.lerp(_target_position, pos_blend)
    var rot_blend: float = clamp(ROTATION_LERP_RATE * delta, 0.0, 1.0)
    rotation.y = lerp_angle(rotation.y, _target_yaw, rot_blend)


func _update_walk_animation(delta: float) -> void:
    if _left_shoulder == null or _right_shoulder == null or _left_hip == null or _right_hip == null:
        return
    var horizontal_speed: float = _target_speed
    if horizontal_speed > 0.2:
        _walk_phase += delta * horizontal_speed * STEP_FREQUENCY
    else:
        _walk_phase = lerp(_walk_phase, 0.0, clamp(delta * 8.0, 0.0, 1.0))
    var swing: float = sin(_walk_phase) * SWING_AMP * clamp(horizontal_speed / WALK_SPEED, 0.0, 1.5)
    _left_hip.rotation.x = swing
    _right_hip.rotation.x = -swing
    _left_shoulder.rotation.x = -swing * ARM_SWING_RATIO
    _right_shoulder.rotation.x = swing * ARM_SWING_RATIO
    _apply_crouch_pose(delta, swing)


func _cache_character_rest_pose() -> void:
    if _character == null or _head == null or _hair == null or _face == null or _torso == null:
        return
    if _left_hip == null or _right_hip == null:
        return
    _character_rest_position = _character.position
    _head_rest_position = _head.position
    _hair_rest_position = _hair.position
    _face_rest_position = _face.position
    _torso_rest_rotation = _torso.rotation
    _head_rest_rotation = _head.rotation
    _hair_rest_rotation = _hair.rotation
    _face_rest_rotation = _face.rotation
    _left_hip_rest_position = _left_hip.position
    _right_hip_rest_position = _right_hip.position


func _apply_crouch_pose(delta: float, walk_swing: float) -> void:
    if _character == null or _head == null or _hair == null or _face == null or _torso == null:
        return
    var target_blend: float = 1.0 if _target_crouching else 0.0
    _crouch_pose_blend = lerp(
        _crouch_pose_blend,
        target_blend,
        clamp(CROUCH_POSE_LERP_RATE * delta, 0.0, 1.0)
    )
    var b: float = _crouch_pose_blend
    var lean: float = deg_to_rad(CROUCH_TORSO_LEAN_DEG) * b
    var knee_bend: float = deg_to_rad(CROUCH_KNEE_BEND_DEG) * b
    var arm_forward: float = deg_to_rad(CROUCH_ARM_FORWARD_DEG) * b

    _character.position = _character_rest_position + Vector3(0.0, -CROUCH_BODY_DROP * b, 0.0)
    _torso.rotation = _torso_rest_rotation + Vector3(lean, 0.0, 0.0)
    _head.position = _head_rest_position + Vector3(0.0, -CROUCH_BODY_DROP * 0.35 * b, -CROUCH_HEAD_FORWARD * b)
    _hair.position = _hair_rest_position + Vector3(0.0, -CROUCH_BODY_DROP * 0.35 * b, -CROUCH_HEAD_FORWARD * b)
    _face.position = _face_rest_position + Vector3(0.0, -CROUCH_BODY_DROP * 0.35 * b, -CROUCH_HEAD_FORWARD * b)
    _head.rotation = _head_rest_rotation + Vector3(lean * 0.5, 0.0, 0.0)
    _hair.rotation = _hair_rest_rotation + Vector3(lean * 0.5, 0.0, 0.0)
    _face.rotation = _face_rest_rotation + Vector3(lean * 0.5, 0.0, 0.0)

    _left_hip.position = _left_hip_rest_position + Vector3(0.0, -CROUCH_HIP_DROP * b, -CROUCH_HIP_FORWARD * b)
    _right_hip.position = _right_hip_rest_position + Vector3(0.0, -CROUCH_HIP_DROP * b, -CROUCH_HIP_FORWARD * b)
    _left_hip.rotation.x = walk_swing - knee_bend
    _right_hip.rotation.x = -walk_swing - knee_bend
    _left_shoulder.rotation.x -= arm_forward
    _right_shoulder.rotation.x -= arm_forward


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_motion_state(pos: Vector3, yaw: float, speed: float, crouching: bool) -> void:
    if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
        return
    _target_position = pos
    _target_yaw = yaw
    _target_speed = speed
    _target_crouching = crouching
