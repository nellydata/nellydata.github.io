// Key-colour emissive billboard for Sprite3D characters and props (proven in Chromaveil). Key pixels render as
// black albedo plus EMISSION glow_color x glow_boost; every other pixel is the sprite as painted. The shader
// billboards itself (set Sprite3D.billboard = DISABLED and pass the frame as `sprite`; Billboard.key_emissive()
// and Billboard.set_frame() do this). See key_emissive.gdshaderinc for the key and cleanup rules.
//
// unshaded_body: the body keeps its own values, untouched by lights and shadows (a character that must read
// against any scene). It is done as black albedo + EMISSION = the texel, because render_mode unshaded drops
// EMISSION on the GL Compatibility renderer: an unshaded variant would draw the key pixels black (measured in
// Godot 4.7.2: unshaded ALBEDO 0 + EMISSION red renders 0,0,0).
// face_camera: false is a Y-fixed billboard (upright, world density); true faces the camera fully, which
// Billboard.pixel_exact() needs (it sets this uniform itself).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert;

#include "res://shaders/key_emissive.gdshaderinc"

uniform sampler2D sprite : source_color, filter_nearest;
uniform bool unshaded_body = false;
uniform bool face_camera = false;

void vertex() {
	// MAIN_CAM_INV_VIEW_MATRIX stays the main camera's in the shadow pass (INV_VIEW_MATRIX is the light's there),
	// so the shadow caster is the same card the camera sees and the sprite never shadows half of itself.
	mat4 cam = MAIN_CAM_INV_VIEW_MATRIX;
	if (face_camera) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(cam[0], cam[1], cam[2], MODEL_MATRIX[3]);
	} else {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(cam[0], MODEL_MATRIX[1],
				vec4(normalize(cross(cam[0].xyz, MODEL_MATRIX[1].xyz)), 0.0), MODEL_MATRIX[3]);
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 t = texture(sprite, UV);
	if (t.a < 0.5) {
		discard;
	}
	ROUGHNESS = 0.9;
	if (is_key(t.rgb)) {
		ALBEDO = vec3(0.0);
		EMISSION = key_glow();
		SPECULAR = 0.0;
	} else if (unshaded_body) {
		ALBEDO = vec3(0.0);
		EMISSION = t.rgb;
		SPECULAR = 0.0;
	} else {
		ALBEDO = t.rgb;
	}
}
