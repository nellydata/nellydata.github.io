class_name PixelView
extends CanvasLayer
## The HD-2D world view for pixel-art phone games (proven in Chromaveil): the 3D world renders into a SubViewport
## that a TextureRect on CanvasLayer -1 shows, under the 2D UI, through the framework tilt-shift and grade pass
## (shaders/tilt_shift.gdshader). Portrait or landscape.
##
## Pixel rule: the world view's pixels must land on whole device pixels. With k device px per UI (art) px from
## PixelFit, the SubViewport renders at the UI grid x PixelFit.world_scale(k): 2x when k is even (each view
## pixel is k / 2 device px), 1x when k is odd (iPhone 14 Safari portrait: k = 5). World textures still sit on the
## characters' grid, 1 texel = 1 art px at the focus plane, never at 2x to match the view (FORMULA.md, Look). Low
## quality renders at 1x with no tilt-shift blur and no key-light shadows.
## It needs PixelFit.apply(root, design_min, true): CANVAS_ITEMS lets the view render finer than the UI grid.
##
## The blur reads a quarter-size copy of the view (`quarter`, shaders/downsample4.gdshader: each texel the mean
## of a 4 x 4 block) through 7 taps, the centre and a fixed ring of six with flat weights, so it stays smooth however
## many device px a view pixel covers (proven in Sonder (then Chromaveil) 0.13). The copy renders after the world
## each frame, and not at all on Low or while paused.
##
## Low looks darker round lamps, a renderer trait: GL Compatibility draws a shadowed directional light in an
## extra additive pass that blends in sRGB, so with key-light shadows on, any surface an omni light also
## reaches comes out brighter (measured, Godot 4.7.2: omni alone 0.357 + sun alone 0.337 gave 0.694 sRGB with sun
## shadows, against 0.482 without). Tune lamp energies on High, then check Low still reads.
##
## Use:
## [codeblock]
## PixelFit.apply(get_tree().root, DESIGN_MIN, true)
## var view := PixelView.new()
## add_child(view)
## view.world.add_child(diorama)          # lights, environment, camera rig and billboards go in view.world
## view.key_light = moon                  # its shadows switch off on Low
## view.focus_source = camera_rig         # anything with screen_focus_y() -> float keeps the sharp band on it
## view.keep_pixel_exact(hero_sprite)     # Billboard.pixel_exact every frame, after the camera moved
## view.low_quality = settings_low        # from the game's own settings
## [/codeblock]
## The view refreshes itself (deferred) on every window resize, after the owner of PixelFit.apply has run.
## While a rotate-your-phone screen shows, call set_paused(true): nothing 3D renders until set_paused(false).

const TILT_SHIFT := preload("res://shaders/tilt_shift.gdshader")
const DOWNSAMPLE := preload("res://shaders/downsample4.gdshader")

## Root of the 3D scene inside the SubViewport: add the diorama, environment, lights, camera rig here.
var world: Node3D
## The SubViewport the world renders into (UI grid x world_scale).
var viewport: SubViewport
## The blur's quarter-size copy of `viewport` (ceil(size / 4) per axis), bound to the post's quarter_tex.
var quarter: SubViewport
## The full-screen TextureRect that shows the world through the post material.
var display: TextureRect
## The tilt-shift and grade material (shaders/tilt_shift.gdshader) on `display`.
var post: ShaderMaterial
## World render pixels per UI pixel right now (1 or 2).
var world_scale := 1
## Main directional light (sun or moon): its shadows switch off on Low quality.
var key_light: DirectionalLight3D
## A node with screen_focus_y() -> float (the framework follow camera has it): moves the sharp band each frame.
var focus_source: Node
## Low quality (phone budget): 1x world render, no tilt-shift blur (and no blur copy), no key-light shadows.
var low_quality := false:
	set = set_low_quality

## Tilt-shift and grade settings (tilt_shift.gdshader uniforms); call apply_post() after changing them.
## The Chromaveil values for a portrait phone; the grade colours default to the shader's neutral night.
var focus_half := 0.16
var blur_max := 1.6
var vignette := 0.45
var grade_shadow := Color(0.10, 0.13, 0.20)
var grade_light := Color(1.0, 0.93, 0.82)
var grade_amount := 0.22

var _exact: Array[Sprite3D] = []
var _paused := false
var _quarter_rect: TextureRect  # draws the world texture into `quarter` through downsample4.gdshader


func _init() -> void:
	layer = -1  # under the 2D UI on layer 0+
	process_priority = 1000  # after gameplay and the camera, so pixel-exact snaps see this frame's positions
	viewport = SubViewport.new()
	viewport.name = "WorldViewport"
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	world = Node3D.new()
	world.name = "World"
	viewport.add_child(world)
	# after the world viewport: sibling viewports render in the order they entered the tree, so the copy is of this
	# frame's view (measured, Godot 4.7.2: a world viewport that entered after it left the copy a frame late)
	quarter = SubViewport.new()
	quarter.name = "BlurQuarter"
	quarter.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(quarter)
	_quarter_rect = TextureRect.new()
	_quarter_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # each bilinear tap is a 2 x 2 mean
	_quarter_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_quarter_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var down := ShaderMaterial.new()
	down.shader = DOWNSAMPLE
	_quarter_rect.material = down
	quarter.add_child(_quarter_rect)
	display = TextureRect.new()
	display.name = "WorldDisplay"
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # size to the screen, not to the world texture
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post = ShaderMaterial.new()
	post.shader = TILT_SHIFT
	display.material = post
	add_child(display)
	apply_post()


func _ready() -> void:
	display.texture = viewport.get_texture()
	_quarter_rect.texture = viewport.get_texture()
	post.set_shader_parameter("quarter_tex", quarter.get_texture())
	get_tree().root.size_changed.connect(_on_size_changed)
	refresh()


func _process(_delta: float) -> void:
	if _paused:
		return
	if focus_source and focus_source.has_method("screen_focus_y"):
		set_focus_y(float(focus_source.call("screen_focus_y")))
	var cam := viewport.get_camera_3d()
	if cam == null or _exact.is_empty():
		return
	var ui_w := ui_size().x
	for s in _exact:
		if is_instance_valid(s):
			Billboard.pixel_exact(s, cam, ui_w, world_scale)


## The UI grid in art px (the root's visible rect: PixelFit's content size).
func ui_size() -> Vector2:
	return get_viewport().get_visible_rect().size


## Re-sizes the world render to the UI grid x world scale (1x on Low) and applies the Low-quality cuts.
## Runs on its own after every resize; call it after changing the fit by hand.
func refresh() -> void:
	if not is_inside_tree():
		return
	var ui := ui_size()
	world_scale = 1 if low_quality else PixelFit.world_scale(PixelFit.current_scale(get_tree().root))
	viewport.size = Vector2i(maxi(1, roundi(ui.x)), maxi(1, roundi(ui.y))) * world_scale
	quarter.size = Vector2i(ceili(viewport.size.x / 4.0), ceili(viewport.size.y / 4.0))
	_quarter_rect.position = Vector2.ZERO
	_quarter_rect.size = Vector2(quarter.size)
	post.set_shader_parameter("blur_max", 0.0 if low_quality else blur_max)
	post.set_shader_parameter("quarter_ready", not low_quality)  # Low has no blur, so it renders no copy
	_sync_quarter()
	if key_light:
		key_light.shadow_enabled = not low_quality


## Switches Low quality on or off (1x world, no blur, no key-light shadows) and refreshes.
func set_low_quality(low: bool) -> void:
	low_quality = low
	refresh()


## Pushes the tilt-shift and grade settings to the post material.
func apply_post() -> void:
	post.set_shader_parameter("focus_half", focus_half)
	post.set_shader_parameter("blur_max", 0.0 if low_quality else blur_max)
	post.set_shader_parameter("vignette", vignette)
	post.set_shader_parameter("grade_shadow", grade_shadow)
	post.set_shader_parameter("grade_light", grade_light)
	post.set_shader_parameter("grade_amount", grade_amount)


## Centre of the sharp tilt-shift band, 0 (top) to 1 (bottom) of the screen.
func set_focus_y(y: float) -> void:
	post.set_shader_parameter("focus_y", y)


## Stops (true) or resumes (false) the world render, e.g. while a rotate-your-phone screen covers it: the
## SubViewport stops updating (UPDATE_DISABLED) and the layer hides, so the GPU does no 3D work.
func set_paused(paused: bool) -> void:
	_paused = paused
	visible = not paused
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if paused else SubViewport.UPDATE_ALWAYS
	_sync_quarter()


## True while set_paused(true) holds the world render.
func is_paused() -> bool:
	return _paused


## Keeps a character billboard pixel-exact (1 texel = 1 UI px) every frame; see Billboard.pixel_exact().
func keep_pixel_exact(sprite: Sprite3D) -> void:
	if sprite and not _exact.has(sprite):
		_exact.append(sprite)


## Stops keeping a billboard pixel-exact (it keeps its last size and offset).
func release_pixel_exact(sprite: Sprite3D) -> void:
	_exact.erase(sprite)


func _on_size_changed() -> void:
	refresh.call_deferred()


# The blur's copy renders only while the blur can read it: never on Low, never while paused.
func _sync_quarter() -> void:
	var on := not low_quality and not _paused
	quarter.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
