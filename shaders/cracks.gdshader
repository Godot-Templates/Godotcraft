shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_opaque, cull_disabled;

// Cracks texture: white background, dark crack lines.
uniform sampler2D cracks_tex : source_color, filter_nearest;
// 0.0 = block unchanged. 1.0 = cracks at full strength.
uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float t = texture(cracks_tex, UV).r;
	// The texture's darkest crack pixel is ~0.71 (very light gray).
	// Remap [0.7, 0.95] → [0, 1] so crack lines collapse to ~0 and the
	// background stays at 1.0 — then MUL by 0 actually blackens the block.
	t = smoothstep(0.7, 0.95, t);
	float mul = mix(1.0, t, progress);
	ALBEDO = vec3(mul);
}
