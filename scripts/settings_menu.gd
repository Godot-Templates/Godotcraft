class_name SettingsMenu
extends CanvasLayer

## Pause / settings overlay. Opens when the player presses Esc. Surfaces three
## actions: Back to Game, Create Multiplayer Room, Join Multiplayer Room.
##
## - Create generates a fresh 4-digit code via MultiplayerManager and displays
##   it so the host can share it.
## - Join prompts for a code and connects to that room.

signal opened
signal closed

const PANEL_WIDTH: float = 380.0
const BTN_HEIGHT: float = 46.0

const VIEW_MAIN: String = "main"
const VIEW_CODE: String = "code"
const VIEW_JOIN: String = "join"
const VIEW_STATUS: String = "status"

var _overlay: ColorRect
var _panel: PanelContainer
var _vbox: VBoxContainer
var _multiplayer_mgr: Node
var _is_open: bool = false
var _view: String = VIEW_MAIN
# What we were attempting when the relay handshake started — drives the
# message shown on connection_failed. "" = no pending action.
var _pending_action: String = ""


func _enter_tree() -> void:
    add_to_group("settings_menu")


func _ready() -> void:
    layer = 50
    _build_ui()
    visible = false
    var mgrs: Array = get_tree().get_nodes_in_group("multiplayer_manager")
    if not mgrs.is_empty():
        _multiplayer_mgr = mgrs[0]
        _multiplayer_mgr.room_created.connect(_on_room_created)
        _multiplayer_mgr.room_joined.connect(_on_room_joined)
        _multiplayer_mgr.connection_failed.connect(_on_connection_failed)
        _multiplayer_mgr.disconnected.connect(_on_disconnected)


# ------------------------- public API -------------------------

func is_open() -> bool:
    return _is_open


func open() -> void:
    if _is_open:
        return
    _is_open = true
    visible = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    _show_main()
    opened.emit()


func close() -> void:
    if not _is_open:
        return
    _is_open = false
    visible = false
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    closed.emit()


# ------------------------- UI construction -------------------------

func _build_ui() -> void:
    _overlay = ColorRect.new()
    _overlay.color = Color(0.0, 0.0, 0.0, 0.55)
    _overlay.set_anchors_preset(Control.PRESET_FULL_RECT, true)
    _overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_overlay)

    var center: CenterContainer = CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT, true)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(center)

    _panel = PanelContainer.new()
    _panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
    var style: StyleBoxFlat = StyleBoxFlat.new()
    style.bg_color = Color(0.72, 0.72, 0.72, 0.96)
    style.border_color = Color(0.18, 0.18, 0.18, 1.0)
    style.border_width_left = 4
    style.border_width_right = 4
    style.border_width_top = 4
    style.border_width_bottom = 4
    style.content_margin_left = 22
    style.content_margin_right = 22
    style.content_margin_top = 20
    style.content_margin_bottom = 20
    _panel.add_theme_stylebox_override("panel", style)
    center.add_child(_panel)

    _vbox = VBoxContainer.new()
    _vbox.add_theme_constant_override("separation", 12)
    _panel.add_child(_vbox)


func _clear_vbox() -> void:
    for child in _vbox.get_children():
        _vbox.remove_child(child)
        child.queue_free()


func _make_title(text: String, size: int = 24) -> Label:
    var l: Label = Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08, 1))
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    return l


func _make_subtle(text: String) -> Label:
    var l: Label = Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", 14)
    l.add_theme_color_override("font_color", Color(0.18, 0.18, 0.18, 1))
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.custom_minimum_size = Vector2(PANEL_WIDTH - 60.0, 0.0)
    return l


func _make_button(text: String, callable: Callable) -> Button:
    var btn: Button = Button.new()
    btn.text = text
    btn.custom_minimum_size = Vector2(0.0, BTN_HEIGHT)
    btn.add_theme_font_size_override("font_size", 16)
    btn.pressed.connect(callable)
    return btn


# ------------------------- views -------------------------

func _show_main() -> void:
    _view = VIEW_MAIN
    _clear_vbox()
    _vbox.add_child(_make_title("Settings"))

    if _multiplayer_mgr != null and _multiplayer_mgr.is_active():
        var code: String = _multiplayer_mgr.get_room_code()
        var status_text: String = "In room: %s" % code if code != "" else "Connected"
        var status: Label = Label.new()
        status.text = status_text
        status.add_theme_font_size_override("font_size", 14)
        status.add_theme_color_override("font_color", Color(0.12, 0.32, 0.12, 1))
        status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _vbox.add_child(status)

    _vbox.add_child(_make_button("Back to Game", _on_back_to_game))
    _vbox.add_child(_make_button("Create Multiplayer Room", _on_create_room))
    _vbox.add_child(_make_button("Join Multiplayer Room", _on_show_join_input))

    if _multiplayer_mgr != null and _multiplayer_mgr.is_active():
        _vbox.add_child(_make_button("Leave Room", _on_leave_room))


func _show_code(code: String) -> void:
    _view = VIEW_CODE
    _clear_vbox()
    _vbox.add_child(_make_title("Room Created"))
    _vbox.add_child(_make_subtle("Share this 4-digit code with friends:"))

    var code_label: Label = Label.new()
    code_label.text = code
    code_label.add_theme_font_size_override("font_size", 56)
    code_label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05, 1))
    code_label.add_theme_color_override("font_outline_color", Color(0.95, 0.95, 0.95, 0.7))
    code_label.add_theme_constant_override("outline_size", 3)
    code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _vbox.add_child(code_label)

    _vbox.add_child(_make_button("Back to Game", _on_back_to_game))


func _show_join_input() -> void:
    _view = VIEW_JOIN
    _clear_vbox()
    _vbox.add_child(_make_title("Join Room"))
    _vbox.add_child(_make_subtle("Enter the 4-digit room code:"))

    var input: LineEdit = LineEdit.new()
    input.name = "CodeInput"
    input.placeholder_text = "1234"
    input.max_length = 4
    input.alignment = HORIZONTAL_ALIGNMENT_CENTER
    input.add_theme_font_size_override("font_size", 32)
    input.custom_minimum_size = Vector2(0.0, 56.0)
    input.text_submitted.connect(_on_join_submit_text)
    _vbox.add_child(input)
    input.grab_focus.call_deferred()

    _vbox.add_child(_make_button("Join", _on_join_submit_pressed))
    _vbox.add_child(_make_button("Cancel", _on_show_main))


func _show_status(message: String) -> void:
    _view = VIEW_STATUS
    _clear_vbox()
    _vbox.add_child(_make_title("Multiplayer", 22))
    _vbox.add_child(_make_subtle(message))
    _vbox.add_child(_make_button("Back to Game", _on_back_to_game))
    _vbox.add_child(_make_button("Back to Menu", _on_show_main))


# ------------------------- button handlers -------------------------

func _on_back_to_game() -> void:
    close()


func _on_show_main() -> void:
    _show_main()


func _on_create_room() -> void:
    if _multiplayer_mgr == null:
        _show_status("Multiplayer manager unavailable.")
        return
    if _multiplayer_mgr.is_active():
        var existing: String = _multiplayer_mgr.get_room_code()
        if existing != "":
            _show_code(existing)
            return
    var code: String = _multiplayer_mgr.create_room()
    if code == "":
        _show_status(
            "Failed to create room.\n%s" % _multiplayer_mgr.get_last_connection_debug()
        )
        return
    # Show the code immediately; room_created will re-show it once the relay
    # confirms our connection, but the value is already known locally.
    _pending_action = "create"
    _show_code(code)


func _on_show_join_input() -> void:
    _show_join_input()


func _on_join_submit_pressed() -> void:
    var input: LineEdit = _vbox.get_node_or_null("CodeInput")
    if input == null:
        return
    _on_join_submit_text(input.text)


func _on_join_submit_text(text: String) -> void:
    var code: String = text.strip_edges()
    if code.length() != 4 or not code.is_valid_int():
        _show_status("Invalid code. Enter exactly 4 digits.")
        return
    if _multiplayer_mgr == null:
        _show_status("Multiplayer manager unavailable.")
        return
    var ok: bool = _multiplayer_mgr.join_room(code)
    if not ok:
        _show_status(
            "Failed to join room.\n%s" % _multiplayer_mgr.get_last_connection_debug()
        )
        return
    _pending_action = "join"
    _show_status("Connecting to room %s…" % code)


func _on_leave_room() -> void:
    if _multiplayer_mgr != null:
        _multiplayer_mgr.leave_room()
    _show_main()


# ------------------------- multiplayer-manager signals -------------------------

func _on_room_created(code: String) -> void:
    _pending_action = ""
    if _is_open and _view in [VIEW_STATUS, VIEW_MAIN]:
        _show_code(code)


func _on_room_joined(code: String) -> void:
    _pending_action = ""
    if _is_open and _view == VIEW_STATUS:
        _show_status("Joined room %s. Press Back to Game." % code)


func _on_connection_failed(details: String) -> void:
    var msg: String
    match _pending_action:
        "create":
            msg = "Couldn't reach the multiplayer relay.\n%s" % details
        "join":
            msg = "Couldn't join the room.\n%s" % details
        _:
            msg = "Connection failed.\n%s" % details
    _pending_action = ""
    if _is_open:
        _show_status(msg)


func _on_disconnected() -> void:
    _pending_action = ""
    if _is_open:
        _show_status("Disconnected from room.")


# ------------------------- input -------------------------

func _input(event: InputEvent) -> void:
    # Esc closes the menu when open. The Player script opens it on Esc when
    # nothing else (inventory, this menu) is consuming the event.
    if not _is_open:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            close()
            get_viewport().set_input_as_handled()
