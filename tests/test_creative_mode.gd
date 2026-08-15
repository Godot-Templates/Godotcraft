class_name TestCreativeMode
extends Node

const HUD_SCRIPT: Script = preload("res://scripts/hud.gd")
const PLAYER_SCRIPT: Script = preload("res://scripts/player.gd")


func _new_hud() -> HUD:
	var hud: HUD = HUD_SCRIPT.new() as HUD
	hud._slots.resize(hud.TOTAL_SLOTS)
	for i: int in hud.TOTAL_SLOTS:
		hud._slots[i] = {"type": "", "count": 0}
	hud._slot_panels.resize(hud.TOTAL_SLOTS)
	return hud


func test_creative_hotbar_contains_every_placeable_block() -> void:
	var hud: HUD = _new_hud()
	hud.set_creative_mode(true)
	var expected: Array[String] = ["dirt", "grass", "cobble", "wood", "leaves", "sand"]
	for i: int in expected.size():
		assert(hud._slots[i].type == expected[i])
		assert(hud._slots[i].count == 1)


func test_creative_placement_does_not_consume_selected_block() -> void:
	var hud: HUD = _new_hud()
	hud.set_creative_mode(true)
	assert(hud.consume_selected(1))
	assert(hud.get_selected_type() == "dirt")
	assert(hud.get_selected_count() == 1)


func test_survival_placement_still_consumes_selected_block() -> void:
	var hud: HUD = _new_hud()
	hud._slots[0] = {"type": "dirt", "count": 1}
	assert(hud.consume_selected(1))
	assert(hud.get_selected_type() == "")
	assert(hud.get_selected_count() == 0)


func test_creative_mining_is_instant_and_drop_free() -> void:
	var player: Player = PLAYER_SCRIPT.new() as Player
	player.set_creative_mode(true)
	assert(player.get_mine_duration("cobble") == 0.0)
	assert(not player.should_spawn_mined_drop())


func test_survival_mining_keeps_duration_and_drops() -> void:
	var player: Player = PLAYER_SCRIPT.new() as Player
	player.set_creative_mode(false)
	assert(player.get_mine_duration("cobble") > 0.0)
	assert(player.should_spawn_mined_drop())
