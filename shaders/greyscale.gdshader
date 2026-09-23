shader_type canvas_item;

uniform float desaturation : hint_range(0.0, 1.0) = 1.0;
uniform float brightness : hint_range(0.5, 1.5) = 0.95;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float gray = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	vec3 final_rgb = mix(col.rgb, vec3(gray), desaturation) * brightness;
	COLOR = vec4(final_rgb, col.a);
}
