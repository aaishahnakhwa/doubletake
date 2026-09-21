shader_type canvas_item;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 pixel = UV / TEXTURE_PIXEL_SIZE;
	bool water_region =
		(pixel.x < 570.0 && pixel.y > 630.0) ||
		(pixel.x > 1400.0 && pixel.y > 345.0) ||
		(pixel.x > 1290.0 && pixel.y > 800.0);
	if (water_region && base.b > 0.2 && base.b > base.g * 1.4 && base.b > base.r * 1.5) {
		float long_wave = sin(pixel.x * 0.13 + TIME * 1.7) * sin(pixel.y * 0.08 - TIME * 1.1);
		float glint = pow(max(sin(pixel.x * 0.18 + pixel.y * 0.09 + TIME * 2.0), 0.0), 12.0);
		base.rgb += vec3(-0.008, 0.018, 0.036) * long_wave + vec3(0.018, 0.055, 0.08) * glint;
	}
	base.rgb *= vec3(0.91, 0.94, 1.0);
	COLOR = base;
}
