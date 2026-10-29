shader_type canvas_item;
render_mode unshaded;

// A self-lit ribbon: the glow is procedural, so Compatibility needs no bloom pass.
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform vec2 wave_center = vec2(0.428, 0.5);
uniform vec4 glow_color : source_color = vec4(0.49, 0.16, 0.90, 1.0);
uniform float intensity : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float motion_speed : hint_range(0.0, 1.0, 0.05) = 0.45;
uniform float glitch_amount : hint_range(0.0, 1.0, 0.05) = 0.45;
uniform float wave_amount : hint_range(0.0, 1.0, 0.05) = 0.7;
// 警告页保留不透明背景；主菜单以透明光晕叠加在原图上。
uniform bool overlay_mode = false;
uniform float reveal_progress : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float reveal_feather : hint_range(0.02, 0.25, 0.01) = 0.12;

varying vec4 node_tint;

void vertex() {
	node_tint = COLOR;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise21(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), f.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), f.x), f.y);
}

float cloud(vec2 p) {
	return noise21(p) * 0.57 + noise21(p * 2.13 + 7.2) * 0.28
		+ noise21(p * 4.37 - 3.1) * 0.15;
}

void fragment() {
	vec2 uv = UV;
	float front = mix(-reveal_feather, 1.0 + reveal_feather, reveal_progress);
	float reveal = 1.0 - smoothstep(front - reveal_feather, front + reveal_feather, uv.x);
	if (reveal <= 0.0001 || (overlay_mode && abs(uv.y - wave_center.y) > 0.35)) {
		discard;
	}
	float aspect = viewport_size.x / max(viewport_size.y, 1.0);
	float t = TIME * motion_speed;
	vec2 local = vec2((uv.x - wave_center.x) * aspect, uv.y - wave_center.y);

	// Long horizontal slices slip sideways; changes fade in and out, never strobe.
	float epoch = floor(t * 1.7);
	float slice = floor(uv.y * 155.0);
	float slice_random = hash21(vec2(slice, epoch));
	float glitch_pulse = pow(sin(fract(t * 1.7) * 3.14159265), 4.0);
	float cut = smoothstep(0.81, 0.97, slice_random) * glitch_pulse * glitch_amount;
	float x = uv.x + (slice_random - 0.5) * cut * 0.12;

	// A confined oscillation lifts the ribbon just left of the text's midpoint.
	float focus = exp(-pow(local.x / 0.27, 2.0));
	float wave = sin(local.x * 27.0 - t * 2.2) * focus * 0.048 * wave_amount;
	float spine = wave_center.y + sin(x * 5.4 - t * 0.55) * 0.018
		+ sin(x * 13.0 + t * 0.32) * 0.006 + wave;
	float distortion = (cloud(vec2(x * 9.0 - t * 0.18, uv.y * 7.0)) - 0.5);
	float d = uv.y - spine + distortion * 0.012
		+ (slice_random - 0.5) * cut * 0.048;
	float width = 0.045 + noise21(vec2(x * 4.0 + t * 0.1, 4.7)) * 0.035;
	float breath = 0.92 + sin(t * 1.15) * 0.08;
	float edge_fade = 0.48 + 0.52 * pow(max(sin(uv.x * 3.14159265), 0.0), 0.6);

	// Broad indigo atmosphere, a violet halo, and fine luminous filaments.
	float fog = exp(-pow(d / (width * 2.4), 2.0));
	float halo = exp(-pow(d / width, 2.0));
	float inner = exp(-abs(d) / 0.014);
	float filament_a = exp(-abs(d - sin(x * 18.0 + t) * 0.004) / 0.0015);
	float filament_b = exp(-abs(d + 0.011 + sin(x * 12.0 - t) * 0.005) / 0.0010);
	float fragments = 0.35 + 0.65 * smoothstep(0.24, 0.77,
		noise21(vec2(x * 32.0 - t * 0.6, 9.8)));

	vec3 light = vec3(0.095, 0.028, 0.21) * fog * 0.54;
	light += glow_color.rgb * halo * (0.12 + distortion * 0.08);
	light += glow_color.rgb * inner * 0.33;
	light += vec3(0.64, 0.37, 0.95) * filament_a * fragments * 0.48;
	light += vec3(0.30, 0.15, 0.70) * filament_b * 0.24;

	// Soft elliptical wavefronts expand through the same local patch of light.
	float radius = length(vec2(local.x * 0.8, local.y * 1.45));
	float phase = radius * 47.0 - t * 2.2;
	float rings = pow(0.5 + 0.5 * cos(phase), 15.0);
	float ring_fade = exp(-radius * 8.5) * smoothstep(0.018, 0.065, radius);
	float ring_breaks = 0.40 + 0.60 * noise21(local * 16.0 + t * 0.1);
	light += glow_color.rgb * rings * ring_fade * ring_breaks * wave_amount * 0.13;

	// Sparse chromatic seams and short digital fragments stay inside the halo.
	float seam = exp(-abs(d + 0.006 + cut * 0.10) / 0.0012);
	light += vec3(0.38, 0.13, 0.67) * seam * cut * 0.85;
	vec2 shard_grid = vec2(uv.x * 21.0, (uv.y - wave_center.y) * 110.0);
	vec2 shard_uv = fract(shard_grid);
	float shard_seed = hash21(floor(shard_grid) + vec2(epoch, epoch + 17.0));
	float shard_shape = (1.0 - smoothstep(0.24, 0.48, abs(shard_uv.x - 0.5)))
		* (1.0 - smoothstep(0.07, 0.19, abs(shard_uv.y - 0.5)));
	float shards = smoothstep(0.82, 0.98, shard_seed) * shard_shape;
	light += glow_color.rgb * shards * exp(-abs(d) / 0.038)
		* glitch_pulse * glitch_amount * 0.65;
	float scan = pow(0.5 + 0.5 * sin(uv.y * viewport_size.y * 3.14159265), 12.0);
	light *= 0.96 + scan * 0.04;
	if (overlay_mode) {
		float leading = exp(-pow((uv.x - front) / 0.035, 2.0)) * halo;
		light += glow_color.rgb * leading * 0.14;
		float vertical_fade = 1.0 - smoothstep(0.23, 0.35, abs(uv.y - wave_center.y));
		float alpha = fog * 0.24 + halo * 0.25 + inner * 0.28 + filament_a * 0.24;
		alpha = min(alpha * intensity, 0.86) * reveal * vertical_fade;
		COLOR = vec4(light * 2.4 * intensity * breath * edge_fade, alpha) * node_tint;
	} else {

		vec3 base = vec3(0.024, 0.026, 0.039);
		float vignette = 1.0 - smoothstep(0.32, 0.88, length((uv - 0.5) * vec2(0.85, 1.0)));
		vec3 color = base + light * intensity * breath * edge_fade;
		color *= 0.77 + vignette * 0.23;
		float grain = (hash21(floor(uv * viewport_size)) - 0.5) / 420.0;
		COLOR = vec4(max(color + grain, vec3(0.0)), reveal) * node_tint;
	}
}
