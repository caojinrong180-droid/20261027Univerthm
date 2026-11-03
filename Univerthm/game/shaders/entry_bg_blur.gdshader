shader_type canvas_item;
render_mode unshaded;

// 进入过场时给背景加的一层虚化：BackBufferCopy 先抄下此刻的画面，这里把它磨砂，再整层淡进来
//（虚化程度 = 这一层的 alpha，所以「飞过去」的同时背景一点点糊掉）。
// 采样是「密过像素」的 9×9 高斯：步长只有 blur_px/4，相邻采样点自带双线性脚印，
// 所以不会像「少采样点 + 大半径」那样在高对比的地方（左上角 logo、右上角文字）拉出两三份重影。
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float blur_px : hint_range(0.0, 32.0) = 12.0;   // 磨砂半径（1080p 下的像素数）
uniform float dim : hint_range(0.0, 0.6) = 0.14;        // 顺手压一点暗，让中间那块更跳

vec3 tap(vec2 uv) {
	return texture(screen_tex, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
}

void fragment() {
	// 半径按屏幕高度折算，换分辨率磨砂的粗细不变
	vec2 step_px = SCREEN_PIXEL_SIZE * blur_px * (1080.0 * SCREEN_PIXEL_SIZE.y) * 0.25;
	vec3 col = vec3(0.0);
	float total = 0.0;
	for (int y = -4; y <= 4; y++) {
		for (int x = -4; x <= 4; x++) {
			vec2 p = vec2(float(x), float(y));
			float weight = exp(-dot(p, p) * 0.11);
			col += tap(SCREEN_UV + p * step_px) * weight;
			total += weight;
		}
	}
	col = col / total * (1.0 - dim);
	COLOR = vec4(max(col, vec3(0.0)), 1.0) * COLOR;
}
