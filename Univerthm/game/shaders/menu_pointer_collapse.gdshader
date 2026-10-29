shader_type canvas_item;
render_mode unshaded;

uniform sampler2D scene_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform vec4 effect_bounds = vec4(0.0, 0.0, 1280.0, 720.0);
uniform vec4 trail_points[32];
uniform int trail_count = 0;
uniform float radius_px : hint_range(20.0, 140.0) = 38.0;
uniform float strength : hint_range(0.0, 1.5) = 0.85;

varying vec4 node_tint;

void vertex() {
	node_tint = COLOR;
	// 只栅格化轨迹周围的区域，控件布局和鼠标坐标仍保持全屏。
	VERTEX = effect_bounds.xy + VERTEX / max(viewport_size, vec2(1.0)) * effect_bounds.zw;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 pixel = SCREEN_UV * viewport_size;
	vec2 displacement = vec2(0.0);
	vec2 center_sum = vec2(0.0);
	float weight_sum = 0.0;
	float peak = 0.0;
	float age_sum = 0.0;
	float radius_sum = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= trail_count) {
			break;
		}
		vec4 point = trail_points[i];
		vec2 center = point.xy * viewport_size;
		vec2 delta = pixel - center;
		float point_radius = radius_px * point.w;
		float distance = length(delta) / max(point_radius, 1.0);
		float life = pow(max(1.0 - point.z, 0.0), 1.25);
		float weight = pow(1.0 - smoothstep(0.0, 1.0, distance), 1.2) * life;
		// 向外取样把图像内容压向中心，并带一点旋转坍缩。
		displacement += (delta * 0.85 + vec2(-delta.y, delta.x) * 0.16) * weight;
		center_sum += center * weight;
		age_sum += point.z * weight;
		radius_sum += point_radius * weight;
		weight_sum += weight;
		peak = max(peak, weight);
	}
	if (peak < 0.002 || strength <= 0.0) {
		discard;
	}
	vec2 center = center_sum / max(weight_sum, 0.0001);
	float age = age_sum / max(weight_sum, 0.0001);
	float local_radius = radius_sum / max(weight_sum, 0.0001);
	vec2 delta = pixel - center;
	float distance = length(delta) / max(local_radius, 1.0);
	vec2 radial = delta / max(length(delta), 1.0);
	vec2 sample_pixel = pixel + displacement / max(weight_sum, 1.0) * strength;

	// 方块收拢和径向色散，与随机故障的横向切片采用不同画法。
	float cell_size = mix(2.0, 11.0, peak * clamp(local_radius / max(radius_px, 1.0), 0.0, 1.0));
	vec2 cell = floor((pixel - center) / cell_size);
	float random = hash21(cell + floor(TIME * 9.0));
	float fracture = smoothstep(0.78, 0.98, random) * peak;
	vec2 mosaic = (floor(sample_pixel / cell_size) + 0.5) * cell_size;
	sample_pixel = mix(sample_pixel, mosaic, peak * 0.58 * min(strength, 1.0));
	sample_pixel += (radial + vec2(-radial.y, radial.x) * 0.4)
		* (random - 0.5) * fracture * 14.0 * strength;
	vec2 split = radial * peak * (1.8 + fracture * 3.5) * strength;
	vec3 image = vec3(
		texture(scene_texture, clamp((sample_pixel + split) / viewport_size, vec2(0.0), vec2(1.0))).r,
		texture(scene_texture, clamp(sample_pixel / viewport_size, vec2(0.0), vec2(1.0))).g,
		texture(scene_texture, clamp((sample_pixel - split) / viewport_size, vec2(0.0), vec2(1.0))).b);
	float core = exp(-pow(distance / 0.27, 2.0)) * peak;
	image *= 1.0 - core * 0.24 * min(strength, 1.0);
	image = mix(image, vec3(0.24, 0.07, 0.52), fracture * 0.21 * min(strength, 1.0));
	float angle = atan(delta.y, delta.x);
	float arcs = pow(0.5 + 0.5 * sin(angle * 7.0 + age * 5.0), 8.0);
	float ring = exp(-pow((distance - (0.78 - age * 0.4)) / 0.035, 2.0));
	image += vec3(0.27, 0.09, 0.48) * ring * arcs * peak * 0.34;
	COLOR = vec4(image, min(peak * 1.4, 1.0)) * node_tint;
}
