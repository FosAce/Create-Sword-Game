// ============================================================
//  箱庭海水：一块被"切开"的水体，顶面是浅滩→深海渐变，
//  侧面是剖切面（浅青色到深蓝），岸边有白色泡沫环。
// ============================================================
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec3 c_shallow : source_color = vec3(0.46, 0.86, 0.81);
uniform vec3 c_mid : source_color = vec3(0.22, 0.66, 0.70);
uniform vec3 c_deep : source_color = vec3(0.10, 0.40, 0.52);
uniform vec3 c_foam : source_color = vec3(0.97, 1.0, 0.99);
uniform vec3 c_cut : source_color = vec3(0.55, 0.86, 0.86);
uniform vec3 c_ink : source_color = vec3(0.12, 0.34, 0.42);
uniform float island_radius = 7.4;
uniform vec2 island_center = vec2(0.0, 0.0);
uniform float water_top = 0.0;
uniform float water_bottom = -1.35;
uniform float seed = 4.0;
uniform float shimmer = 1.0;

varying vec3 vwp;
varying vec3 vwn;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031 + seed * 0.021);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(i);
	float b = h21(i + vec2(1.0, 0.0));
	float c = h21(i + vec2(0.0, 1.0));
	float d = h21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	vwp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vwn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float r = length(vwp.xz - island_center);
	// 0 = 远离岛（深），1 = 贴近岛（浅）
	float shore = 1.0 - smoothstep(island_radius * 0.72, island_radius * 2.05, r);
	shore = clamp(shore, 0.0, 1.0);

	vec2 p = vwp.xz * 0.55;
	float w = fbm(p * 1.7 + vec2(TIME * 0.045, TIME * 0.028));
	float w2 = fbm(p * 4.2 - vec2(TIME * 0.03, TIME * 0.05));

	if (vwn.y > 0.65) {
		// ---------- 水面 ----------
		vec3 col = mix(c_deep, c_mid, smoothstep(0.05, 0.55, shore));
		col = mix(col, c_shallow, smoothstep(0.55, 0.95, shore));
		col *= 0.95 + 0.10 * w;
		// 水下砂石透出来的浅色斑
		col = mix(col, c_shallow * 1.06, smoothstep(0.72, 1.0, shore) * (0.35 + 0.3 * w2));

		// ---------- 卷浪冲岸 ----------
		vec2 dv = vwp.xz - island_center;
		float ang = atan(dv.y, dv.x);
		float wave_len = island_radius * 0.26;
		// 用正弦波列代替 fract 分带：正弦处处连续，不会有"台阶"和循环接缝
		float phw = (r - island_radius * 0.50) / wave_len * 6.28318 + TIME * 1.15;
		float swell = sin(phw);
		// 角向噪声改用"单位方向向量"取样，避开 atan 在 ±π 处的不连续
		vec2 adir = vec2(cos(ang), sin(ang));
		float brk = fbm(adir * 2.4 + vec2(r * 0.30, TIME * 0.07));
		// 浪峰：只取正弦上升的一段，两头都软
		float crest = smoothstep(0.30, 0.98, swell);
		crest *= 0.25 + 0.95 * brk;
		float near_shore = 1.0 - smoothstep(island_radius * 0.98, island_radius * 1.45, r);
		float surf = clamp(crest * near_shore, 0.0, 1.0);
		col = mix(col, c_foam * 0.96, surf * 0.78);

		// ---------- 浪纹墨线（水纹线）----------
		// 在正弦的两个相位上各画一条细线，被噪声打断，只在近岸出现
		float l1 = smoothstep(0.075, 0.020, abs(swell - 0.55));
		float l2 = smoothstep(0.055, 0.015, abs(swell + 0.30)) * 0.75;
		float ink = clamp(l1 + l2, 0.0, 1.0);
		ink *= smoothstep(0.22, 0.58, brk);
		ink *= 1.0 - smoothstep(island_radius * 1.15, island_radius * 1.62, r);
		col = mix(col, c_ink, clamp(ink, 0.0, 1.0) * 0.45);
		// 岸边常驻泡沫带（跟着浪缓慢地涨落：涌上来、又退回去）
		float surge = 0.5 + 0.5 * sin(TIME * 0.36);
		float ring_r = island_radius * (0.99 + 0.075 * surge);
		float shore_foam = smoothstep(ring_r + 0.42, ring_r - 0.16, r)
			* (0.55 + 0.45 * brk);
		// 泡沫"生成又退去"：内侧边缘再叠一层游走的碎沫
		shore_foam *= 0.55 + 0.55 * fbm(adir * 4.0 + vec2(r * 1.9, -TIME * 0.50));
		col = mix(col, c_foam, clamp(shore_foam, 0.0, 1.0) * 0.82);

		ALBEDO = col;
		// 浅水半透明：看得见水下的沙底、石子、水草和焦散
		ALPHA = mix(1.0, 0.70, smoothstep(0.30, 0.95, shore));
		ROUGHNESS = 0.58 - surf * 0.05;
		METALLIC = 0.0;
		SPECULAR = 0.10;
		// 细微波纹法线 + 浪峰鼓起（幅度收小，否则会在着色上裂成一块块）
		float dx = (w2 - 0.5) * 0.05 * shimmer + (brk - 0.5) * surf * 0.12;
		float dy = (w - 0.5) * 0.05 * shimmer;
		NORMAL = normalize(NORMAL + vec3(dx, 0.0, dy + surf * 0.11));
	} else {
		// ---------- 剖切侧壁 ----------
		float t = clamp((vwp.y - water_bottom) / max(0.001, water_top - water_bottom), 0.0, 1.0);
		vec3 col = mix(c_deep * 0.55, c_cut, pow(t, 0.75));
		col = mix(col, c_foam, smoothstep(0.93, 1.0, t) * 0.55);
		// 底部沉积层
		col = mix(vec3(0.42, 0.46, 0.47), col, smoothstep(0.0, 0.22, t));
		ALBEDO = col;
		ALPHA = 1.0;
		ROUGHNESS = 0.45;
		METALLIC = 0.0;
		SPECULAR = 0.35;
	}
}
