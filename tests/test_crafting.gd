class_name TestCraftingPure
extends Node

## Pure recipe-matching tests for the 2x2 inventory crafting, incl. the
## shapeless log -> 4x planks recipe. These exercises only touch inert
## slot/held dictionaries — no Control trees are built — so the headless
## runner can instance them identically every time.

const HUD_SCRIPT: Script = preload("res://scripts/hud.gd")


func _new_hud() -> CanvasLayer:
    # Instance the raw script with no packed-scene fixture; then seed the slot
    # arrays the same way hud's _ready does so refresh guards stay inert.
    var hud: CanvasLayer = CanvasLayer.new()
    hud.set_script(HUD_SCRIPT)
    hud._slots.resize(hud.TOTAL_SLOTS)
    for i in hud.TOTAL_SLOTS:
        hud._slots[i] = {"type": "", "count": 0}
    hud._slot_panels.resize(hud.TOTAL_SLOTS)
    return hud


func test_empty_grid_yields_no_output() -> void:
    var hud: CanvasLayer = _new_hud()
    hud._recompute_output()
    var output: Dictionary = hud._slots[hud.OUTPUT_INDEX]
    assert(output.type == "")
    assert(output.count == 0)


func test_log_anywhere_in_grid_yields_four_planks() -> void:
    # The single-log recipe is shapeless: each of the four grid slots must work.
    for slot_i in 4:
        var hud: CanvasLayer = _new_hud()
        hud._slots[hud.CRAFT_START + slot_i] = {"type": "wood", "count": 1}
        hud._recompute_output()
        var output: Dictionary = hud._slots[hud.OUTPUT_INDEX]
        assert(output.type == "planks")
        assert(output.count == 4)


func test_shaped_recipes_still_match() -> void:
    var hud: CanvasLayer = _new_hud()
    for i in 4:
        hud._slots[hud.CRAFT_START + i] = {"type": "sand", "count": 1}
    hud._recompute_output()
    var output: Dictionary = hud._slots[hud.OUTPUT_INDEX]
    assert(output.type == "cobble")
    assert(output.count == 4)


func test_shaped_recipe_rejects_mismatched_grid() -> void:
    var hud: CanvasLayer = _new_hud()
    for i in 4:
        hud._slots[hud.CRAFT_START + i] = {"type": "sand", "count": 1}
    # Swap out one corner; the exact sand x4 shape must no longer match, and
    # there is no shapeless wood input, so the output must clear.
    hud._slots[hud.CRAFT_START + 3] = {"type": "gravel", "count": 1}
    hud._recompute_output()
    var output: Dictionary = hud._slots[hud.OUTPUT_INDEX]
    assert(output.type == "")
    assert(output.count == 0)


func test_planks_times_four_yield_crafting_table() -> void:
    # The 2x2-planks shaped recipe is how the crafting table is made.
    var hud: CanvasLayer = _new_hud()
    for i in 4:
        hud._slots[hud.CRAFT_START + i] = {"type": "planks", "count": 1}
    hud._recompute_output()
    var output: Dictionary = hud._slots[hud.OUTPUT_INDEX]
    assert(output.type == "crafting_table")
    assert(output.count == 1)


func test_three_planks_do_not_yield_crafting_table() -> void:
    var hud: CanvasLayer = _new_hud()
    for i in 3:
        hud._slots[hud.CRAFT_START + i] = {"type": "planks", "count": 1}
    hud._recompute_output()
    var output: Dictionary = hud._slots[hud.OUTPUT_INDEX]
    assert(output.type == "")
    assert(output.count == 0)
