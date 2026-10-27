shader_type canvas_item;
// 故事板后处理（和网页 web/js/sb_render.js 的 FRAG 一一对应）
// 用法：每个生效的 shader 一层 ColorRect，配一个 ShaderMaterial；层与层之间插 BackBufferCopy，
// 这样第 N 层读到的就是第 N-1 层的输出（真正的逐层叠加，不是合并成一个 pass）。

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform vec2 u_res = vec2(1280.0, 720.0);
uniform float u_time = 0.0;

uniform float u_bloom = 0.0;
uniform float u_rgb = 0.0;
uniform float u_scan = 0.0;
uniform float u_wave = 0.0;
uniform float u_glitch = 0.0;
uniform float u_heat = 0.0;
uniform float u_pixel = 0.0;
uniform float u_poster = 0.0;
uniform float u_grain = 0.0;
uniform float u_vignette = 0.0;
uniform float u_invert = 0.0;
uniform float u_stretch = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 sample3(vec2 uv, vec2 off) {
	return vec3(
		texture(screen_tex, clamp(uv + off, vec2(0.0), vec2(1.0))).r,
		texture(screen_tex, clamp(uv, vec2(0.0), vec2(1.0))).g,
		texture(screen_tex, clamp(uv - off, vec2(0.0), vec2(1.0))).b);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = u_time;

	if (u_wave > 0.001) {
		uv.x += sin(uv.y * 24.0 + t * 3.0) * 0.0045 * u_wave;
		uv.y += cos(uv.x * 18.0 + t * 2.4) * 0.0032 * u_wave;
	}

	if (u_heat > 0.001) {
		uv.x += sin(uv.y * 92.0 + t * 9.0) * 0.0032 * u_heat;
		uv.y += sin(uv.x * 61.0 - t * 7.0) * 0.0024 * u_heat;
	}

	if (u_glitch > 0.001) {
		float band = floor(uv.y * 26.0);
		float r = hash(vec2(band, floor(t * 14.0)));
		if (r > 0.72) uv.x += (r - 0.86) * 0.10 * u_glitch;
		float r2 = hash(vec2(floor(uv.x * 16.0), floor(t * 9.0) + 3.0));
		if (r2 > 0.93) uv.y += (r2 - 0.965) * 0.14 * u_glitch;
	}

	if (u_pixel > 0.001) {
		vec2 cells = mix(u_res, vec2(28.0, 16.0), 0.82 * u_pixel);
		uv = (floor(uv * cells) + 0.5) / cells;
	}

	if (u_stretch > 0.001) {
		// 四角拉伸：角上的采样点往中心收（角落内容被拽出去），边和中心几乎不动
		vec2 sp = uv - 0.5;
		vec2 sa = abs(sp) * 2.0;
		float corner = pow(sa.x * sa.y, 1.3);
		float edge = max(sa.x, sa.y);
		float k = u_stretch * (0.16 * corner + 0.03 * edge * edge * edge);
		uv = 0.5 + sp * (1.0 - clamp(k, 0.0, 0.35));
	}

	uv = clamp(uv, vec2(0.0), vec2(1.0));
	vec2 off = vec2(u_rgb * 0.006 + u_heat * 0.0015, 0.0);
	vec3 col = sample3(uv, off);

	if (u_bloom > 0.001) {
		float rad = 0.0042 * u_bloom + 0.0012;
		vec3 sum = vec3(0.0);
		float wsum = 0.0;
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.7853981;
			vec2 dir = vec2(cos(a), sin(a));
			sum += texture(screen_tex, clamp(uv + dir * rad, vec2(0.0), vec2(1.0))).rgb;
			sum += texture(screen_tex, clamp(uv + dir * rad * 2.6, vec2(0.0), vec2(1.0))).rgb * 0.55;
			wsum += 1.55;
		}
		vec3 bl = sum / wsum;
		col += bl * bl * u_bloom * 1.4;
	}

	if (u_poster > 0.001) {
		float levels = mix(64.0, 4.0, u_poster);
		col = floor(col * levels + 0.5) / levels;
	}

	if (u_scan > 0.001) {
		float s = sin(uv.y * u_res.y * 1.7 + t * 8.0) * 0.5 + 0.5;
		col *= 1.0 - u_scan * 0.26 * s;
		col *= 1.0 - u_scan * 0.08 * (sin(uv.y * u_res.y * 26.0) * 0.5 + 0.5);
	}

	if (u_grain > 0.001) {
		col += (hash(uv * u_res + t * 60.0) - 0.5) * u_grain * 0.17;
	}

	if (u_vignette > 0.001) {
		vec2 d = uv - 0.5;
		float v = smoothstep(0.86, 0.24, length(d) * 1.36);
		col *= mix(1.0, v, u_vignette);
	}

	col = mix(col, vec3(1.0) - col, clamp(u_invert, 0.0, 1.0) * 0.9);
	COLOR = vec4(col, 1.0);
}
