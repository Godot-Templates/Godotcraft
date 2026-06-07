class_name HUD
extends CanvasLayer

## Hotbar (9 slots: scroll-wheel or 1–9 keys to switch) + Inventory (E to toggle).
## Inventory has a 2x2 crafting grid + output slot in the header (Minecraft-style).
## While the inventory is open, left-click picks up / drops a whole stack on the
## cursor; right-click splits / drops one at a time; mismatched types swap.

const HOTBAR_SIZE: int = 9
const INVENTORY_ROWS: int = 3
const INVENTORY_COLS: int = 9
const CRAFT_SIZE: int = 4
const SLOT_SIZE: Vector2 = Vector2(50.0, 50.0)

# Flat slot index layout:
#  0..8   hotbar
#  9..35  inventory (3 rows × 9)
#  36..39 crafting grid (2×2, row-major)
#  40     crafting output
const HOTBAR_START: int = 0
const INV_START: int = 9
const CRAFT_START: int = 36
const OUTPUT_INDEX: int = 40
const TOTAL_SLOTS: int = 41

signal selection_changed(slot_index: int, item_type: String)

# Shaped 2x2 recipes — pattern must match the crafting grid exactly (no rotation).
# Empty slot = "".
const RECIPES: Array = [
    {"shape": ["sand", "sand", "sand", "sand"], "output": {"type": "cobble", "count": 4}},
    {"shape": ["leaves", "leaves", "leaves", "leaves"], "output": {"type": "wood", "count": 2}},
    {"shape": ["dirt", "dirt", "dirt", "dirt"], "output": {"type": "grass", "count": 4}},
    {"shape": ["cobble", "cobble", "cobble", "cobble"], "output": {"type": "wood", "count": 1}},
]

@export var dirt_texture: Texture2D
@export var grass_top_texture: Texture2D
@export var cobble_texture: Texture2D
@export var wood_texture: Texture2D
@export var leaves_texture: Texture2D
@export var sand_texture: Texture2D

@onready var hotbar: HBoxContainer = $Hotbar
@onready var inventory: PanelContainer = $Inventory
@onready var inv_grid: GridContainer = $Inventory/InvContent/InvGrid

var _slots: Array = []           # length TOTAL_SLOTS, each { type, count }
var _slot_panels: Array = []     # length TOTAL_SLOTS, parallel to _slots
var _selected_slot: int = 0
var _held: Dictionary = {"type": "", "count": 0}  # cursor-held stack
var _cursor_preview: Control


func _enter_tree() -> void:
    add_to_group("hud")


func _ready() -> void:
    _slots.resize(TOTAL_SLOTS)
    for i in TOTAL_SLOTS:
        _slots[i] = {"type": "", "count": 0}
    _slot_panels.resize(TOTAL_SLOTS)
    _build_hotbar()
    _build_crafting_section()
    _build_inventory_grid()
    _style_inventory_panel()
    _build_cursor_preview()
    _update_selection()


func _process(_delta: float) -> void:
    if _cursor_preview != null and _cursor_preview.visible:
        _cursor_preview.position = get_viewport().get_mouse_position() - SLOT_SIZE * 0.5


# ------------------------- public API -------------------------

func is_inventory_open() -> bool:
    return inventory.visible


func get_selected_type() -> String:
    var s: Dictionary = _slots[_selected_slot]
    return s.type if s.count > 0 else ""


func get_selected_count() -> int:
    return _slots[_selected_slot].count


func add_item(type: String, count: int) -> int:
    # Prefer merging into an existing stack of the same type (hotbar first, then inventory).
    var last: int = INV_START + INVENTORY_ROWS * INVENTORY_COLS
    for i in last:
        if _slots[i].type == type and _slots[i].count > 0:
            _slots[i].count += count
            _refresh_slot(i)
            if i == _selected_slot:
                _emit_selection_changed()
            return count
    # Otherwise occupy the first empty slot.
    for i in last:
        if _slots[i].count == 0:
            _slots[i].type = type
            _slots[i].count = count
            _refresh_slot(i)
            if i == _selected_slot:
                _emit_selection_changed()
            return count
    return 0


func consume_selected(amount: int) -> bool:
    var s: Dictionary = _slots[_selected_slot]
    if s.count < amount:
        return false
    s.count -= amount
    if s.count == 0:
        s.type = ""
    _refresh_slot(_selected_slot)
    _emit_selection_changed()
    return true


# ------------------------- UI construction -------------------------

func _build_hotbar() -> void:
    for i in HOTBAR_SIZE:
        var idx: int = HOTBAR_START + i
        var slot: Panel = _make_slot(str(i + 1), idx)
        hotbar.add_child(slot)
        _slot_panels[idx] = slot


func _build_crafting_section() -> void:
    # Restructure the InvContent VBox: put a header HBox at the top with the
    # Title on the left and the crafting block on the right.
    var inv_content: VBoxContainer = $Inventory/InvContent
    var title: Label = $Inventory/InvContent/Title

    var header: HBoxContainer = HBoxContainer.new()
    header.name = "Header"
    header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_theme_constant_override("separation", 16)

    inv_content.remove_child(title)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    header.add_child(title)

    var craft_vbox: VBoxContainer = VBoxContainer.new()
    craft_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    craft_vbox.add_theme_constant_override("separation", 4)

    var craft_label: Label = Label.new()
    craft_label.text = "Crafting"
    craft_label.add_theme_font_size_override("font_size", 14)
    craft_label.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08, 1))
    craft_vbox.add_child(craft_label)

    var craft_row: HBoxContainer = HBoxContainer.new()
    craft_row.add_theme_constant_override("separation", 8)
    craft_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER

    var craft_grid: GridContainer = GridContainer.new()
    craft_grid.columns = 2
    craft_grid.add_theme_constant_override("h_separation", 4)
    craft_grid.add_theme_constant_override("v_separation", 4)
    for i in CRAFT_SIZE:
        var idx: int = CRAFT_START + i
        var slot: Panel = _make_slot("", idx)
        craft_grid.add_child(slot)
        _slot_panels[idx] = slot
    craft_row.add_child(craft_grid)

    var arrow: Label = Label.new()
    arrow.text = "→"
    arrow.add_theme_font_size_override("font_size", 32)
    arrow.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08, 1))
    arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    craft_row.add_child(arrow)

    var output: Panel = _make_slot("", OUTPUT_INDEX)
    _slot_panels[OUTPUT_INDEX] = output
    var output_wrap: CenterContainer = CenterContainer.new()
    output_wrap.add_child(output)
    craft_row.add_child(output_wrap)

    craft_vbox.add_child(craft_row)
    header.add_child(craft_vbox)

    inv_content.add_child(header)
    inv_content.move_child(header, 0)


func _build_inventory_grid() -> void:
    for i in INVENTORY_ROWS * INVENTORY_COLS:
        var idx: int = INV_START + i
        var slot: Panel = _make_slot("", idx)
        inv_grid.add_child(slot)
        _slot_panels[idx] = slot


func _build_cursor_preview() -> void:
    _cursor_preview = Control.new()
    _cursor_preview.name = "CursorPreview"
    _cursor_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _cursor_preview.custom_minimum_size = SLOT_SIZE
    _cursor_preview.size = SLOT_SIZE
    _cursor_preview.visible = false
    _cursor_preview.z_index = 100
    add_child(_cursor_preview)

    var icon: TextureRect = TextureRect.new()
    icon.name = "Icon"
    icon.set_anchors_preset(Control.PRESET_FULL_RECT, true)
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _cursor_preview.add_child(icon)

    var badge: Label = Label.new()
    badge.name = "Badge"
    badge.add_theme_font_size_override("font_size", 14)
    badge.add_theme_color_override("font_color", Color.WHITE)
    badge.add_theme_color_override("font_outline_color", Color.BLACK)
    badge.add_theme_constant_override("outline_size", 3)
    badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
    badge.offset_left = -30.0
    badge.offset_top = -20.0
    badge.offset_right = -3.0
    badge.offset_bottom = -1.0
    badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
    badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _cursor_preview.add_child(badge)


# ------------------------- per-slot construction -------------------------

func _make_slot(label_text: String, slot_index: int) -> Panel:
    var slot: Panel = Panel.new()
    slot.custom_minimum_size = SLOT_SIZE
    # Lock the slot to a square — without SHRINK_CENTER, an HBoxContainer would
    # stretch slots vertically and they'd read as taller-than-wide rectangles.
    slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    slot.add_theme_stylebox_override("panel", _slot_style(false))
    slot.mouse_filter = Control.MOUSE_FILTER_PASS
    slot.set_meta("slot_index", slot_index)
    slot.gui_input.connect(_on_slot_gui_input.bind(slot_index))

    if label_text != "":
        var label: Label = Label.new()
        label.text = label_text
        label.add_theme_font_size_override("font_size", 12)
        label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1))
        label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05, 1))
        label.add_theme_constant_override("outline_size", 3)
        label.position = Vector2(3.0, 0.0)
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        slot.add_child(label)

    var icon: TextureRect = TextureRect.new()
    icon.name = "Icon"
    icon.set_anchors_preset(Control.PRESET_FULL_RECT, true)
    icon.offset_left = 6.0
    icon.offset_top = 6.0
    icon.offset_right = -6.0
    icon.offset_bottom = -6.0
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    icon.visible = false
    slot.add_child(icon)

    var badge: Label = Label.new()
    badge.name = "Badge"
    badge.add_theme_font_size_override("font_size", 14)
    badge.add_theme_color_override("font_color", Color.WHITE)
    badge.add_theme_color_override("font_outline_color", Color.BLACK)
    badge.add_theme_constant_override("outline_size", 3)
    badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
    badge.offset_left = -30.0
    badge.offset_top = -20.0
    badge.offset_right = -3.0
    badge.offset_bottom = -1.0
    badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
    badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    badge.visible = false
    slot.add_child(badge)

    return slot


func _slot_style(selected: bool) -> StyleBoxFlat:
    var s: StyleBoxFlat = StyleBoxFlat.new()
    s.bg_color = Color(0.55, 0.55, 0.55, 0.94) if selected else Color(0.45, 0.45, 0.45, 0.92)
    s.border_color = Color(1.0, 1.0, 1.0, 1.0) if selected else Color(0.18, 0.18, 0.18, 1.0)
    var w: int = 3 if selected else 2
    s.border_width_left = w
    s.border_width_right = w
    s.border_width_top = w
    s.border_width_bottom = w
    s.corner_radius_top_left = 0
    s.corner_radius_top_right = 0
    s.corner_radius_bottom_left = 0
    s.corner_radius_bottom_right = 0
    return s


func _style_inventory_panel() -> void:
    var bg: StyleBoxFlat = StyleBoxFlat.new()
    bg.bg_color = Color(0.72, 0.72, 0.72, 0.96)
    bg.border_color = Color(0.18, 0.18, 0.18, 1.0)
    bg.border_width_left = 4
    bg.border_width_right = 4
    bg.border_width_top = 4
    bg.border_width_bottom = 4
    bg.content_margin_left = 14
    bg.content_margin_right = 14
    bg.content_margin_top = 12
    bg.content_margin_bottom = 12
    inventory.add_theme_stylebox_override("panel", bg)
    var title: Label = inventory.get_node("InvContent/Header/Title") if inventory.has_node("InvContent/Header/Title") else $Inventory/InvContent/Title
    title.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08, 1))
    title.add_theme_color_override("font_outline_color", Color(0.95, 0.95, 0.95, 0.5))
    title.add_theme_constant_override("outline_size", 2)


# ------------------------- click-to-pickup -------------------------

func _on_slot_gui_input(event: InputEvent, slot_index: int) -> void:
    if not inventory.visible:
        return
    if event is InputEventMouseButton and event.pressed:
        var mb: InputEventMouseButton = event
        if mb.button_index == MOUSE_BUTTON_LEFT:
            _slot_left_click(slot_index)
            get_viewport().set_input_as_handled()
        elif mb.button_index == MOUSE_BUTTON_RIGHT:
            _slot_right_click(slot_index)
            get_viewport().set_input_as_handled()


func _slot_left_click(slot_index: int) -> void:
    if slot_index == OUTPUT_INDEX:
        _take_output()
        return
    var slot: Dictionary = _slots[slot_index]
    if _held.count == 0:
        if slot.count > 0:
            _held = {"type": slot.type, "count": slot.count}
            slot.type = ""
            slot.count = 0
    else:
        if slot.count == 0:
            slot.type = _held.type
            slot.count = _held.count
            _held = {"type": "", "count": 0}
        elif slot.type == _held.type:
            slot.count += _held.count
            _held = {"type": "", "count": 0}
        else:
            # Swap
            var tmp: Dictionary = {"type": slot.type, "count": slot.count}
            slot.type = _held.type
            slot.count = _held.count
            _held = tmp
    _refresh_slot(slot_index)
    _refresh_cursor()
    _on_craft_changed(slot_index)
    if slot_index == _selected_slot:
        _emit_selection_changed()


func _slot_right_click(slot_index: int) -> void:
    if slot_index == OUTPUT_INDEX:
        # Right-click on output behaves like left-click (take the whole batch).
        _take_output()
        return
    var slot: Dictionary = _slots[slot_index]
    if _held.count == 0:
        if slot.count > 0:
            var take: int = int(ceil(slot.count / 2.0))
            _held = {"type": slot.type, "count": take}
            slot.count -= take
            if slot.count == 0:
                slot.type = ""
    else:
        if slot.count == 0:
            slot.type = _held.type
            slot.count = 1
            _held.count -= 1
        elif slot.type == _held.type:
            slot.count += 1
            _held.count -= 1
        else:
            return  # different type, can't drop one
        if _held.count == 0:
            _held.type = ""
    _refresh_slot(slot_index)
    _refresh_cursor()
    _on_craft_changed(slot_index)
    if slot_index == _selected_slot:
        _emit_selection_changed()


func _refresh_cursor() -> void:
    if _cursor_preview == null:
        return
    if _held.count == 0:
        _cursor_preview.visible = false
        return
    _cursor_preview.visible = true
    var icon: TextureRect = _cursor_preview.get_node("Icon")
    var badge: Label = _cursor_preview.get_node("Badge")
    icon.texture = _texture_for(_held.type)
    icon.visible = icon.texture != null
    badge.text = str(_held.count)
    badge.visible = _held.count > 1


# ------------------------- crafting -------------------------

func _on_craft_changed(changed_index: int) -> void:
    # Only inputs (36..39) trigger a recompute; output changes are driven by _take_output.
    if changed_index >= CRAFT_START and changed_index < OUTPUT_INDEX:
        _recompute_output()


func _recompute_output() -> void:
    var shape: Array = []
    for i in CRAFT_SIZE:
        shape.append(_slots[CRAFT_START + i].type)
    var output_slot: Dictionary = _slots[OUTPUT_INDEX]
    for recipe in RECIPES:
        if (recipe.shape as Array) == shape:
            output_slot.type = recipe.output.type
            output_slot.count = recipe.output.count
            _refresh_slot(OUTPUT_INDEX)
            return
    output_slot.type = ""
    output_slot.count = 0
    _refresh_slot(OUTPUT_INDEX)


func _take_output() -> void:
    var output: Dictionary = _slots[OUTPUT_INDEX]
    if output.count == 0:
        return
    if _held.count == 0:
        _held = {"type": output.type, "count": output.count}
    elif _held.type == output.type:
        _held.count += output.count
    else:
        return  # cursor holds something else
    # Consume one of each crafting input.
    for i in CRAFT_SIZE:
        var s: Dictionary = _slots[CRAFT_START + i]
        if s.count > 0:
            s.count -= 1
            if s.count == 0:
                s.type = ""
            _refresh_slot(CRAFT_START + i)
    _refresh_cursor()
    _recompute_output()


# ------------------------- selection / refresh -------------------------

func _update_selection() -> void:
    for i in HOTBAR_SIZE:
        _slot_panels[HOTBAR_START + i].add_theme_stylebox_override(
            "panel", _slot_style(i == _selected_slot)
        )
    _emit_selection_changed()


func _emit_selection_changed() -> void:
    selection_changed.emit(_selected_slot, get_selected_type())


func _refresh_slot(index: int) -> void:
    var slot_node: Panel = _slot_panels[index]
    if slot_node == null:
        return
    var icon: TextureRect = slot_node.get_node_or_null("Icon")
    var badge: Label = slot_node.get_node_or_null("Badge")
    var item: Dictionary = _slots[index]
    if item.count > 0:
        if icon != null:
            icon.texture = _texture_for(item.type)
            icon.visible = icon.texture != null
        if badge != null:
            badge.text = str(item.count)
            badge.visible = item.count > 1
    else:
        if icon != null:
            icon.visible = false
        if badge != null:
            badge.visible = false


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


# ------------------------- input -------------------------

func _input(event: InputEvent) -> void:
    # If a Control owns keyboard focus (e.g. the settings-menu join-code
    # LineEdit), let it consume its own keystrokes — don't hijack 1-9 here.
    if get_viewport().gui_get_focus_owner() != null:
        return
    # Also stand down while the settings menu is up so its own input handler
    # owns the keystrokes.
    if _is_settings_menu_open():
        return
    if event is InputEventKey and event.pressed and not event.echo:
        var k: int = event.keycode
        if k == KEY_E:
            _toggle_inventory()
            get_viewport().set_input_as_handled()
            return
        if k == KEY_ESCAPE and inventory.visible:
            _close_inventory()
            get_viewport().set_input_as_handled()
            return
        if not inventory.visible and k >= KEY_1 and k <= KEY_9:
            _selected_slot = k - KEY_1
            _update_selection()
            get_viewport().set_input_as_handled()
            return
    elif event is InputEventMouseButton and event.pressed:
        # Don't swallow events when inventory is open — slots need to receive them.
        if inventory.visible:
            return
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _selected_slot = (_selected_slot - 1 + HOTBAR_SIZE) % HOTBAR_SIZE
            _update_selection()
            get_viewport().set_input_as_handled()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _selected_slot = (_selected_slot + 1) % HOTBAR_SIZE
            _update_selection()
            get_viewport().set_input_as_handled()


func _is_settings_menu_open() -> bool:
    var menus: Array = get_tree().get_nodes_in_group("settings_menu")
    if menus.is_empty():
        return false
    var menu: Node = menus[0]
    if menu.has_method("is_open"):
        return menu.is_open()
    return false


func _toggle_inventory() -> void:
    if inventory.visible:
        _close_inventory()
    else:
        _open_inventory()


func _open_inventory() -> void:
    inventory.visible = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_inventory() -> void:
    # Return any held stack to the inventory so items aren't lost.
    if _held.count > 0:
        add_item(_held.type, _held.count)
        _held = {"type": "", "count": 0}
        _refresh_cursor()
    # Also return any leftover crafting inputs.
    for i in CRAFT_SIZE:
        var s: Dictionary = _slots[CRAFT_START + i]
        if s.count > 0:
            add_item(s.type, s.count)
            s.type = ""
            s.count = 0
            _refresh_slot(CRAFT_START + i)
    _recompute_output()
    inventory.visible = false
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
