shader_type canvas_item;

void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	float max_channel = max(ink.r, max(ink.g, ink.b));
	float min_channel = min(ink.r, min(ink.g, ink.b));
	float chroma = max_channel - min_channel;
	// The extracted sheet has a baked neutral checkerboard. Keep coloured
	// paint, dark outlines and bright shoe highlights; discard neutral greys.
	float coloured = smoothstep(0.055, 0.13, chroma);
	float outline = 1.0 - smoothstep(0.28, 0.42, max_channel);
	float highlight = smoothstep(0.89, 0.94, max_channel);
	float coverage = max(coloured, max(outline, highlight));
	COLOR = vec4(ink.rgb, ink.a * coverage);
}
