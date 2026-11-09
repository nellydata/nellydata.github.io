// Living foliage billboard (proven in Chromaveil): reeds, grass, bushes, palms and trees that move.
// A Y-fixed billboard (the shader billboards itself, so set Sprite3D.billboard = DISABLED; Billboard.foliage()
// does all of this). The top of the sprite shears in a scrolling gust field, so gusts visibly roll across a reed
// bed instead of everything swaying in step; roots stay put (h squared); foliage bends away from the player
// (`player_world_pos`, declared in project.godot [shader_globals]) within push_radius. The shear snaps to whole
// texels so the pixel art never smears.
// Pass the sprite texture as `sprite` (a material_override ignores Sprite3D.texture) and keep pixel_m equal to
// the sprite's pixel_size. Nearest filtering, alpha scissor at 0.5, casts shadows like an opaque card.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert;

global uniform vec3 player_world_pos;
global uniform float night_light;     // 0 day .. 1 night (world_clock.gd sets it; project.godot declares it)

uniform sampler2D sprite : source_color, filter_nearest;
uniform float pixel_m = 0.0625;       // world metres per texel (the Sprite3D's pixel_size)
uniform float height_m = 1.0;         // sprite height in metres (texture height x pixel_m)
uniform float stiffness = 1.0;        // about 1 reeds and grass, 2 bushes, 3 palms and trees
uniform float phase = 0.0;            // per-prop phase so neighbours never move in step
uniform float push_radius = 1.1;      // bend away from the player within this distance (m)
uniform float gust_strength = 0.11;   // tip sway as a fraction of the height
uniform float push_strength = 0.18;   // tip bend at contact, as a fraction of the height
uniform float night_emission = 0.14;  // self-light at full night, so foliage never goes muddy; x night_light

// Two travelling waves plus a slow swell: gust fronts roll across the ground along +x / +z.
float gust(vec2 p, float t) {
	return 0.55 * sin(p.x * 0.45 + p.y * 0.18 - t * 1.6)
		+ 0.3 * sin(p.x * 1.3 - p.y * 0.7 - t * 2.7 + phase)
		+ 0.25 * sin(t * 0.35 + phase);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	// Y-fixed billboard: main-camera right, model up, and the normal between them. MAIN_CAM_INV_VIEW_MATRIX stays
	// the main camera's in the shadow pass (INV_VIEW_MATRIX is the light's there), so the card that casts the
	// shadow is the card the camera sees and the sprite never shadows half of itself.
	vec4 right = MAIN_CAM_INV_VIEW_MATRIX[0];
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(right, MODEL_MATRIX[1],
			vec4(normalize(cross(right.xyz, MODEL_MATRIX[1].xyz)), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float h = clamp(1.0 - UV.y, 0.0, 1.0);  // 0 at the roots, 1 at the tip
	float w = gust(origin.xz, TIME) * gust_strength * h * h / max(stiffness, 0.01);
	vec2 away = origin.xz - player_world_pos.xz;
	float d = length(away);
	if (d < push_radius && d > 0.001) {
		// bend along the billboard's own x (camera right); full bend once the player is 0.25 m to one side
		float side = clamp(dot(away, normalize(right.xz + vec2(1e-5, 0.0))) * 4.0, -1.0, 1.0);
		w += side * (1.0 - d / push_radius) * push_strength * h;
	}
	VERTEX.x += round(w * height_m / pixel_m) * pixel_m;  // whole texels only
}

void fragment() {
	vec4 t = texture(sprite, UV);
	if (t.a < 0.5) {
		discard;
	}
	ALBEDO = t.rgb;
	EMISSION = t.rgb * night_emission * night_light;  // fades out by day with the clock
	ROUGHNESS = 0.95;
}
