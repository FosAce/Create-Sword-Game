// ============================================================
//  刀柄木料 + 玩家雕刻/填漆
//  carve_tex: R = 雕刻深度(0..1), G = 填漆/镶嵌(0..1)
//  UV: u = 绕柄一周, v = 沿柄方向
// ============================================================
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D carve_tex : repeat_enable, filter_linear;
uniform vec3 wood_dark : source_color = vec3(0.23, 0.14, 0.08);
uniform vec3 wood_light : source_color = vec3(0.56, 0.35, 0.19);
uniform vec3 inlay_col : source_color = vec3(0.95, 0.78, 0.32);
uniform float carve_depth : hint_range(0.0, 1.0) = 0.65;
uniform float grain_scale = 34.0;
uniform float wet : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(carve_tex, UV);
	float h = clamp(c.r, 0.0, 1.0);
	float ink = clamp(c.g, 0.0, 1.0);
	// B 通道存"镶嵌材料编号"：0 金 1 银 2 钻石 3 铜 4 黑漆 5 朱漆
	int ii = int(floor(c.b * 8.0 + 0.5));
	vec3 ic = vec3(0.95, 0.78, 0.32);
	float im = 0.95;
	float ir = 0.26;
	float ie = 0.0;
	if (ii == 1) {
		ic = vec3(0.88, 0.91, 0.95); im = 0.95; ir = 0.16;
	} else if (ii == 2) {
		// 钻石：几乎不反光的镜面 + 冷白自发光，看起来会闪
		ic = vec3(0.93, 0.97, 1.0); im = 0.10; ir = 0.04; ie = 1.60;
	} else if (ii == 3) {
		ic = vec3(0.74, 0.45, 0.22); im = 0.90; ir = 0.36;
	} else if (ii == 4) {
		ic = vec3(0.12, 0.10, 0.09); im = 0.0; ir = 0.42;
	} else if (ii == 5) {
		ic = vec3(0.62, 0.16, 0.12); im = 0.05; ir = 0.38;
	}
	if (ink < 0.01) {
		ic = inlay_col;
	}

	// UV 梯度 → 假凹凸
	float e = 0.0035;
	float gx = texture(carve_tex, UV + vec2(e, 0.0)).r - texture(carve_tex, UV - vec2(e, 0.0)).r;
	float gy = texture(carve_tex, UV + vec2(0.0, e)).r - texture(carve_tex, UV - vec2(0.0, e)).r;

	// 木纹
	float rings = sin(UV.y * grain_scale * 0.45 + sin(UV.x * 5.0) * 1.6) * 0.5 + 0.5;
	float streak = sin(UV.x * 90.0 + UV.y * 4.0) * 0.5 + 0.5;
	vec3 col = mix(wood_dark, wood_light, 0.42 + 0.34 * rings + 0.10 * streak);
	if (wet > 0.01) {
		col = mix(col, col * 1.9 + vec3(0.05, 0.03, 0.02), wet);
	}

	// 雕刻凹槽：变暗 + 棱边高光（雕刻刀走过留下的亮边）
	float dent = 1.0 - h * carve_depth;
	col *= dent;
	float ridge = clamp(length(vec2(gx, gy)) * 26.0, 0.0, 1.0);
	col += ridge * 0.30 * (1.0 - h);

	col = mix(col, ic, ink * 0.92);

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.52, 0.82, h), ir, ink);
	METALLIC = mix(0.0, im, ink);
	EMISSION = ic * ie * ink;
	SPECULAR = 0.45;
	NORMAL = normalize(NORMAL + vec3(-gx, -gy, 0.0) * 7.0 * carve_depth);
}
