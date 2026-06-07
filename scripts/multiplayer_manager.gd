class_name MultiplayerManager
extends Node

## Multiplayer room manager built on Ziva's WebSocket relay.
##
## - create_room() generates a fresh 4-digit code, connects to the relay, and
##   returns the code so the UI can show it.
## - join_room(code) connects to an existing room by its 4-digit code.
## - Host-authority spawner pattern (host = lowest real peer id, per Ziva docs)
##   spawns a small RemotePlayer node per peer; each peer drives its own avatar
##   while compact RPC state packets keep remote avatars smooth.

signal room_created(code: String)
signal room_joined(code: String)
signal connection_failed(details: String)
signal disconnected

const REMOTE_PLAYER_SCRIPT: Script = preload("res://scripts/remote_player.gd")
const USER_ID_SETTING: String = "ziva/multiplayer/user_id"
const GAME_ID_SETTING: String = "ziva/multiplayer/game_id"
const RELAY_URL_SETTING: String = "ziva/multiplayer/relay_url"

var _spawner: MultiplayerSpawner
var _players_root: Node
var _current_code: String = ""
var _host: int = 0
var _last_connection_debug: String = ""
var _pending_peer: WebSocketMultiplayerPeer
var _pending_room_code: String = ""
var _connect_started_msec: int = 0
var _last_peer_status: int = MultiplayerPeer.CONNECTION_DISCONNECTED


func _ready() -> void:
    add_to_group("multiplayer_manager")

    _players_root = Node.new()
    _players_root.name = "RemotePlayers"
    add_child(_players_root)

    _spawner = MultiplayerSpawner.new()
    _spawner.name = "Spawner"
    add_child(_spawner)
    _spawner.spawn_path = _spawner.get_path_to(_players_root)
    _spawner.spawn_function = Callable(self, "_spawn_remote_player")

    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
    if _pending_peer == null:
        return
    var status: int = _pending_peer.get_connection_status()
    if status != _last_peer_status:
        _last_peer_status = status
        _log_connection_debug(
            "peer status -> %s after %d ms"
            % [_connection_status_name(status), Time.get_ticks_msec() - _connect_started_msec]
        )


# ------------------------- public API -------------------------

func is_active() -> bool:
    var peer: MultiplayerPeer = multiplayer.multiplayer_peer
    if peer == null:
        return false
    if peer is OfflineMultiplayerPeer:
        return false
    return true


func get_room_code() -> String:
    return _current_code


func get_last_connection_debug() -> String:
    return _last_connection_debug


func sync_block_added(pos: Vector3i, type: String) -> void:
    if not is_active():
        return
    _rpc_apply_block_edit.rpc(pos.x, pos.y, pos.z, type, true)


func sync_block_removed(pos: Vector3i) -> void:
    if not is_active():
        return
    _rpc_apply_block_edit.rpc(pos.x, pos.y, pos.z, "", false)


func create_room() -> String:
    var code: String = _generate_code()
    if not _connect_to_relay(code):
        return ""
    _current_code = code
    return code


func join_room(code: String) -> bool:
    if code.length() != 4 or not code.is_valid_int():
        return false
    if not _connect_to_relay(code):
        return false
    _current_code = code
    return true


func leave_room() -> void:
    multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
    _clear_avatars()
    _current_code = ""
    _host = 0
    _pending_peer = null
    _pending_room_code = ""


# ------------------------- relay connection -------------------------

func _generate_code() -> String:
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.randomize()
    return "%04d" % rng.randi_range(0, 9999)


func _connect_to_relay(room_code: String) -> bool:
    var user_id: String = ProjectSettings.get_setting(USER_ID_SETTING, "")
    var game_id: String = ProjectSettings.get_setting(GAME_ID_SETTING, "")
    var relay_url: String = ProjectSettings.get_setting(RELAY_URL_SETTING, "")
    _last_connection_debug = ""
    _pending_peer = null
    _pending_room_code = room_code
    if user_id.is_empty() or game_id.is_empty() or relay_url.is_empty():
        _last_connection_debug = (
            "Missing Ziva multiplayer settings. %s=%s, %s=%s, %s=%s."
            % [
                USER_ID_SETTING,
                _present_or_missing(user_id),
                GAME_ID_SETTING,
                _present_or_missing(game_id),
                RELAY_URL_SETTING,
                _present_or_missing(relay_url),
            ]
        )
        push_error("Ziva multiplayer: %s" % _last_connection_debug)
        return false
    var url: String = "%s/r/%s?u=%s&g=%s&v=1" % [relay_url, room_code, user_id, game_id]
    var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
    var err: int = peer.create_client(url)
    if err != OK:
        _last_connection_debug = (
            "WebSocketMultiplayerPeer.create_client failed: %s (%d). URL: %s"
            % [error_string(err), err, _debug_url(relay_url, room_code, user_id, game_id)]
        )
        push_error("Ziva multiplayer: %s" % _last_connection_debug)
        return false
    _pending_peer = peer
    _connect_started_msec = Time.get_ticks_msec()
    _last_peer_status = peer.get_connection_status()
    _last_connection_debug = (
        "Connecting to relay. URL: %s. Settings: %s=%s, %s=%s, %s=%s. Initial status: %s."
        % [
            _debug_url(relay_url, room_code, user_id, game_id),
            USER_ID_SETTING,
            _redacted_value(user_id),
            GAME_ID_SETTING,
            _redacted_value(game_id),
            RELAY_URL_SETTING,
            relay_url,
            _connection_status_name(_last_peer_status),
        ]
    )
    _log_connection_debug(_last_connection_debug)
    multiplayer.multiplayer_peer = peer
    return true


func _present_or_missing(value: String) -> String:
    return "missing" if value.is_empty() else "present"


func _redacted_value(value: String) -> String:
    if value.is_empty():
        return "missing"
    if value.length() <= 8:
        return "present(length=%d)" % value.length()
    return "present(length=%d, suffix=%s)" % [value.length(), value.right(4)]


func _debug_url(relay_url: String, room_code: String, user_id: String, game_id: String) -> String:
    return (
        "%s/r/%s?u=<%s>&g=<%s>&v=1"
        % [relay_url, room_code, _redacted_value(user_id), _redacted_value(game_id)]
    )


func _diagnose_url(relay_url: String, user_id: String, game_id: String) -> String:
    var http_url: String = relay_url
    if http_url.begins_with("wss://"):
        http_url = "https://%s" % http_url.substr(6)
    elif http_url.begins_with("ws://"):
        http_url = "http://%s" % http_url.substr(5)
    return (
        "%s/diagnose?u=%s&g=%s&v=1"
        % [http_url, user_id.uri_encode(), game_id.uri_encode()]
    )


func _connection_status_name(status: int) -> String:
    match status:
        MultiplayerPeer.CONNECTION_DISCONNECTED:
            return "DISCONNECTED"
        MultiplayerPeer.CONNECTION_CONNECTING:
            return "CONNECTING"
        MultiplayerPeer.CONNECTION_CONNECTED:
            return "CONNECTED"
        _:
            return "UNKNOWN(%d)" % status


func _log_connection_debug(message: String) -> void:
    print("[Multiplayer] %s" % message)


func _diagnose_relay_failure(relay_url: String, user_id: String, game_id: String) -> String:
    if relay_url.is_empty() or user_id.is_empty() or game_id.is_empty():
        return ""

    var req: HTTPRequest = HTTPRequest.new()
    req.timeout = 5.0
    add_child(req)
    var err: int = req.request(_diagnose_url(relay_url, user_id, game_id))
    if err != OK:
        req.queue_free()
        return "Relay diagnostic request failed to start: %s (%d)." % [error_string(err), err]

    var result: Array = await req.request_completed
    req.queue_free()

    var request_result: int = int(result[0])
    var status_code: int = int(result[1])
    var body: PackedByteArray = result[3]
    if request_result != HTTPRequest.RESULT_SUCCESS:
        return "Relay diagnostic request failed: %s (%d)." % [
            _http_request_result_name(request_result),
            request_result,
        ]

    var text: String = body.get_string_from_utf8()
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        return "Relay diagnostic returned HTTP %d but the response was not valid JSON." % status_code

    var data: Dictionary = parsed
    var message: String = str(data.get("message", "")).strip_edges()
    var reason: String = str(data.get("reason", "")).strip_edges()
    if message.is_empty():
        return "Relay diagnostic returned HTTP %d with reason: %s." % [
            status_code,
            reason if not reason.is_empty() else "unknown",
        ]

    if reason.is_empty() or reason == "ok":
        return message
    return "%s (%s)" % [message, reason]


func _http_request_result_name(result: int) -> String:
    match result:
        HTTPRequest.RESULT_SUCCESS:
            return "SUCCESS"
        HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
            return "CHUNKED_BODY_SIZE_MISMATCH"
        HTTPRequest.RESULT_CANT_CONNECT:
            return "CANT_CONNECT"
        HTTPRequest.RESULT_CANT_RESOLVE:
            return "CANT_RESOLVE"
        HTTPRequest.RESULT_CONNECTION_ERROR:
            return "CONNECTION_ERROR"
        HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
            return "TLS_HANDSHAKE_ERROR"
        HTTPRequest.RESULT_NO_RESPONSE:
            return "NO_RESPONSE"
        HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
            return "BODY_SIZE_LIMIT_EXCEEDED"
        HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
            return "BODY_DECOMPRESS_FAILED"
        HTTPRequest.RESULT_REQUEST_FAILED:
            return "REQUEST_FAILED"
        HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
            return "DOWNLOAD_FILE_CANT_OPEN"
        HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
            return "DOWNLOAD_FILE_WRITE_ERROR"
        HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
            return "REDIRECT_LIMIT_REACHED"
        HTTPRequest.RESULT_TIMEOUT:
            return "TIMEOUT"
        _:
            return "UNKNOWN"


# ------------------------- host election (Ziva docs pattern) -------------------------

func _real_peers() -> Array:
    var out: Array = []
    for p in multiplayer.get_peers():
        if int(p) > 1:
            out.append(int(p))
    return out


# Host = lowest real peer id. include_self_floor lets the caller exclude `me`
# from the candidate set during the connect burst — at that instant
# get_peers() may not yet list the lower peers the relay is about to deliver,
# and claiming self as authority there would make this peer REJECT the real
# host's SPAWN with ERR_UNAUTHORIZED until it caught up.
func _refresh_host(include_self_floor: bool = true) -> void:
    var cands: Array = _real_peers()
    var me: int = multiplayer.get_unique_id()
    if include_self_floor and me > 1:
        cands.append(me)
    cands.sort()
    # Never drop a known host to 0 on a transient empty view — only adopt a
    # new one when we have a candidate.
    if cands.size() > 0:
        _host = int(cands[0])
        set_multiplayer_authority(_host)
        _spawner.set_multiplayer_authority(_host)


func _i_am_host() -> bool:
    return multiplayer.get_unique_id() == _host and _host > 0


func _host_spawn(id: int) -> void:
    if not _i_am_host() or id <= 1:
        return
    if _players_root.has_node("player_%d" % id):
        return
    _spawner.spawn(id)


func _host_spawn_all() -> void:
    if not _i_am_host():
        return
    _host_spawn(multiplayer.get_unique_id())
    for id in _real_peers():
        _host_spawn(id)


func _world() -> Node:
    var scene: Node = get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("World")


func _send_world_snapshot_to(peer_id: int) -> void:
    if not _i_am_host() or peer_id <= 1:
        return
    var world: Node = _world()
    if world == null or not world.has_method("get_block_snapshot"):
        return
    var snapshot: Array = world.get_block_snapshot()
    _rpc_apply_world_snapshot.rpc_id(peer_id, snapshot)


func _clear_avatars() -> void:
    for child in _players_root.get_children():
        child.queue_free()


# ------------------------- multiplayer signal handlers -------------------------

func _on_connected_to_server() -> void:
    # id 2 is the ONLY id that provably has no lower peer, so it is the only
    # peer that may treat itself as the host floor on connect (and self-spawn).
    # Every other peer waits to learn the roster before it knows the host.
    var me: int = multiplayer.get_unique_id()
    _log_connection_debug(
        "connected_to_server after %d ms. unique_id=%d, peers=%s"
        % [Time.get_ticks_msec() - _connect_started_msec, me, str(multiplayer.get_peers())]
    )
    _pending_peer = null
    _pending_room_code = ""
    _refresh_host(me == 2)
    room_joined.emit(_current_code)
    if me == 2:
        room_created.emit(_current_code)
        _host_spawn_all()
    elif _host > 0:
        _rpc_request_world_snapshot.rpc_id(_host)


func _on_peer_connected(id: int) -> void:
    if id <= 1:
        return
    _refresh_host()
    _host_spawn_all()
    if _i_am_host():
        _send_world_snapshot_to(id)


func _on_peer_disconnected(id: int) -> void:
    # Reactive failover: when any peer drops, recompute the host from the
    # roster (now authoritative). If that makes US the new lowest peer, we
    # adopt the spawner and re-spawn everyone still present.
    if _i_am_host() and _players_root.has_node("player_%d" % id):
        _players_root.get_node("player_%d" % id).queue_free()
    _refresh_host()
    if _i_am_host():
        if _players_root.has_node("player_%d" % id):
            _players_root.get_node("player_%d" % id).queue_free()
        _host_spawn_all()


func _on_connection_failed() -> void:
    var elapsed: int = Time.get_ticks_msec() - _connect_started_msec if _connect_started_msec > 0 else 0
    var status: String = "unavailable"
    if _pending_peer != null:
        status = _connection_status_name(_pending_peer.get_connection_status())
    var room_code: String = _pending_room_code
    var user_id: String = ProjectSettings.get_setting(USER_ID_SETTING, "")
    var game_id: String = ProjectSettings.get_setting(GAME_ID_SETTING, "")
    var relay_url: String = ProjectSettings.get_setting(RELAY_URL_SETTING, "")
    var fallback_details: String = (
        "Relay handshake failed after %d ms. Last peer status: %s. Room: %s. "
        + "Likely causes: relay rejected the WebSocket upgrade because multiplayer is disabled "
        + "for the account/project, the account tier or bandwidth cap blocks relay use, "
        + "the relay URL is wrong, or local network/TLS/WebSocket access is blocked."
    ) % [elapsed, status, room_code]
    multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
    _current_code = ""
    _host = 0
    _pending_peer = null
    _pending_room_code = ""

    var diagnostic: String = await _diagnose_relay_failure(relay_url, user_id, game_id)
    if diagnostic.is_empty():
        _last_connection_debug = fallback_details
    else:
        _last_connection_debug = (
            "Relay handshake failed after %d ms. Last peer status: %s. Room: %s. %s"
            % [elapsed, status, room_code, diagnostic]
        )

    push_error("Ziva multiplayer: %s" % _last_connection_debug)
    connection_failed.emit(_last_connection_debug)


func _on_server_disconnected() -> void:
    _log_connection_debug("server_disconnected while in room %s" % _current_code)
    disconnected.emit()
    multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
    _clear_avatars()
    _current_code = ""
    _host = 0
    _pending_peer = null
    _pending_room_code = ""


# ------------------------- spawn function -------------------------

func _spawn_remote_player(data: Variant) -> Node:
    var id: int = int(data)
    var avatar: Node3D = Node3D.new()
    avatar.name = "player_%d" % id
    avatar.set_script(REMOTE_PLAYER_SCRIPT)
    return avatar


@rpc("any_peer", "call_remote", "reliable")
func _rpc_apply_block_edit(x: int, y: int, z: int, type: String, add: bool) -> void:
    var world: Node = _world()
    if world == null or not world.has_method("apply_block_edit"):
        return
    world.apply_block_edit(Vector3i(x, y, z), type, add)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_world_snapshot() -> void:
    if not _i_am_host():
        return
    var requester: int = multiplayer.get_remote_sender_id()
    _send_world_snapshot_to(requester)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_apply_world_snapshot(snapshot: Array) -> void:
    if multiplayer.get_remote_sender_id() != _host:
        return
    var world: Node = _world()
    if world == null or not world.has_method("apply_block_snapshot"):
        return
    world.apply_block_snapshot(snapshot)
