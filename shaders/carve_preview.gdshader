// ============================================================
//  雕刻画布的所见即所得预览（2D）。
//  参数与 carve_wood.gdshader 保持一致，玩家在平面图纸上作画，
//  3D 里的刀柄会同步出现同样的凹槽与填漆。
// ============================================================
shader_type canvas_item;

uniform sampler2D carve_tex : repeat_enable, filter_linear;
uniform vec3 wood_dark : source_color = vec3(0.23, 0.14, 0.08);
uniform vec3 wood_light : source_color = vec3(0.56, 0.35, 0.19);
uniform vec3 inlay_col : source_color = vec3(0.95, 0.78, 0.32);
uniform float carve_depth : hint_range(0.0, 1.0) = 0.65;
uniform float grain_scale = 34.0;

void fragment() {
	vec4 c = texture(carve_tex, UV);
	float h = clamp(c.r, 0.0, 1.0);
	float ink = clamp(c.g, 0.0, 1.0);
	// B 通道 = 镶嵌材料编号（和 3D 柄同一个解码）
	int ii = int(floor(c.b * 8.0 + 0.5));
	vec3 ic = vec3(0.95, 0.78, 0.32);
	if (ii == 1) {
		ic = vec3(0.88, 0.91, 0.95);
	} else if (ii == 2) {
		ic = vec3(0.93, 0.97, 1.0);
	} else if (ii == 3) {
		ic = vec3(0.74, 0.45, 0.22);
	} else if (ii == 4) {
		ic = vec3(0.12, 0.10, 0.09);
	} else if (ii == 5) {
		ic = vec3(0.62, 0.16, 0.12);
	}
	if (ink < 0.01) {
		ic = inlay_col;
	}

	float e = 0.0035;
	float gx = texture(carve_tex, UV + vec2(e, 0.0)).r - texture(carve_tex, UV - vec2(e, 0.0)).r;
	float gy = texture(carve_tex, UV + vec2(0.0, e)).r - texture(carve_tex, UV - vec2(0.0, e)).r;

	float rings = sin(UV.y * grain_scale * 0.45 + sin(UV.x * 5.0) * 1.6) * 0.5 + 0.5;
	float streak = sin(UV.x * 90.0 + UV.y * 4.0) * 0.5 + 0.5;
	vec3 col = mix(wood_dark, wood_light, 0.42 + 0.34 * rings + 0.10 * streak);

	col *= (1.0 - h * carve_depth);
	float ridge = clamp(length(vec2(gx, gy)) * 26.0, 0.0, 1.0);
	col += ridge * 0.30 * (1.0 - h);
	col = mix(col, ic, ink * 0.92);
	// 钻石给一点微光，2D 里也能看出区别
	if (ii == 2) {
		col += ic * 0.18 * ink;
	}

	COLOR = vec4(col, 1.0);
}
