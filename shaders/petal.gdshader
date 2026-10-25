// ============================================================
//  樱花花瓣：半透明卡片
//  · 形状在 UV 里画：椭圆 + 顶端缺刻（樱花花瓣的标志）
//  · BACKLIGHT 做透光 —— 逆光时花瓣会亮起来，这是日系樱花的关键
// ============================================================
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_lambert, specular_schlick_ggx, shadows_disabled;

uniform vec3 base_col : source_color = vec3(1.0, 0.84, 0.90);
uniform vec3 tip_col : source_color = vec3(1.0, 0.97, 0.98);
uniform float alpha_mul : hint_range(0.0, 1.0) = 0.80;
uniform float translucency : hint_range(0.0, 2.0) = 0.95;
uniform float soft = 0.055;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	// 椭圆轮廓
	float e = length(p * vec2(1.18, 1.0));
	// 顶端缺刻：在 +Y 处挖掉一个小圆
	float notch = length(p - vec2(0.0, 0.86));
	float a = smoothstep(1.0, 1.0 - soft * 3.0, e)
		* smoothstep(0.30, 0.30 + soft * 3.0, notch);
	// 中脉
	float vein = smoothstep(0.05, 0.0, abs(p.x)) * 0.22;
	// 根部深、尖端浅
	vec3 col = mix(base_col, tip_col, clamp(p.y * 0.5 + 0.5, 0.0, 1.0));
	col = mix(col, col * 0.93, vein);
	ALBEDO = col;
	ALPHA = a * alpha_mul;
	ROUGHNESS = 0.88;
	METALLIC = 0.0;
	SPECULAR = 0.25;
	BACKLIGHT = col * translucency;
}
