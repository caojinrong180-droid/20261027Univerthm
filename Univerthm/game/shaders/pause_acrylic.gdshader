shader_type canvas_item;
render_mode unshaded;

// 暂停界面的亚克力板：把下层画面磨砂、去饱和、压暗，再叠上磨砂颗粒与板边受光，

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform float blur_px : hint_range(0.0, 16.0) = 6.5;   // 磨砂半径（1080p 下的像素数，换分辨率观感不变）
uniform float dim : hint_range(0.0, 1.0) = 0.5;        // 压暗，给图标留对比度
uniform float frost : hint_range(0.0, 1.0) = 0.8;      // 去饱和程度
uniform float lift : hint_range(0.0, 0.4) = 0.15;      // 板体自身的漫反射底光
uniform float grain : hint_range(0.0, 0.12) = 0.038;   // 磨砂颗粒
uniform float sheen : hint_range(0.0, 0.4) = 0.1;      // 斜面反光
uniform float rim : hint_range(0.0, 0.8) = 0.26;       // 板边高光
uniform vec4 tint : source_color = vec4(0.36, 0.26, 0.62, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 frost_tap(vec2 uv) {
	return texture(screen_tex, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
}

// 3×3 高斯；用三档步长各采一次再混合，凑出接近大半径的模糊
vec3 frost_blur(vec2 uv, vec2 step_px) {
	vec3 c = frost_tap(uv) * 0.25;
	c += (frost_tap(uv + vec2(step_px.x, 0.0)) + frost_tap(uv - vec2(step_px.x, 0.0))
		+ frost_tap(uv + vec2(0.0, step_px.y)) + frost_tap(uv - vec2(0.0, step_px.y))) * 0.125;
	c += (frost_tap(uv + step_px) + frost_tap(uv - step_px)
		+ frost_tap(uv + vec2(step_px.x, -step_px.y)) + frost_tap(uv + vec2(-step_px.x, step_px.y))) * 0.0625;
	return c;
}

void fragment() {
	// 半径按屏幕高度折算，窗口拉大缩小磨砂的粗细都一样。
	vec2 step_px = SCREEN_PIXEL_SIZE * blur_px * (1080.0 * SCREEN_PIXEL_SIZE.y);
	vec3 col = frost_blur(SCREEN_UV, step_px * 0.65);
	col = mix(col, frost_blur(SCREEN_UV, step_px * 1.7), 0.5);
	col = mix(col, frost_blur(SCREEN_UV, step_px * 3.2), 0.45);

	// 磨砂玻璃不保留底下的饱和色，再压一层冷紫底色。
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(luma), col, frost);
	col = mix(col, tint.rgb, 0.3);
	col = col * (1.0 - dim) + tint.rgb * lift;

	// 斜面受光：左上一道很淡的斜光，右下沉下去。
	col += tint.rgb * smoothstep(0.35, 1.05, (1.0 - UV.x) * 0.55 + (1.0 - UV.y) * 0.62) * sheen;
	float vignette = smoothstep(0.0, 0.9, length((UV - vec2(0.5)) * vec2(1.15, 1.0)));
	col *= 1.0 - vignette * 0.22;

	// 板边高光 + 磨砂颗粒：前者是亚克力的厚度感，后者是它的手感。
	vec2 edge = min(UV, vec2(1.0) - UV);
	col += tint.rgb * rim * (1.0 - smoothstep(0.0, 0.012, min(edge.x, edge.y)));
	float speck = (hash(FRAGCOORD.xy) - 0.5) * 0.85 + (hash(floor(FRAGCOORD.xy * 0.34)) - 0.5) * 0.15;
	col += speck * grain;

	COLOR = vec4(max(col, vec3(0.0)), 1.0) * COLOR;
}
