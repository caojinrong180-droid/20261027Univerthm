shader_type canvas_item;
render_mode unshaded;

uniform float motion_strength : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform vec2 pointer_offset = vec2(0.0);
uniform float motion_time = 0.0;
uniform float overscan : hint_range(1.04, 1.15, 0.005) = 1.06;
uniform float breathing_zoom : hint_range(0.0, 0.015, 0.001) = 0.006;
uniform vec2 parallax_amount = vec2(0.0065, 0.005);

varying vec4 node_tint;

void vertex() {
	node_tint = COLOR;
}

void fragment() {
	// 整张图平滑推拉，保留黑洞光环的形状；预留边缘覆盖鼠标视差。
	float breath = 0.5 + 0.5 * sin(motion_time * 0.72);
	float zoom = overscan + breath * breathing_zoom * motion_strength;
	vec2 uv = (UV - vec2(0.5)) / zoom + vec2(0.5);
	vec2 drift = vec2(sin(motion_time * 0.31) * 0.0015,
		cos(motion_time * 0.27) * 0.001);
	uv += (drift - pointer_offset * parallax_amount) * motion_strength;
	vec4 art = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0)));
	// 紫色星云随同一呼吸周期轻微明暗起伏。
	float violet = smoothstep(0.015, 0.12, art.b - art.g) * smoothstep(0.0, 0.08, art.r - art.g);
	art.rgb *= 1.0 + sin(motion_time * 0.72) * violet * 0.015 * motion_strength;
	COLOR = art * node_tint;
}
