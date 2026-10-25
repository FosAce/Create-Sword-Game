// ============================================================
//  描边：反向外壳（inverted hull）+ 屏幕空间恒定线宽
//  沿法线外扩的量乘上视空间距离 → 不管远近，屏幕上都是同样粗的一条线。
//  width 是"屏幕比例系数"：约 0.0016 ≈ 900p 下 2.6 px
// ============================================================
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled, fog_disabled;

uniform float width = 0.0016;
uniform vec3 line_col : source_color = vec3(0.16, 0.13, 0.12);

void vertex() {
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = max(-mv.z, 0.05);
	VERTEX += NORMAL * width * dist;
}

void fragment() {
	ALBEDO = line_col;
}
