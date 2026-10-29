shader_type canvas_item;
render_mode unshaded;

uniform sampler2D scene_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 region_a = vec4(0.1, 0.5, 0.25, 0.07);
uniform vec4 region_b = vec4(0.6, 0.6, 0.16, 0.04);
uniform vec4 protected_rect = vec4(0.65, 0.1, 0.21, 0.3);
uniform float burst_phase : hint_range(0.0, 1.0) = 1.0;
uniform float burst_seed = 0.0;
uniform float strength : hint_range(0.0, 2.0, 0.05) = 1.0;

varying vec4 node_tint;

void vertex() {
	node_tint = COLOR;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float box_mask(vec2 p, vec4 rect) {
	vec2 q = (p - rect.xy) / max(rect.zw, vec2(0.0001));
	vec2 edge = min(q, 1.0 - q);
	return smoothstep(0.0, 0.025, edge.x) * smoothstep(0.0, 0.08, edge.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float a = box_mask(uv, region_a);
	float b = box_mask(uv, region_b);
	float mask = max(a, b) * (1.0 - box_mask(uv, protected_rect));
	if (mask < 0.001 || burst_phase >= 1.0) {
		discard;
	}
	vec4 region = a >= b ? region_a : region_b;
	vec2 local = (uv - region.xy) / max(region.zw, vec2(0.0001));
	float row = floor(local.y * 9.0);
	float tick = floor(burst_phase * 6.0);
	float random = hash21(vec2(row + burst_seed, tick + burst_seed));
	float offset = (random - 0.5) * 0.045 * strength;
	vec2 shift = vec2(offset, (hash21(vec2(row, burst_seed)) - 0.5) * 0.003 * strength);
	float split = (0.0015 + random * 0.0025) * strength;
	vec3 image = vec3(
		texture(scene_texture, clamp(uv + shift + vec2(split, 0.0), vec2(0.0), vec2(1.0))).r,
		texture(scene_texture, clamp(uv + shift, vec2(0.0), vec2(1.0))).g,
		texture(scene_texture, clamp(uv + shift - vec2(split, 0.0), vec2(0.0), vec2(1.0))).b);
	float stripe = step(0.78, hash21(vec2(row + 9.0, burst_seed + tick)));
	image = mix(image, vec3(0.48, 0.13, 0.78), stripe * 0.25 * min(strength, 1.0));
	// 一次故障包含两个短促切片，持续片刻后完全恢复。
	float shutter = (burst_phase < 0.32 || (burst_phase > 0.46 && burst_phase < 0.86)) ? 1.0 : 0.12;
	float envelope = smoothstep(0.0, 0.06, burst_phase) * (1.0 - smoothstep(0.84, 1.0, burst_phase));
	COLOR = vec4(image, mask * shutter * envelope * min(strength, 1.0)) * node_tint;
}
