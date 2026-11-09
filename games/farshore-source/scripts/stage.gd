class_name Stage
extends RefCounted
## Shared HD-2D presentation setup used by exploration and battle:
## world SubViewport + tilt-shift/grade pass + night environment.

static func make_view(parent: Node) -> Dictionary:
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.stretch_shrink = 1
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var post := ShaderMaterial.new()
	post.shader = preload("res://shaders/tilt_shift.gdshader")
	container.material = post
	parent.add_child(container)
	var vp := SubViewport.new()
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.audio_listener_enable_3d = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	container.add_child(vp)
	var world := Node3D.new()
	world.name = "World"
	vp.add_child(world)
	world.add_child(environment())
	return {"container": container, "viewport": vp, "world": world, "post": post}

static func environment() -> WorldEnvironment:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.1, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.38, 0.55)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.36, 0.42, 0.55)
	env.fog_light_energy = 0.9
	env.fog_density = 0.016
	env.fog_sky_affect = 1.0
	env.fog_height = 1.5
	env.fog_height_density = 0.04
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.92
	we.environment = env
	return we
