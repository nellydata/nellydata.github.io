// Quarter-size copy of the world view for the tilt-shift blur (tilt_shift.gdshader, quarter_tex) (proven in
// Sonder (then Chromaveil) 0.13). Each output texel is the mean of a 4 x 4 block of the view: four bilinear taps
// one source texel either side of its centre, each tap the mean of a 2 x 2 quad. Draw it with a TextureRect with
// linear filtering, sized to fill a SubViewport a quarter of the view's size; PixelView does this.
shader_type canvas_item;

void fragment() {
	vec2 s = TEXTURE_PIXEL_SIZE;  // one source texel
	vec3 c = texture(TEXTURE, UV + vec2(-1.0, -1.0) * s).rgb
		+ texture(TEXTURE, UV + vec2(1.0, -1.0) * s).rgb
		+ texture(TEXTURE, UV + vec2(-1.0, 1.0) * s).rgb
		+ texture(TEXTURE, UV + vec2(1.0, 1.0) * s).rgb;
	COLOR = vec4(c * 0.25, 1.0);
}
