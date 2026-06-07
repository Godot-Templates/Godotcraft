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

var _local_player: Node3D
var _character: Node3D
var _left_shoulder: Node3D
var _right_shoulder: Node3D
var _left_hip: Node3D
var _right_hip: Node3D
var _target_position: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _target_speed: float = 0.0
var _send_accum: float = 0.0
var _walk_phase: float = 0.0
var _last_sent_position: Vector3 = Vector3.ZERO


func _enter_tree() -> void:
    # Name format: "player_<peer_id>". Set authority before network callbacks
    # arrive so the broadcaster is deterministic on every peer.
    var owner_id: int = int(str(name).trim_prefix("player_"))
    set_multiplayer_authority(owner_id)


func _ready() -> void:
    _character = CHARACTER_SCENE.instantiate()
    add_child(_character)
    _left_shoulder = _character.get_node_or_null("LeftShoulder")
    _right_shoulder = _character.get_node_or_null("RightShoulder")
    _left_hip = _character.get_node_or_null("LeftHip")
    _right_hip = _character.get_node_or_null("RightHip")
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
    _last_sent_position = global_position

    _send_accum += delta
    if _send_accum < SEND_RATE:
        return
    _send_accum = 0.0
    _rpc_motion_state.rpc(global_position, rotation.y, _target_speed)


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


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_motion_state(pos: Vector3, yaw: float, speed: float) -> void:
    if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
        return
    _target_position = pos
    _target_yaw = yaw
    _target_speed = speed
