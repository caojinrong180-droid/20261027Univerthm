shader_type canvas_item;
render_mode unshaded;

uniform float blur_radius : hint_range(0.0, 0.06) = 0.025;

void fragment() {
	vec3 col = vec3(0.0);
	float total = 0.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 p = vec2(float(x), float(y));
			float weight = exp(-dot(p, p) * 0.42);
			col += textureLod(TEXTURE, clamp(UV + p * blur_radius, vec2(0.0), vec2(1.0)), 1.0).rgb * weight;
			total += weight;
		}
	}
	col /= total;
	// 明亮曲绘也保持文本对比度，曲绘仍可辨认。
	float shade = mix(0.12, 0.28, smoothstep(0.1, 0.9, UV.x));
	float vignette = 1.0 - smoothstep(0.28, 0.83, distance(UV, vec2(0.6, 0.43)));
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(luma * 0.85, luma * 0.58, luma * 1.18), 0.28);
	col = col * shade * (0.65 + vignette * 0.35) + vec3(0.018, 0.004, 0.035);
	COLOR = vec4(col, 1.0) * COLOR;
}
