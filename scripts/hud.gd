class_name HUD
extends CanvasLayer

## Hotbar (9 slots: scroll-wheel or 1–9 keys to switch) + Inventory panel (E to toggle).
## Tracks per-slot { type, count } items, fires selection_changed so the player can
## show the held block on its FP arm. Opening the inventory flips mouse-mode to
## VISIBLE; player.gd already freezes movement when mouse isn't captured.

const HOTBAR_SIZE: int = 9
const INVENTORY_ROWS: int = 3
const SLOT_SIZE: Vector2 = Vector2(50.0, 50.0)

signal selection_changed(slot_index: int, item_type: String)

@export var dirt_texture: Texture2D
@export var grass_top_texture: Texture2D
@export var cobble_texture: Texture2D
@export var wood_texture: Texture2D
@export var leaves_texture: Texture2D
@export var sand_texture: Texture2D

@onready var hotbar: HBoxContainer = $Hotbar
@onready var inventory: PanelContainer = $Inventory
@onready var inv_grid: GridContainer = $Inventory/InvContent/InvGrid

var _hotbar_slots: Array[Panel] = []
var _selected_slot: int = 0
var _items: Array = []  # length HOTBAR_SIZE: [{ "type": String, "count": int }, ...]


func _enter_tree() -> void:
	add_to_group("hud")


func _ready() -> void:
	_items.resize(HOTBAR_SIZE)
	for i in HOTBAR_SIZE:
		_items[i] = {"type": "", "count": 0}
	_build_hotbar()
	_build_inventory_grid()
	_style_inventory_panel()
	_update_selection()


func _style_inventory_panel() -> void:
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0.72, 0.72, 0.72, 0.96)
	bg.border_color = Color(0.18, 0.18, 0.18, 1.0)
	bg.border_width_left = 4
	bg.border_width_right = 4
	bg.border_width_top = 4
	bg.border_width_bottom = 4
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 10
	bg.content_margin_bottom = 10
	inventory.add_theme_stylebox_override("panel", bg)
	var title: Label = $Inventory/InvContent/Title
	title.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08, 1))
	title.add_theme_color_override("font_outline_color", Color(0.95, 0.95, 0.95, 0.5))
	title.add_theme_constant_override("outline_size", 2)


func is_inventory_open() -> bool:
	return inventory.visible


func get_selected_type() -> String:
	var s: Dictionary = _items[_selected_slot]
	return s.type if s.count > 0 else ""


func get_selected_count() -> int:
	return _items[_selected_slot].count


func add_item(type: String, count: int) -> int:
	# Prefer adding to an existing slot of the same type.
	for i in HOTBAR_SIZE:
		if _items[i].type == type and _items[i].count > 0:
			_items[i].count += count
			_refresh_slot(i)
			if i == _selected_slot:
				_emit_selection_changed()
			return count
	# Otherwise occupy the first empty slot.
	for i in HOTBAR_SIZE:
		if _items[i].count == 0:
			_items[i].type = type
			_items[i].count = count
			_refresh_slot(i)
			if i == _selected_slot:
				_emit_selection_changed()
			return count
	return 0  # inventory full


func consume_selected(amount: int) -> bool:
	var s: Dictionary = _items[_selected_slot]
	if s.count < amount:
		return false
	s.count -= amount
	if s.count == 0:
		s.type = ""
	_refresh_slot(_selected_slot)
	_emit_selection_changed()
	return true


func _build_hotbar() -> void:
	for i in HOTBAR_SIZE:
		var slot: Panel = _make_slot(str(i + 1))
		hotbar.add_child(slot)
		_hotbar_slots.append(slot)


func _build_inventory_grid() -> void:
	for i in HOTBAR_SIZE * INVENTORY_ROWS:
		inv_grid.add_child(_make_slot(""))


func _make_slot(label_text: String) -> Panel:
	var slot: Panel = Panel.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.add_theme_stylebox_override("panel", _slot_style(false))
	slot.mouse_filter = Control.MOUSE_FILTER_PASS

	# Slot number (top-left).
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

	# Item icon (fills slot with padding).
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

	# Count badge (bottom-right).
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
	# Minecraft slots are rectangular — no rounded corners.
	s.corner_radius_top_left = 0
	s.corner_radius_top_right = 0
	s.corner_radius_bottom_left = 0
	s.corner_radius_bottom_right = 0
	return s


func _update_selection() -> void:
	for i in HOTBAR_SIZE:
		_hotbar_slots[i].add_theme_stylebox_override("panel", _slot_style(i == _selected_slot))
	_emit_selection_changed()


func _emit_selection_changed() -> void:
	selection_changed.emit(_selected_slot, get_selected_type())


func _refresh_slot(index: int) -> void:
	var slot_node: Panel = _hotbar_slots[index]
	var icon: TextureRect = slot_node.get_node_or_null("Icon")
	var badge: Label = slot_node.get_node_or_null("Badge")
	var item: Dictionary = _items[index]
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


func _input(event: InputEvent) -> void:
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
		if inventory.visible:
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_selected_slot = (_selected_slot - 1 + HOTBAR_SIZE) % HOTBAR_SIZE
			_update_selection()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_selected_slot = (_selected_slot + 1) % HOTBAR_SIZE
			_update_selection()
			get_viewport().set_input_as_handled()


func _toggle_inventory() -> void:
	if inventory.visible:
		_close_inventory()
	else:
		_open_inventory()


func _open_inventory() -> void:
	inventory.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_inventory() -> void:
	inventory.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
