class_name RemotePlayer
extends Node3D

## A networked player avatar. One instance per peer, spawned by the host via
## MultiplayerSpawner.
##
## - Authority is derived from the node name in _enter_tree (deterministic across
##   peers, no networked handoff needed).
## - On the owning peer the avatar is hidden (you already see your own first-
##   person view) and its position is copied from the local Player each frame so
##   the MultiplayerSynchronizer can broadcast it.
## - On remote peers the synchronizer drives position/rotation; we just render
##   the character mesh.

const CHARACTER_SCENE: PackedScene = preload("res://scenes/character.tscn")

var _local_player: Node3D
var _character: Node3D


func _enter_tree() -> void:
    # Name format: "player_<peer_id>". Set authority before the synchronizer
    # configures itself so the broadcaster is correct on every peer.
    var owner_id: int = int(str(name).trim_prefix("player_"))
    set_multiplayer_authority(owner_id)


func _ready() -> void:
    _character = CHARACTER_SCENE.instantiate()
    add_child(_character)

    if is_multiplayer_authority():
        # Find the local Player so we can mirror its world position.
        var players: Array = get_tree().get_nodes_in_group("player")
        if not players.is_empty():
            _local_player = players[0]
        # Hide our own avatar's character mesh — we already see ourselves in FP
        # and the local Player's own Character handles third-person rendering.
        if _character != null:
            _character.visible = false


func _process(_delta: float) -> void:
    if not is_multiplayer_authority():
        return
    if _local_player == null:
        var players: Array = get_tree().get_nodes_in_group("player")
        if not players.is_empty():
            _local_player = players[0]
        if _local_player == null:
            return
    global_position = _local_player.global_position
    rotation.y = _local_player.rotation.y
