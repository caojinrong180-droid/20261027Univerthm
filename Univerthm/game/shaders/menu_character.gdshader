shader_type canvas_item;
render_mode unshaded;

uniform float motion_strength : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float sway : hint_range(0.0, 0.015, 0.0005) = 0.005;
uniform float cloth_sway : hint_range(0.0, 0.05, 0.001) = 0.026;
uniform float cloth_lift : hint_range(0.0, 0.02, 0.001) = 0.009;

varying vec4 node_tint;

void vertex() {
	node_tint = COLOR;
}

void fragment() {
	vec2 uv = UV;
	// 只轻摆外围的发梢、衣摆，面部和身体中央保持稳定。
	float sides = smoothstep(0.10, 0.38, abs(uv.x - 0.5));
	float lower = smoothstep(0.16, 0.46, uv.y);
	float feet_pin = 1.0 - smoothstep(0.86, 1.0, uv.y);
	float edge_pin = smoothstep(0.0, 0.055, min(uv.x, 1.0 - uv.x));
	float weight = sides * lower * feet_pin * edge_pin * motion_strength;
	float drift = sin(TIME * 1.15 - uv.y * 5.0) * 0.72
		+ sin(TIME * 1.8 + uv.y * 10.0) * 0.28;
	uv.x += drift * sway * weight;
	uv.y += sin(TIME * 1.3 + uv.x * 7.0) * sway * weight * 0.25;
	// 衣角单独加大摆幅，越靠下、越靠外缘越明显，不拉扯脸和手部。
	float cloth = smoothstep(0.28, 0.60, UV.y)
		* (1.0 - smoothstep(0.82, 1.0, UV.y)) * sides * edge_pin * motion_strength;
	float cloth_phase = TIME * 1.45 - UV.y * 7.0 + UV.x * 3.0;
	float flutter = sin(cloth_phase) * 0.74 + sin(TIME * 2.6 - UV.y * 13.0) * 0.26;
	uv.x += flutter * cloth_sway * cloth;
	uv.y += (cos(cloth_phase * 0.9) * 0.65 + sin(TIME * 1.8 + UV.x * 5.0) * 0.35)
		* cloth_lift * cloth;
	COLOR = texture(TEXTURE, uv) * node_tint;
}
