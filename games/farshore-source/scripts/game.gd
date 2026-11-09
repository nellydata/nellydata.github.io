extends Node
## Farshore: a short exploration game built with the framework's pixel presentation.

const SAVE_PATH := "user://farshore.json"
const DESIGN_MIN := Vector2i(192, 336)
const FONT := preload("res://assets/fonts/hd2d_body.fnt")
const STONES := [
	{"name": "The Grove", "position": Vector3(-9, 0, -7), "color": Color("cbe89c"),
		"line": "The grove remembers a song carried on the wind."},
	{"name": "The Eastern Rise", "position": Vector3(9, 0, -8), "color": Color("f6ce86"),
		"line": "A warm note rises above the eastern cliffs."},
	{"name": "The South Shore", "position": Vector3(9, 0, 9), "color": Color("a6e2e1"),
		"line": "A quiet note returns from the sea."},
]
const TOWER := Vector3(0, 0, 0)
const SPAWN := Vector3(-3, 0, 8)
const PLAYER_RADIUS := 0.32
const WALK_SPEED := 4.2
const TOWER_REACH := 2.8

var view: PixelView
var rig: FollowCamera
var hero: Node3D
var hero_sprite: Sprite3D
var stones: Array[Node3D] = []
var found := [false, false, false]
var complete := false
var playing := false
var held := {"up": false, "down": false, "left": false, "right": false}
var walk_time := 0.0
var facing := "down"
var hero_frames: Dictionary = {}
var obstacles: Array[Dictionary] = []
var near_index := -1
var panel: PanelContainer
var panel_title: Label
var panel_text: Label
var panel_button: Button
var hud: Control
var progress: Label
var hint: Label
var action: Button
var notice: Label
var notice_timer := 0.0
var ui: Control
var buttons: Dictionary = {}
var sound: AudioStreamPlayer
var sounds: Array[AudioStreamWAV] = []
var save_warning := ""


func _ready() -> void:
	PixelFit.apply(get_tree().root, DESIGN_MIN, true)
	get_tree().root.size_changed.connect(_schedule_resize)
	view = PixelView.new()
	add_child(view)
	_build_world()
	_build_ui()
	_build_audio()
	_load_progress()
	_refresh_stones()
	_resize()
	_show_panel("FARSHORE", "A small island has fallen quiet.\n\nFind three windstones, then bring their song to the old signal tower.\n\nMove with the arrows or WASD, or use the on-screen controls. Use the action button or Space near a landmark.", "BEGIN")


func _process(delta: float) -> void:
	if notice_timer > 0.0:
		notice_timer -= delta
		if notice_timer <= 0.0:
			notice.text = ""
	if not playing:
		return
	var direction := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT) or held.right) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT) or held.left),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or held.down) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or held.up)
	).normalized()
	if direction.length_squared() > 0.0:
		facing = ("right" if direction.x > 0.0 else "left") if absf(direction.x) > absf(direction.y) else ("down" if direction.y > 0.0 else "up")
		var before := hero.position
		_move_hero(direction * delta * WALK_SPEED)
		if hero.position.distance_squared_to(before) > 0.000001:
			walk_time += delta
			hero_sprite.texture = hero_frames[facing][1 + int(walk_time * 7.0) % 2]
		else:
			hero_sprite.texture = hero_frames[facing][0]
	else:
		walk_time = 0.0
		hero_sprite.texture = hero_frames[facing][0]
	RenderingServer.global_shader_parameter_set("player_world_pos", hero.global_position)
	_update_context()


func _move_hero(motion: Vector2) -> void:
	var steps := maxi(1, ceili(motion.length() / 0.15))
	var step := motion / float(steps)
	for i in steps:
		for axis: Vector2 in [Vector2(step.x, 0), Vector2(0, step.y)]:
			var current := Vector2(hero.position.x, hero.position.z)
			var next: Vector2 = (current + axis).clamp(Vector2(-14.5, -14.5), Vector2(14.5, 14.5))
			var blocked := false
			for obstacle in obstacles:
				var center: Vector2 = obstacle.center
				var radius: float = obstacle.radius + PLAYER_RADIUS
				var old_dist := current.distance_squared_to(center)
				var new_dist := next.distance_squared_to(center)
				if new_dist < radius * radius and new_dist < old_dist:
					blocked = true
					break
			if not blocked:
				hero.position.x = next.x
				hero.position.z = next.y


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			if playing:
				_interact()
			elif panel.visible:
				_close_panel()
			get_viewport().set_input_as_handled()


func _resize() -> void:
	PixelFit.apply(get_tree().root, DESIGN_MIN, true)
	if rig and rig.cam:
		rig.cam.keep_aspect = Camera3D.KEEP_HEIGHT if PixelFit.is_landscape() else Camera3D.KEEP_WIDTH
	if not ui:
		return
	var size := get_viewport().get_visible_rect().size
	var inset := PixelFit.safe_insets()
	var left := float(inset.left) + 8.0
	var right := float(inset.right) + 8.0
	var top := float(inset.top) + 8.0
	var bottom := float(inset.bottom) + 8.0
	progress.position = Vector2(left, top)
	progress.size = Vector2(maxf(100.0, size.x - left - right - 50.0), 24)
	buttons.help.position = Vector2(size.x - right - 35, top)
	var y := size.y - bottom - 82
	buttons.up.position = Vector2(left + 34, y)
	buttons.left.position = Vector2(left, y + 34)
	buttons.down.position = Vector2(left + 34, y + 34)
	buttons.right.position = Vector2(left + 68, y + 34)
	action.position = Vector2(size.x - right - 70, size.y - bottom - 42)
	hint.position = Vector2(maxf(left, size.x / 2.0 - 92), size.y - bottom - 30)
	hint.size = Vector2(minf(184, size.x - left - right), 20)
	notice.position = Vector2(left, top + 27)
	notice.size = Vector2(size.x - left - right, 30)
	panel.size = Vector2(minf(300.0, size.x - left - right), minf(190.0, size.y - top - bottom))
	panel.position = (size - panel.size) / 2.0


func _schedule_resize() -> void:
	_resize.call_deferred()


func _build_world() -> void:
	var world := view.world
	var env := Stage.environment()
	env.environment.background_color = Color("a1ccd0")
	env.environment.ambient_light_color = Color("d4e5cf")
	env.environment.ambient_light_energy = 0.45
	env.environment.fog_enabled = true
	env.environment.fog_light_color = Color("b0d1cb")
	env.environment.fog_density = 0.009
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff0cb")
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-52, -30, 0)
	world.add_child(sun)
	view.key_light = sun
	view.focus_half = 0.24
	view.blur_max = 1.0
	view.vignette = 0.15
	view.grade_amount = 0.04
	view.apply_post()
	var kit := Kit.new()
	kit.add_material("grass", _material(Color("668f64")))
	kit.add_material("path", _material(Color("c2b58a")))
	kit.add_material("rock", _material(Color("8b9b8a")))
	kit.add_material("dark", _material(Color("485e5c")))
	kit.add_material("water", _material(Color("588f9d")))
	kit.add_material("roof", _material(Color("b06c55")))
	kit.box("water", Vector3(0, -0.75, 0), Vector3(100, 0.2, 100), 0, Color.WHITE, ["bottom"])
	kit.box("rock", Vector3(0, -0.42, 0), Vector3(32, 0.7, 32), 0, Color.WHITE, ["bottom"])
	kit.box("grass", Vector3(0, -0.1, 0), Vector3(31, 0.2, 31), 0, Color.WHITE, ["bottom"])
	kit.box("path", Vector3(0, 0.012, 0), Vector3(3.2, 0.024, 24), 0, Color.WHITE, ["bottom"])
	kit.box("path", Vector3(0, 0.014, -7), Vector3(21, 0.028, 2.5), 0, Color.WHITE, ["bottom"])
	kit.cylinder("rock", Vector3(0, 0, 0), 2.0, 0.35, 12)
	kit.cylinder("rock", Vector3(0, 0.35, 0), 0.9, 3.8, 8)
	kit.cylinder("dark", Vector3(0, 4.15, 0), 1.1, 0.28, 8)
	kit.cylinder("roof", Vector3(0, 4.43, 0), 1.0, 0.8, 8, true, Color.WHITE, 0.0)
	obstacles.append({"center": Vector2.ZERO, "radius": 2.0})
	for s in STONES:
		var p: Vector3 = s.position
		kit.cylinder("rock", p, 0.95, 0.32, 8)
		kit.cylinder("dark", p + Vector3(0, 0.32, 0), 0.45, 0.72, 8)
		obstacles.append({"center": Vector2(p.x, p.z), "radius": 0.8})
	kit.build(world)
	var tree_tex := ImageTexture.create_from_image(_tree_art())
	var grass_tex := ImageTexture.create_from_image(_grass_art())
	var rng := RandomNumberGenerator.new()
	rng.seed = 7341
	for i in 45:
		var p := Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14))
		if absf(p.x) < 2.4 or absf(p.z + 7) < 1.7 or p.distance_to(TOWER) < 3.0 or p.distance_to(SPAWN) < 4.0:
			continue
		var clear := true
		for s in STONES:
			if p.distance_to(s.position) < 2.3:
				clear = false
		if not clear:
			continue
		var tree := Billboard.make(tree_tex, 13.0, false)
		tree.position = p
		tree.modulate = Color.from_hsv(0.31 + rng.randf_range(-0.02, 0.02), 0.75, rng.randf_range(0.84, 1.0))
		world.add_child(tree)
		obstacles.append({"center": Vector2(p.x, p.z), "radius": 0.35})
	for i in 65:
		var p := Vector3(rng.randf_range(-14, 14), 0.02, rng.randf_range(-14, 14))
		if absf(p.x) < 1.8 or absf(p.z + 7) < 1.3:
			continue
		var tuft := Billboard.make(grass_tex, 16.0, false)
		tuft.position = p
		world.add_child(tuft)
	for s in STONES:
		var marker := Node3D.new()
		marker.position = s.position + Vector3(0, 1.12, 0)
		world.add_child(marker)
		var crystal := Billboard.make(ImageTexture.create_from_image(_crystal_art(s.color)), 12.0, false)
		marker.add_child(crystal)
		var glow := Billboard.glow(Billboard.halo_texture(12), s.color)
		glow.position.y = 0.7
		marker.add_child(glow)
		stones.append(marker)
	hero = Node3D.new()
	hero.position = SPAWN
	world.add_child(hero)
	for direction in ["down", "up", "left", "right"]:
		var frames: Array[ImageTexture] = []
		for step in 3:
			frames.append(ImageTexture.create_from_image(_hero_art(direction, step)))
		hero_frames[direction] = frames
	hero_sprite = Billboard.make(hero_frames.down[0], 16.0, false)
	hero.add_child(hero_sprite)
	rig = FollowCamera.new()
	rig.base = {"pitch": 38.0, "distance": 17.0, "fov": 38.0, "height": 0.9, "yaw": 0.0}
	rig.bounds = AABB(Vector3(-16, -5, -16), Vector3(32, 20, 32))
	world.add_child(rig)
	rig.target = hero
	rig.snap()
	view.focus_source = rig


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat


func _tree_art() -> Image:
	var image := Image.create(32, 52, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(13, 30, 6, 22), Color("725845"))
	image.fill_rect(Rect2i(15, 29, 2, 23), Color("a38156"))
	for y in range(3, 38):
		for x in range(2, 30):
			var dx := float(x - 16) / 14.0
			var dy := float(y - 20) / 17.0
			if dx * dx + dy * dy < 1.0:
				var c := Color("365e4d") if x < 6 or y > 32 else Color("4a7957")
				if ((x * 7 + y * 13) % 17) < 4:
					c = Color("78a569")
				image.set_pixel(x, y, c)
	return image


func _grass_art() -> Image:
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	for i in 8:
		image.set_pixel(3 + i / 3, 11 - i, Color("b4ce80"))
		image.set_pixel(8 - i / 4, 11 - i, Color("3e7254"))
	return image


func _crystal_art(color: Color) -> Image:
	var image := Image.create(18, 30, false, Image.FORMAT_RGBA8)
	for y in range(3, 27):
		var width := mini(6, mini(y - 2, 27 - y))
		for x in range(9 - width, 10 + width):
			image.set_pixel(x, y, color.lightened(0.2) if x < 9 else color)
	return image


func _hero_art(direction: String, step: int) -> Image:
	var image := Image.create(22, 38, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(7, 3, 8, 8), Color("62483c"))
	if direction != "up":
		image.fill_rect(Rect2i(7, 5, 8, 6), Color("dba781"))
	image.fill_rect(Rect2i(5, 2, 12, 4), Color("394b59"))
	image.fill_rect(Rect2i(4, 11, 14, 13), Color("3d7980"))
	image.fill_rect(Rect2i(6, 11, 10, 3), Color("d98061"))
	if direction == "up":
		image.fill_rect(Rect2i(6, 14, 10, 9), Color("ad6251"))
	var stride := 0 if step == 0 else (2 if step == 1 else -2)
	image.fill_rect(Rect2i(16, 13 + stride, 3, 10), Color("dba781"))
	image.fill_rect(Rect2i(3, 13 - stride, 3, 10), Color("dba781"))
	image.fill_rect(Rect2i(7 + stride, 24, 4, 10), Color("364b50"))
	image.fill_rect(Rect2i(12 - stride, 24, 4, 10), Color("364b50"))
	image.fill_rect(Rect2i(6 + stride, 34, 5, 3), Color("6c4a3c"))
	image.fill_rect(Rect2i(12 - stride, 34, 5, 3), Color("6c4a3c"))
	if direction == "down":
		image.fill_rect(Rect2i(8, 7, 1, 1), Color("283a3c"))
		image.fill_rect(Rect2i(13, 7, 1, 1), Color("283a3c"))
	elif direction != "up":
		image.fill_rect(Rect2i(8 if direction == "left" else 13, 7, 1, 1), Color("283a3c"))
	return image


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	progress = _label("", 11)
	hud.add_child(progress)
	notice = _label("", 10)
	hud.add_child(notice)
	hint = _label("", 10)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(hint)
	for spec in [["up", "W"], ["left", "A"], ["down", "S"], ["right", "D"]]:
		var b := _button(spec[1], Vector2(32, 32))
		var key: String = spec[0]
		b.button_down.connect(func() -> void: held[key] = true)
		b.button_up.connect(func() -> void: held[key] = false)
		hud.add_child(b)
		buttons[key] = b
	action = _button("LISTEN", Vector2(70, 38))
	action.pressed.connect(_interact)
	hud.add_child(action)
	var help := _button("?", Vector2(35, 30))
	help.pressed.connect(func() -> void:
		_show_panel("FIELD NOTES", "Find the three glowing windstones around the island. Walk close and choose LISTEN. Then return to the tower at the crossroads.\n\nArrow keys / WASD move. Space or Enter listens. Your progress saves in this browser.", "RETURN"))
	hud.add_child(help)
	buttons.help = help
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	ui.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)
	panel_title = _label("", 17)
	stack.add_child(panel_title)
	panel_text = _label("", 10)
	panel_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(panel_text)
	panel_button = _button("BEGIN", Vector2(70, 26))
	panel_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel_button.pressed.connect(_close_panel)
	stack.add_child(panel_button)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("fff9e8"))
	label.add_theme_color_override("font_shadow_color", Color("172b35"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.16, 0.17, 0.94)
	style.border_color = Color("dfd0a6")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style


func _button(text: String, size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.size = size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", Color("fff9e8"))
	button.add_theme_color_override("font_hover_color", Color("fff9e8"))
	button.add_theme_color_override("font_pressed_color", Color("fff9e8"))
	button.add_theme_stylebox_override("normal", _panel_style())
	var active := _panel_style()
	active.bg_color = Color("527f75")
	button.add_theme_stylebox_override("hover", active)
	button.add_theme_stylebox_override("pressed", active)
	return button


func _show_panel(title: String, text: String, button_text: String) -> void:
	playing = false
	for key in held:
		held[key] = false
	panel_title.text = title
	panel_text.text = text + ("\n\n" + save_warning if not save_warning.is_empty() else "")
	panel_button.text = button_text
	panel.visible = true
	hud.visible = false


func _close_panel() -> void:
	panel.visible = false
	hud.visible = true
	playing = true
	_update_context()


func _update_context() -> void:
	near_index = -1
	var n := 0
	for i in found.size():
		if found[i]:
			n += 1
		elif hero.position.distance_to(STONES[i].position) < 2.1:
			near_index = i
	var near_tower := hero.position.distance_to(TOWER) < TOWER_REACH
	progress.text = "STONES  %d / 3" % n
	if near_index >= 0:
		hint.text = STONES[near_index].name
		action.text = "LISTEN"
	elif near_tower:
		hint.text = "THE SIGNAL TOWER"
		action.text = "RESTORE"
	else:
		hint.text = "" if not complete else "THE ISLAND IS SINGING"
		action.text = "LISTEN"


func _interact() -> void:
	if not playing:
		return
	_update_context()
	if near_index >= 0:
		var index := near_index
		found[index] = true
		_refresh_stones()
		_save_progress()
		_play_sound(index)
		_show_panel(STONES[index].name.to_upper(), STONES[index].line + "\n\nA windstone answers. Its light will guide you back to the tower.", "CONTINUE")
	elif hero.position.distance_to(TOWER) < TOWER_REACH:
		if found.all(func(value: bool) -> bool: return value):
			complete = true
			_save_progress()
			_play_sound(3)
			_show_panel("THE SIGNAL RETURNS", "The three notes gather into one bright call.\n\nAcross the water, another light answers. The island is no longer alone.\n\nThank you for exploring Farshore.", "KEEP EXPLORING")
		else:
			_show_panel("THE SIGNAL TOWER", "The tower is quiet. Three windstones hold the notes that can wake it.\n\nLook for their light in the grove, the eastern rise, and the south shore.", "CONTINUE")
	else:
		_flash_notice("Explore the island. Glowing stones hold the lost notes.")


func _refresh_stones() -> void:
	for i in stones.size():
		stones[i].visible = not found[i]


func _flash_notice(text: String) -> void:
	notice.text = text
	notice_timer = 4.0


func _save_problem(detail: String) -> void:
	push_warning(detail)
	save_warning = "Save unavailable. Progress may not persist."
	_flash_notice(save_warning)


func _save_progress() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		_save_problem("Could not save Farshore progress: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify({"version": 1, "found": found, "complete": complete,
		"x": hero.position.x, "z": hero.position.z}))
	file.flush()
	if file.get_error() != OK:
		_save_problem("Could not finish saving Farshore progress: %s" % error_string(file.get_error()))
	else:
		save_warning = ""


func _load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		_save_problem("Could not open Farshore save: %s" % error_string(FileAccess.get_open_error()))
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("version") != 1 or not data.get("found") is Array:
		_save_problem("Farshore save is invalid; starting a new journey.")
		return
	var saved: Array = data.found
	if saved.size() != 3 or not saved.all(func(value: Variant) -> bool: return value is bool):
		_save_problem("Farshore save has invalid windstone data; starting a new journey.")
		return
	if not data.get("complete") is bool or (data.complete and not saved.all(func(value: bool) -> bool: return value)):
		_save_problem("Farshore save has invalid completion data; starting a new journey.")
		return
	found = saved.duplicate()
	complete = data.complete
	if data.get("x") is float or data.get("x") is int:
		hero.position.x = clampf(float(data.x), -14.5, 14.5)
	if data.get("z") is float or data.get("z") is int:
		hero.position.z = clampf(float(data.z), -14.5, 14.5)
	rig.snap()


func _build_audio() -> void:
	sound = AudioStreamPlayer.new()
	sound.volume_db = -12.0
	add_child(sound)
	for frequency in [392.0, 494.0, 587.0, 784.0]:
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 22050
		var bytes := PackedByteArray()
		var count := int(stream.mix_rate * 0.45)
		bytes.resize(count * 2)
		for i in count:
			var t := float(i) / stream.mix_rate
			var envelope := exp(-t * 6.0) * minf(1.0, t * 80.0)
			var sample := int(20000.0 * envelope * (sin(TAU * frequency * t) + 0.25 * sin(TAU * frequency * 2.0 * t)) / 1.25)
			bytes.encode_s16(i * 2, sample)
		stream.data = bytes
		sounds.append(stream)


func _play_sound(index: int) -> void:
	sound.stream = sounds[index]
	sound.play()
