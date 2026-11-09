// Key-colour emissive (proven in Chromaveil): pixels painted in one reserved key colour render as glow instead of
// paint. Uses: glowing eyes, runes, glyphs, screens, lit windows on a sprite. The art stays an ordinary PNG; the
// glow colour is a uniform, so the same frames can glow white, then a power's hue, with no new art.
// Included by key_emissive_billboard.gdshader (3D, black albedo + EMISSION) and key_emissive_canvas.gdshader (2D).
//
// Key rule: paint key pixels in the EXACT key (default #ff00ff, a colour no other art uses) and keep the key made
// of 0 / 255 channels, so the test reads the same in linear (3D) and sRGB (2D). The tolerance only absorbs
// import rounding.
// Cleanup rule (run it in your art checks before shipping): anti-aliased or resampled key pixels, those with
// r - g > 60 and b - g > 60 (0..255) that are not the exact key, fail is_key() and render as visible pink.
// Snap each one to the exact key or to its neighbour's colour.
uniform vec4 key_color : source_color = vec4(1.0, 0.0, 1.0, 1.0);
uniform float key_tolerance : hint_range(0.0, 0.5) = 0.1;
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float glow_boost = 1.6;  // above 1 feeds the Environment glow (bloom) on the HD-2D stack

bool is_key(vec3 c) {
	return all(lessThanEqual(abs(c - key_color.rgb), vec3(key_tolerance)));
}

vec3 key_glow() {
	return glow_color.rgb * glow_boost;
}
