// Presentation pass applied to the low-resolution world viewport.
// Tilt-shift blur (HD-2D miniature look), vignette, subtle grade and
// optional damage / low-health / slow-motion treatments for combat.
shader_type canvas_item;

uniform float focus_y = 0.55;        // focal band centre (0 top .. 1 bottom)
uniform float focus_half = 0.20;     // half-height of the sharp band
uniform float blur_max = 2.2;        // in source texels
uniform float vignette = 0.55;
uniform vec4 grade_shadow : source_color = vec4(0.10, 0.13, 0.20, 1.0);
uniform vec4 grade_light : source_color = vec4(1.0, 0.93, 0.82, 1.0);
uniform float grade_amount = 0.22;
uniform float damage_flash = 0.0;    // red pulse when hit
uniform float low_health = 0.0;      // desaturate + pulse edges
uniform float slowmo = 0.0;          // cool desaturation for slow-motion windows
uniform float impact = 0.0;          // monochrome impact frame (crits)
uniform float prism = 0.0;           // Loadout refraction
uniform float counter = 0.0;         // counter-window frame (distinct from crit impact)
uniform float freeze = 0.0;          // final-blow freeze frame: ink/oxblood/gilt duotone + speed lines
uniform vec2 freeze_center = vec2(0.5, 0.5);
// A quarter-size copy of the view (downsample4.gdshader: each texel the mean of a 4 x 4 block; PixelView binds
// one). With it (quarter_ready true) the blur is 7 taps read from the copy, the centre and a fixed ring of six with
// flat weights, smooth at any radius and any render scale; without it the 5 x 5 taps below run unchanged, so other
// users keep their look.
uniform sampler2D quarter_tex : filter_linear, repeat_disable;
uniform bool quarter_ready = false;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float d = abs(UV.y - focus_y);
	float b = smoothstep(focus_half, focus_half + 0.32, d) * blur_max;
	vec3 col;
	if (quarter_ready) {
		col = texture(TEXTURE, UV).rgb;
		if (b >= 0.15) {
			// r in quarter texels: b source texels / 4, at least 0.5; the ring sits at r x 0.75. The copy already holds
			// each 4 x 4 block's mean, so one ring of six bilinear taps is enough: 7 taps, 0.25 + 6 x 0.125 = 1
			vec2 q = 1.0 / vec2(textureSize(quarter_tex, 0));
			float r = max(b / 4.0, 0.5);
			vec3 blur = texture(quarter_tex, UV).rgb * 0.25;
			for (int i = 0; i < 6; i++) {
				float a = float(i) * 1.0472;  // 60 degrees apart
				blur += texture(quarter_tex, UV + vec2(cos(a), sin(a)) * r * 0.75 * q).rgb * 0.125;
			}
			col = mix(col, blur, smoothstep(0.15, 1.0, b));
		}
	} else if (b < 0.25) {
		col = texture(TEXTURE, UV).rgb;
	} else {
		col = vec3(0.0);
		float tot = 0.0;
		for (int i = -2; i <= 2; i++) {
			for (int j = -2; j <= 2; j++) {
				vec2 o = vec2(float(i), float(j)) * px * b * 0.6;
				float w = 1.0 / (1.0 + float(i * i + j * j));
				col += texture(TEXTURE, UV + o).rgb * w;
				tot += w;
			}
		}
		col /= tot;
	}
	if (prism > 0.0) {
		vec2 dir = (UV - 0.5) * prism * 0.012;
		col.r = mix(col.r, texture(TEXTURE, UV + dir).r, prism);
		col.b = mix(col.b, texture(TEXTURE, UV - dir).b, prism);
	}
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 graded = mix(grade_shadow.rgb, grade_light.rgb, lum) * lum * 1.6;
	col = mix(col, graded, grade_amount);
	vec2 v = UV - 0.5;
	float vig = 1.0 - dot(v, v) * vignette * 1.6;
	col *= vig;
	if (slowmo > 0.0) {
		// slow motion reads at the edges only: a cool, quiet vignette
		float se = smoothstep(0.3, 0.7, length(v * vec2(1.0, 1.3)));
		col = mix(col, vec3(lum) * vec3(0.7, 0.86, 1.1), slowmo * se * 0.7);
	}
	if (low_health > 0.0) {
		float edge = smoothstep(0.15, 0.55, length(v));
		col = mix(col, vec3(lum), low_health * 0.5);
		col += vec3(0.5, 0.02, 0.04) * edge * low_health * (0.6 + 0.4 * sin(TIME * 5.0));
	}
	col += vec3(0.6, 0.05, 0.05) * damage_flash;
	if (counter > 0.0) {
		// counter window: a gold pulse breathing in from the screen edges
		float ce = smoothstep(0.26, 0.66, length(v * vec2(1.0, 1.3)));
		float beat = 0.55 + 0.45 * sin(TIME * 16.0);
		vec3 gold = vec3(1.0, 0.8, 0.38);
		col = mix(col, gold * (0.6 + lum), counter * ce * beat * 0.75);
		float rim = smoothstep(0.47, 0.5, max(abs(v.x), abs(v.y)));
		col = mix(col, gold * 1.3, counter * rim * beat);
	}
	if (impact > 0.0) {
		float m = step(0.33, lum);
		col = mix(col, vec3(m), impact);
	}
	if (freeze > 0.0) {
		float l2 = dot(col, vec3(0.299, 0.587, 0.114));
		// three-tone ink print: deep ink, oxblood mids, gilt-ivory lights
		vec3 ink = vec3(0.06, 0.04, 0.08);
		vec3 ox = vec3(0.48, 0.12, 0.17);
		vec3 gl = vec3(0.98, 0.9, 0.7);
		vec3 tone = l2 < 0.22 ? ink : (l2 < 0.5 ? mix(ox, ink, 0.25) : mix(ox, gl, smoothstep(0.5, 0.8, l2)));
		// halftone in the mids
		vec2 cell = fract(SCREEN_UV * vec2(textureSize(TEXTURE, 0)) / 3.0) - 0.5;
		float dotm = step(length(cell), 0.35 * (1.0 - l2));
		tone = mix(tone, tone * 0.7, dotm * step(0.22, l2) * 0.6);
		// radial speed lines converging on the blow
		vec2 d = UV - freeze_center;
		float ang = atan(d.y, d.x);
		float rays = step(0.86, fract(sin(floor(ang * 70.0)) * 43758.5453));
		float far = smoothstep(0.18, 0.55, length(d * vec2(1.6, 1.0)));
		tone = mix(tone, gl, rays * far * 0.55);
		col = mix(col, tone, freeze);
	}
	COLOR = vec4(col, 1.0);
}
