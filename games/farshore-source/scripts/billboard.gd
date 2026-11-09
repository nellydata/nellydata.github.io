class_name Billboard
extends RefCounted
## Sprite3D helpers for HD-2D billboards (proven in Chromaveil): pixel art standing in a lit 3D diorama.
##
## Two densities live side by side:
## - World density: props and NPCs at a fixed texel size in metres (make(), 16 px per metre by default), so
##   they scale with depth like the 3D world around them.
## - Pixel-exact: the player character at exactly 1 texel = 1 UI (art) pixel whatever its depth (pixel_exact(),
##   every frame), so the hero always reads at the same crisp scale as the 2D UI.
##
## Gotchas measured on GL Compatibility (Godot 4.7.2):
## - Sprite3D.modulate is stored as 8-bit vertex colour, so values above 1 are clamped. For HDR (bloom) put the
##   colour in a material's albedo_color instead (glow() does).
## - A material_override replaces Sprite3D's own material: Sprite3D.billboard, texture, alpha_cut and shaded
##   no longer apply. The shaders here billboard themselves and take the frame as `sprite`; use set_frame().
## - A self-billboarding shader must turn by MAIN_CAM_INV_VIEW_MATRIX, not INV_VIEW_MATRIX: in the shadow pass
##   the latter is the light's, so the shadow-casting card faces the light and darkens half of the shaded card
##   the camera sees (Godot's own billboard modes already do this).
## - render_mode unshaded drops EMISSION. For a body immune to lights, write black ALBEDO and the colour as
##   EMISSION in a lit shader (key_emissive_billboard's unshaded_body).
## - alpha_cut DISCARD (make()) drops every pixel under the 0.5 scissor, so a soft glow drawn that way (every pixel at
##   70/255 or less, say) never shows. Glows are blended and unshaded: glow().

## Meta key holding a sprite's resting offset (feet on the ground) for pixel_exact().
const BASE_OFFSET := &"billboard_base_offset"
const FOLIAGE := preload("res://shaders/foliage_billboard.gdshader")
const KEY_EMISSIVE := preload("res://shaders/key_emissive_billboard.gdshader")


## A world-density billboard: Y-fixed (upright, turns to the camera), feet on the ground at the node origin,
## nearest filtering, alpha-cut discard, double-sided, casting shadows. px_per_m texels make one metre.
static func make(tex: Texture2D, px_per_m := 16.0, shaded := true) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = 1.0 / maxf(px_per_m, 0.001)
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = shaded
	s.double_sided = true
	s.centered = true
	s.offset = Vector2(0.0, tex.get_size().y / 2.0) if tex else Vector2.ZERO
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	s.set_meta(BASE_OFFSET, s.offset)
	return s


## Scales a billboard so its painted figure (the texture's used rect, not the canvas) is height_m tall, and
## moves it so the lowest painted row (the soles) touches the ground at the node origin. Returns the pixel size.
static func fit_height(sprite: Sprite3D, height_m: float) -> float:
	if sprite == null or sprite.texture == null:
		return 0.0
	var tex := sprite.texture
	var used := tex.get_image().get_used_rect()
	if used.size.y <= 0:
		return sprite.pixel_size
	sprite.pixel_size = height_m / float(used.size.y)
	var tex_h := float(tex.get_size().y)
	sprite.offset = Vector2(sprite.offset.x, tex_h / 2.0 - (tex_h - float(used.end.y)))
	sprite.set_meta(BASE_OFFSET, sprite.offset)
	return sprite.pixel_size


## A foliage billboard (reeds, grass, bushes, trees) on shaders/foliage_billboard: gust-field sway, roots pinned,
## bends away from `player_world_pos`, texel-snapped. stiffness about 1 reeds, 2 bushes, 3 trees; phase per prop.
static func foliage(tex: Texture2D, px_per_m := 16.0, stiffness := 1.0, phase := 0.0) -> Sprite3D:
	var s := make(tex, px_per_m, true)
	var m := _self_billboard(s, FOLIAGE)
	m.set_shader_parameter("pixel_m", s.pixel_size)
	m.set_shader_parameter("height_m", (tex.get_size().y if tex else 0.0) * s.pixel_size)
	m.set_shader_parameter("stiffness", stiffness)
	m.set_shader_parameter("phase", phase)
	return s


## A billboard whose key-colour pixels (default #ff00ff) glow glow_color (shaders/key_emissive_billboard).
## unshaded_body keeps the rest at its painted values whatever the lights. Y-fixed until pixel_exact() runs.
static func key_emissive(tex: Texture2D, glow_color: Color, px_per_m := 16.0, unshaded_body := false) -> Sprite3D:
	var s := make(tex, px_per_m, true)
	var m := _self_billboard(s, KEY_EMISSIVE)
	m.set_shader_parameter("glow_color", glow_color)
	m.set_shader_parameter("unshaded_body", unshaded_body)
	return s


## Shows a new animation frame on a billboard, also on a self-billboarding shader (its `sprite` uniform).
static func set_frame(sprite: Sprite3D, tex: Texture2D) -> void:
	sprite.texture = tex
	var m := sprite.material_override as ShaderMaterial
	if m:
		m.set_shader_parameter("sprite", tex)


## World metres per texel that make one texel exactly one UI pixel at view depth `depth` (metres along the camera
## axis): the frustum spans 2 x depth x tan(fov / 2) metres across ui_px UI pixels on the axis the fov is locked
## to. Example: depth 16 m, fov 34, 234 px wide (KEEP_WIDTH) gives 0.0418 m.
static func texel_m(depth: float, fov_deg: float, ui_px: float) -> float:
	return 2.0 * depth * tan(deg_to_rad(fov_deg) / 2.0) / maxf(ui_px, 1.0)


## Distance from the camera to a point along the camera's forward axis (what perspective scales by), at least
## 0.5 m so a sprite at the near plane cannot blow up.
static func view_depth(cam_xform: Transform3D, world_pos: Vector3) -> float:
	var forward := -cam_xform.basis.z.normalized()
	return maxf((world_pos - cam_xform.origin).dot(forward), 0.5)


## The sprite offset (in texels) that puts a camera-facing billboard's left and bottom edges on whole UI pixels.
## screen_ui is the projected node origin in UI px (y down); base_offset the resting offset; tex_size the frame
## size. With 1 texel = 1 UI px the quad spans offset +- tex_size / 2 texels around the origin, so each edge sits
## at screen_ui + that span. The left edge moves to the nearest whole pixel. The bottom edge only ever moves up
## (by under 1 px, y is up in texels): a downward snap would sink the sole row under the ground plane, where the
## depth test clips it, and at world x2 that row then draws half height (pixel-exact gate, QA_AND_PROBES.md).
static func snap_offset(screen_ui: Vector2, base_offset: Vector2, tex_size: Vector2) -> Vector2:
	var left := screen_ui.x + base_offset.x - tex_size.x / 2.0
	var bottom := screen_ui.y - (base_offset.y - tex_size.y / 2.0)
	return base_offset + Vector2(roundf(left) - left, bottom - floorf(bottom))


## Keeps a character billboard at exactly 1 texel = 1 UI (art) pixel whatever its depth. Call it every frame
## after the camera has moved (PixelView.keep_pixel_exact() does), with the UI grid width in art px and the
## PixelView world scale (view px per UI px).
## Why it works: the billboard faces the camera fully (square texels, no foreshortening; a Y-fixed card would
## squash rows by cos(pitch)), and all of it sits at one view depth, where the frustum spans
## 2 x depth x tan(fov / 2) metres across the UI width (KEEP_WIDTH; KEEP_HEIGHT spans the height instead). Setting
## pixel_size to that over the UI px gives 1 texel = 1 UI px. Then the left and bottom edges are snapped onto the
## UI pixel grid through the offset, so nearest sampling hits every texel once. Only the draw is snapped: the
## node position stays smooth and deterministic. Nearest filtering, no mipmaps.
## It owns the sprite's offset from then on: the resting offset is read once into the BASE_OFFSET meta (set the
## meta to change it), so animate by frames (set_frame(), or a sheet's frame), never by moving the offset.
static func pixel_exact(sprite: Sprite3D, cam: Camera3D, ui_width: float, world_scale: int) -> void:
	if sprite == null or sprite.texture == null or cam == null or not sprite.is_inside_tree():
		return
	if not sprite.has_meta(BASE_OFFSET):
		sprite.set_meta(BASE_OFFSET, sprite.offset)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var m := sprite.material_override as ShaderMaterial
	if m:
		m.set_shader_parameter("face_camera", true)  # a custom vertex() ignores Sprite3D.billboard
	var pos := sprite.global_position
	var ui_px := ui_width
	if cam.keep_aspect == Camera3D.KEEP_HEIGHT:
		var vp := cam.get_viewport().get_visible_rect().size
		ui_px = ui_width * vp.y / maxf(vp.x, 1.0)
	sprite.pixel_size = texel_m(view_depth(cam.global_transform, pos), cam.fov, ui_px)
	var screen_ui := cam.unproject_position(pos) / float(maxi(world_scale, 1))
	sprite.offset = snap_offset(screen_ui, sprite.get_meta(BASE_OFFSET), frame_size(sprite))


## The size in texels of the frame a Sprite3D shows: its region when region_enabled, else the texture split by
## hframes x vframes (a sheet such as DirSprite's), else the whole texture.
static func frame_size(sprite: Sprite3D) -> Vector2:
	if sprite == null or sprite.texture == null:
		return Vector2.ZERO
	if sprite.region_enabled:
		return sprite.region_rect.size
	return sprite.texture.get_size() / Vector2(maxi(sprite.hframes, 1), maxi(sprite.vframes, 1))


## The pixel-exact probe's checker (tools/webtest/pixel_exact.mjs): size x size texels alternating the key colour
## #ff00ff and cyan #00ffff. Show it on the pixel-exact lead instead of its art when pxtest_requested() is true;
## in a device-resolution capture every texel must then land as one k x k block of device px.
static func pxtest_checker(size := 16) -> ImageTexture:
	var n := maxi(size, 2)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			img.set_pixel(x, y, Color(1, 0, 1) if (x + y) % 2 == 0 else Color(0, 1, 1))
	return ImageTexture.create_from_image(img)


## True when the pixel-exact probe is asked for: `--pxtest` among the user args on desktop (`godot ... -- --pxtest`),
## `?pxtest` in the page URL on the web (pixel_exact.mjs adds it). The web returns a JS boolean as an int (1 or 0),
## and GDScript has no `int == bool`, so the result goes through bool(): `== true` was silently false in a release
## export (KNOWLEDGE.md, Phone and web).
static func pxtest_requested() -> bool:
	if OS.get_cmdline_user_args().has("--pxtest"):
		return true
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('pxtest')"))
	return false


## An additive glow billboard for a light source: fully camera-facing, unshaded, BLEND_MODE_ADD, no shadow.
## color may go above 1 to feed the Environment glow (it lives in the material, where HDR survives). A null tex
## uses halo_texture(). Centre it on the light: glow.position = light.position. LightBudget flickers its modulate.
static func glow(tex: Texture2D, color: Color, px_per_m := 16.0) -> Sprite3D:
	var t := tex if tex else halo_texture()
	var s := Sprite3D.new()
	s.texture = t
	s.pixel_size = 1.0 / maxf(px_per_m, 0.001)
	s.centered = true
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = t
	m.albedo_color = color
	s.material_override = m
	return s


## A procedural pixel-art halo: a core and three stepped rings, each one flat alpha (no smooth gradient, no dither:
## shade is a flat step, FORMULA.md, Look), white with the intensity in alpha. Used by glow() when no art is given.
static func halo_texture(radius_px := 16) -> ImageTexture:
	var r := maxi(radius_px, 4)
	var img := Image.create(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	for y in r * 2:
		for x in r * 2:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length() / float(r)
			var a := 0.0
			for ring in [[0.25, 0.9], [0.5, 0.5], [0.75, 0.22], [1.0, 0.08]]:
				if d <= ring[0]:
					a = ring[1]
					break
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


static func _self_billboard(s: Sprite3D, shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("sprite", s.texture)
	s.material_override = m
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED  # the shader billboards itself
	s.extra_cull_margin = 1.0  # the shader turns and shears the quad outside its flat local box
	return m
