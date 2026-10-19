# ==========================================
# FILE: Touch.gd
# DESCRIPTION: Touch-screen support. Press and hold anything with a description (cards, charms, map nodes,
#              HUD items) to see it in a popup; lift your finger to close it. On touch devices taps act on
#              release, and a hold or a drag cancels the tap so nothing is played by accident.
#              Desktop mouse play is unchanged.
# VERSION: v0.100
# ==========================================
extends Node

const HOLD_TIME := 0.45   # seconds before a press becomes a hold
const SLOP := 18.0        # pixels a finger may wander before the press counts as a drag

## Phones and tablets scroll the map by dragging.
var drag_scroll := OS.has_feature("mobile")

var _start := Vector2.ZERO
var _armed := false
var _consumed := false   # this touch became a hold or a drag, so its release is not a tap
var _timer: Timer
var _layer: CanvasLayer
var _popup: PanelContainer
var _title: Label
var _body: Label
var _held_button: BaseButton
var _theme: Theme

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_hold)
	add_child(_timer)
	_layer = CanvasLayer.new()
	_layer.layer = 128
	add_child(_layer)

# is_tap
# DESCRIPTION: Whether a left mouse-button event should count as a tap or click. With a real mouse that is
#              the press; for a touch it is the release, unless the touch turned into a hold or a drag.
func is_tap(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return false
	# Godot turns touches into mouse events tagged with the emulation device id.
	if event.device != InputEvent.DEVICE_ID_EMULATION:
		return event.pressed
	return not event.pressed and not _consumed

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			_start = event.position
			_armed = true
			_consumed = false
			_timer.start(HOLD_TIME)
		else:
			_armed = false
			_timer.stop()
			_hide()
			_release_button.call_deferred()
	elif event is InputEventScreenDrag and event.index == 0:
		if not _consumed and event.position.distance_to(_start) > SLOP:
			_armed = false
			_timer.stop()
			_consumed = true
			_hold_button()

func _on_hold() -> void:
	if not _armed:
		return
	var text := _info_at(_start)
	if text == "":
		return
	_consumed = true
	_hold_button()
	_show(text, _start)
	Sfx.play("hover", 1.0, -4.0)

# _info_at
# DESCRIPTION: The description under a point: the current screen gets the first say (battle hand cards),
#              then the nearest control with a tooltip.
func _info_at(pos: Vector2) -> String:
	var main := get_tree().get_first_node_in_group("router")
	if main != null and main.has_method("touch_info_at"):
		var text: String = main.touch_info_at(pos)
		if text != "":
			return text
	var c: Control = get_viewport().gui_get_hovered_control()
	while c != null:
		if c.tooltip_text != "":
			return c.tooltip_text
		c = c.get_parent() as Control
	return ""

# A Button fires on release, so a held or dragged button is briefly disabled to cancel its press.
func _hold_button() -> void:
	var c: Control = get_viewport().gui_get_hovered_control()
	while c != null and not (c is BaseButton):
		c = c.get_parent() as Control
	if c != null and not (c as BaseButton).disabled:
		_held_button = c
		_held_button.disabled = true

func _release_button() -> void:
	if _held_button != null and is_instance_valid(_held_button):
		_held_button.disabled = false
	_held_button = null

# ---------- Popup ----------

func _show(text: String, at: Vector2) -> void:
	_hide()
	var lines := text.split("\n", false, 1)
	_popup = PanelContainer.new()
	if _theme == null:
		_theme = UIKit.build_theme()
	_popup.theme = _theme
	_popup.add_theme_stylebox_override("panel", UIKit.panel_style(0))
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := UIKit.vbox(6)
	_popup.add_child(col)
	_title = UIKit.label(lines[0], 24, UIKit.GOLD, true)
	col.add_child(_title)
	if lines.size() > 1:
		_body = UIKit.label(lines[1], 22, UIKit.TEXT)
		_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.custom_minimum_size.x = 520
		col.add_child(_body)
	_layer.add_child(_popup)
	_place.call_deferred(at)

# Above the finger where there is room (so the finger doesn't cover it), otherwise below; kept on screen.
func _place(at: Vector2) -> void:
	if _popup == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var s := _popup.get_combined_minimum_size()
	_popup.size = s
	var pos := Vector2(at.x - s.x / 2.0, at.y - s.y - 90.0)
	if pos.y < 8.0:
		pos.y = at.y + 90.0
	pos.x = clampf(pos.x, 8.0, screen.x - s.x - 8.0)
	pos.y = clampf(pos.y, 8.0, screen.y - s.y - 8.0)
	_popup.position = pos

func _hide() -> void:
	if _popup != null:
		_popup.queue_free()
		_popup = null
